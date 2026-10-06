import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct DocumentEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BillingDocument
    @State private var showPaywall = false
    @State private var showClientEditor = false
    init(document: BillingDocument) { _draft = State(initialValue: document) }
    private var paidAmount: Binding<Double> {
        Binding(get: { draft.paidAmount }, set: { amount in
            draft.depositAmount = amount == 0 ? nil : amount
            draft.alreadyPaidAmount = nil
        })
    }
    var body: some View { NavigationStack { Form {
        Section("Document") { Picker("Type", selection: $draft.type) { ForEach(DocumentType.allCases) { Text($0.title).tag($0) } }.onChange(of: draft.type) { _, type in if draft.number.isEmpty || !draft.number.hasPrefix(type.prefix) { draft.number = store.nextNumber(for: type, date: draft.issueDate) }; if type == .creditNote { for index in draft.items.indices { draft.items[index].unitPriceHT = -abs(draft.items[index].unitPriceHT) } } }; TextField("Numéro", text: $draft.number); DatePicker("Date d’émission", selection: $draft.issueDate, displayedComponents: .date); DatePicker("Échéance", selection: $draft.dueDate, displayedComponents: .date); DatePicker("Date de prestation", selection: $draft.serviceDate.orToday, displayedComponents: .date) }
        Section("Client") { Picker("Client", selection: $draft.clientID) { Text("Choisir un client").tag(""); ForEach(store.clients) { Text($0.displayName).tag($0.id) } }; Button("Ajouter un client") { showClientEditor = true } }
        Section("Facturation électronique") { Picker("Nature de l’opération", selection: $draft.operationCategory.orService) { ForEach(OperationCategory.allCases) { Text($0.title).tag(Optional($0)) } }; Toggle("TVA sur les débits", isOn: $draft.vatOnDebits.orFalse); Toggle("Adresse de livraison différente", isOn: Binding(get: { draft.deliveryAddress != nil }, set: { if !$0 { draft.deliveryAddress = nil } else { draft.deliveryAddress = PostalAddress() } })); if draft.deliveryAddress != nil { AddressFields(value: $draft.deliveryAddress) } }
        if !(store.profile.commercialEntities ?? []).isEmpty || !(store.clients.first { $0.id == draft.clientID }?.commercialEntities ?? []).isEmpty { Section("Entités commerciales") { if let entities = store.profile.commercialEntities, !entities.isEmpty { Picker("Émetteur", selection: $draft.issuerEntityID) { Text("Raison sociale principale").tag(String?.none); ForEach(entities) { entity in Text(entity.displayName).tag(Optional(entity.id)) } } }; if let entities = store.clients.first(where: { $0.id == draft.clientID })?.commercialEntities, !entities.isEmpty { Picker("Entité client", selection: $draft.clientEntityID) { Text("Client principal").tag(String?.none); ForEach(entities) { entity in Text(entity.displayName).tag(Optional(entity.id)) } } } } }
        Section("Prestations") {
            ForEach($draft.items) { $item in InvoiceItemEditor(item: $item) }.onDelete { draft.items.remove(atOffsets: $0) }
            Menu {
                Section("Catalogue") { ForEach(store.catalog) { item in Button(item.description) { draft.items.append(DocumentItem(description: item.description, unitPriceHT: item.unitPriceHT, vatRate: item.vatRate, unitLabel: item.unit)) } } }
                Section("Mission / personnel") {
                    Button("Heures de mission") { draft.items.append(DocumentItem(description: "Heures de mission", quantity: 1, unitPriceHT: 0, vatRate: 20, unitLabel: "h")) }
                    Button("Tickets restaurant") { draft.items.append(DocumentItem(description: "Tickets restaurant", quantity: 1, unitPriceHT: 0, vatRate: 20, unitLabel: "ticket")) }
                    Button("Indemnités de déplacement") { draft.items.append(DocumentItem(description: "Indemnités de déplacement", quantity: 1, unitPriceHT: 0, vatRate: 20, unitLabel: "jour")) }
                    Button("Indemnités kilométriques") { draft.items.append(DocumentItem(description: "Indemnités kilométriques", quantity: 1, unitPriceHT: 0, vatRate: 20, unitLabel: "km")) }
                    Button("Travaux au mètre linéaire") { draft.items.append(DocumentItem(description: "Travaux linéaires", quantity: 1, unitPriceHT: 0, vatRate: 20, unitLabel: "ml")) }
                    Button("Travaux au mètre cube") { draft.items.append(DocumentItem(description: "Travaux au mètre cube", quantity: 1, unitPriceHT: 0, vatRate: 20, unitLabel: "m³")) }
                }
                Button("Ligne vide") { draft.items.append(DocumentItem()) }
            } label: { Label("Ajouter une ligne", systemImage: "plus.circle.fill") }
        }
        if draft.type != .creditNote { Section("Remise") { TextField("Remise globale (%)", value: $draft.globalDiscountPercent.amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad); TextField("ou remise globale (€ HT)", value: $draft.globalDiscountAmount.amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad); Text("Utilisez soit un pourcentage, soit un montant. Le montant est prioritaire lorsqu’il est renseigné.").font(.caption).foregroundStyle(.secondary) } }
        Section("Référence d'affaire") { if draft.type == .creditNote { LabeledContent("Facture concernée", value: draft.sourceDocumentNumber ?? "À préciser"); TextField("Motif de l’avoir", text: $draft.creditReason.orEmpty, axis: .vertical).lineLimit(2...4) }; TextField("Titre / désignation (facultatif)", text: $draft.projectTitle.orEmpty); TextField("N° d'engagement ou contrat", text: $draft.projectReference.orEmpty); TextField("N° de bon de commande", text: $draft.purchaseOrderNumber.orEmpty) }
        if draft.type != .creditNote { Section("Règlement") { Picker("Devise", selection: $draft.currencyCode.orEmpty) { Text("Euro (€)").tag("EUR"); Text("Dollar américain ($)").tag("USD"); Text("Livre sterling (£)").tag("GBP"); Text("Franc suisse (CHF)").tag("CHF") }; TextField("Retenue de garantie / caution", value: $draft.retentionAmount.amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad); TextField("À déduire (déjà payé / acompte)", value: paidAmount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad) } }
        Section("Totaux") { if draft.globalDiscountValue > 0 { LabeledContent("Sous-total HT", value: Formatters.money(draft.subtotalHT, currencyCode: draft.currencyCode ?? store.profile.currencyCode)); LabeledContent("Remise globale", value: "− " + Formatters.money(draft.globalDiscountValue, currencyCode: draft.currencyCode ?? store.profile.currencyCode)) }; LabeledContent("Total HT", value: Formatters.money(draft.totalHT, currencyCode: draft.currencyCode ?? store.profile.currencyCode)); LabeledContent("TVA", value: Formatters.money(draft.totalVAT, currencyCode: draft.currencyCode ?? store.profile.currencyCode)); LabeledContent(draft.type == .creditNote ? "Total avoir TTC" : "Total TTC") { Text(Formatters.money(draft.totalTTC, currencyCode: draft.currencyCode ?? store.profile.currencyCode)).bold() }; if draft.type == .creditNote { LabeledContent("Avoir à déduire") { Text(Formatters.money(draft.creditAmount, currencyCode: draft.currencyCode ?? store.profile.currencyCode)).bold() } } else { if (draft.retentionAmount ?? 0) > 0 { LabeledContent("Retenue / caution", value: "− " + Formatters.money(draft.retentionAmount ?? 0, currencyCode: draft.currencyCode ?? store.profile.currencyCode)) }; if draft.paidAmount > 0 { LabeledContent("À déduire (déjà payé / acompte)", value: "− " + Formatters.money(draft.paidAmount, currencyCode: draft.currencyCode ?? store.profile.currencyCode)) }; LabeledContent("Net à payer") { Text(Formatters.money(draft.netToPay, currencyCode: draft.currencyCode ?? store.profile.currencyCode)).bold() } } }
        Section("Informations complémentaires") { TextField("Notes (facultatif)", text: $draft.notes, axis: .vertical).lineLimit(3...6) }
    }.navigationTitle(draft.number.isEmpty ? "Nouveau document" : draft.number).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() }.disabled(draft.number.isEmpty || draft.items.isEmpty) } } }.onAppear { if draft.currencyCode == nil { draft.currencyCode = store.profile.currencyCode } }.sheet(isPresented: $showClientEditor) { ClientEditor() }.sheet(isPresented: $showPaywall) { PaywallView() } }
    private func save() { store.saveDocument(draft); dismiss() }
}

struct InvoiceItemEditor: View { @Binding var item: DocumentItem
    var body: some View { VStack(alignment: .leading) { TextField("Description", text: $item.description); TextField("Note de ligne (facultatif)", text: $item.note.orEmpty, axis: .vertical).lineLimit(1...3); HStack { TextField("Qté", value: $item.quantity, format: .number).keyboardType(.decimalPad); Picker("Unité", selection: $item.unitLabel.orEmpty) { Text("Heure").tag("h"); Text("Jour").tag("jour"); Text("Ticket").tag("ticket"); Text("Kilomètre").tag("km"); Text("Mètre linéaire").tag("ml"); Text("Mètre cube").tag("m³"); Text("Forfait").tag("forfait"); Text("Unité").tag("unité") }.labelsHidden(); TextField("Prix HT", value: $item.unitPriceHT, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad); Picker("TVA", selection: $item.vatRate) { Text("0 %").tag(0.0); Text("5,5 %").tag(5.5); Text("10 %").tag(10.0); Text("20 %").tag(20.0) }.labelsHidden() }; TextField("Remise ligne (%)", value: $item.discountPercent.amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad); Text("Total : \(Formatters.money(item.totalLineHT)) HT").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 3) }
}

struct ClientsView: View { @EnvironmentObject private var store: AppStore; @State private var create = false
    var body: some View { NavigationStack { List { ForEach(store.clients) { client in NavigationLink { ClientEditor(client: client) } label: { VStack(alignment: .leading) { Text(client.displayName).font(.headline); if !client.email.isEmpty { Text(client.email).font(.caption).foregroundStyle(.secondary) } } } }.onDelete { index in index.map { store.clients[$0] }.forEach(store.deleteClient) } }.contentMargins(.bottom, 72, for: .scrollContent).overlay { if store.clients.isEmpty { ContentUnavailableView("Aucun client", systemImage: "person.crop.circle.badge.plus", description: Text("Ajoutez vos premiers clients pour facturer plus vite.")) } }.navigationTitle("Clients").toolbar { ToolbarItem(placement: .topBarTrailing) { Button { create = true } label: { Image(systemName: "plus") } } } }.sheet(isPresented: $create) { ClientEditor() } }
}

struct ClientEditor: View { @EnvironmentObject private var store: AppStore; @Environment(\.dismiss) private var dismiss; @State private var draft: Client; @State private var contactEditor: ClientContact?; @State private var selectedLogo: PhotosPickerItem?
    init(client: Client = Client()) { _draft = State(initialValue: client) }
    var body: some View { NavigationStack { Form {
        Section("Identité") { TextField("Entreprise", text: $draft.companyName); TextField("Forme juridique (facultatif)", text: $draft.legalForm.orEmpty); TextField("Contact principal", text: $draft.contactName) }
        Section("Adresse") { AddressFields(value: $draft.addressDetails); TextField("Adresse libre (ancienne donnée)", text: $draft.address, axis: .vertical).lineLimit(2...4) }
        Section("Coordonnées") { TextField("Email", text: $draft.email).keyboardType(.emailAddress).textInputAutocapitalization(.never); TextField("Téléphone", text: $draft.phone).keyboardType(.phonePad); TextField("SIRET (facultatif)", text: $draft.siret).keyboardType(.numberPad); TextField("SIREN (facturation électronique)", text: $draft.siren.orEmpty).keyboardType(.numberPad); TextField("N° TVA intracommunautaire", text: $draft.vatNumber.orEmpty) }
        Section("Livraison") { Toggle("Adresse de livraison différente", isOn: Binding(get: { draft.deliveryAddress != nil }, set: { if !$0 { draft.deliveryAddress = nil } else { draft.deliveryAddress = PostalAddress() } })); if draft.deliveryAddress != nil { AddressFields(value: $draft.deliveryAddress) } }
        Section("Logo client") { PhotosPicker(selection: $selectedLogo, matching: .images) { Label(draft.logoPath?.isEmpty == false ? "Remplacer le logo" : "Choisir un logo", systemImage: "photo") }; if let path = draft.logoPath, !path.isEmpty { Text("Logo local sélectionné").font(.caption).foregroundStyle(.secondary) } }
        Section("Contacts liés") {
            ForEach(draft.contacts) { contact in Button { contactEditor = contact } label: { VStack(alignment: .leading) { Text(contact.name.isEmpty ? "Contact sans nom" : contact.name); Text([contact.role, contact.email, contact.phone].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) } }.foregroundStyle(.primary) }.onDelete { draft.contacts.remove(atOffsets: $0) }
            Button { contactEditor = ClientContact() } label: { Label("Ajouter un contact", systemImage: "person.badge.plus") }
        }
    }.navigationTitle("Client").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { if let address = draft.addressDetails { draft.address = address.formatted }; store.saveClient(draft); dismiss() }.disabled(draft.displayName.isEmpty) } } }.task(id: selectedLogo) { if let selectedLogo, let data = try? await selectedLogo.loadTransferable(type: Data.self) { draft.logoPath = try? LogoStore.save(data) } }.sheet(item: $contactEditor) { contact in ClientContactEditor(contact: contact) { saved in if let index = draft.contacts.firstIndex(where: { $0.id == saved.id }) { draft.contacts[index] = saved } else { draft.contacts.append(saved) } } } }
}

struct ClientContactEditor: View { @Environment(\.dismiss) private var dismiss; @State private var draft: ClientContact; let onSave: (ClientContact) -> Void
    init(contact: ClientContact, onSave: @escaping (ClientContact) -> Void) { _draft = State(initialValue: contact); self.onSave = onSave }
    var body: some View { NavigationStack { Form { TextField("Nom", text: $draft.name); TextField("Fonction", text: $draft.role); TextField("Email", text: $draft.email).keyboardType(.emailAddress).textInputAutocapitalization(.never); TextField("Téléphone", text: $draft.phone).keyboardType(.phonePad) }.navigationTitle("Contact lié").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { onSave(draft); dismiss() }.disabled(draft.name.isEmpty) } } } }
}

struct AddressFields: View {
    @Binding var value: PostalAddress?
    private var address: Binding<PostalAddress> { Binding(get: { value ?? PostalAddress() }, set: { value = $0 }) }
    var body: some View {
        TextField("Numéro", text: address.number)
        TextField("Rue", text: address.street)
        HStack { TextField("Code postal", text: address.postalCode).keyboardType(.numbersAndPunctuation); TextField("Ville", text: address.city) }
        TextField("Pays", text: address.country)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var profileEditor = false
    @State private var isImporter = false
    @State private var shareURL: URL?
    @State private var backupPreview: BackupImportPreview?
    @State private var studioNotice = false
    @State private var reminderMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Entreprise") {
                    Button { profileEditor = true } label: {
                        LabeledContent("Profil", value: store.profile.name.isEmpty ? "À compléter" : store.profile.name)
                    }
                }
                Section("Catalogue") {
                    NavigationLink("Prestations et produits") { CatalogView() }
                    NavigationLink("Modèles de documents") { TemplatesView() }
                }
                Section("Sauvegarde") {
                    Button { shareURL = try? store.exportBackup() } label: {
                        Label("Exporter mes données", systemImage: "square.and.arrow.up")
                    }
                    Button { isImporter = true } label: {
                        Label("Importer une sauvegarde", systemImage: "square.and.arrow.down")
                    }
                    Button { shareURL = try? store.exportAccountingCSV() } label: {
                        Label("Exporter le journal comptable (CSV)", systemImage: "tablecells")
                    }
                }
                Section("Synchronisation") {
                    if store.hasAdvancedAccess {
                        Toggle("Synchroniser avec iCloud", isOn: Binding(get: { store.iCloudSyncEnabled }, set: store.setICloudSyncEnabled))
                        Text("Vos données sont chiffrées et stockées dans votre espace iCloud privé, sans serveur CashDraft. La version la plus récente prévaut en cas de modifications sur plusieurs appareils.").font(.footnote).foregroundStyle(.secondary)
                        HStack { Text("État"); Spacer(); Text(store.iCloudSyncStatus).foregroundStyle(.secondary) }
                        if store.iCloudSyncEnabled { Button("Synchroniser maintenant") { Task { await store.syncWithICloud() } } }
                    } else { StudioLockedRow(title: "Synchronisation iCloud", subtitle: "Disponible avec CashDraft Studio") { showStudioNotice() } }
                }
                Section("Relances") {
                    Button("Activer les relances d’échéance") { Task { reminderMessage = await store.enableDueDateReminders() ? "Relances activées : 7 jours avant, à échéance et en retard." : "Autorisez les notifications dans Réglages iOS pour activer les relances." } }
                    Text("Notifications locales uniquement : aucune facture ni donnée n’est envoyée à un serveur.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Corbeille") {
                    NavigationLink {
                        TrashView()
                    } label: {
                        HStack {
                            Label("Documents supprimés", systemImage: "trash")
                            Spacer()
                            if !store.trashedDocuments.isEmpty {
                                Text("\(store.trashedDocuments.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Facturation") {
                    NavigationLink { PaywallView() } label: {
                        HStack {
                            Label("Mes crédits et CashDraft Pro", systemImage: "creditcard")
                            Spacer()
                            Text(billingStatus)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Studio") {
                    if store.hasAdvancedAccess { NavigationLink("Statistiques", destination: StatisticsView()) }
                    else { StudioLockedRow(title: "Statistiques et pilotage", subtitle: "Disponible avec CashDraft Studio") { showStudioNotice() } }
                }
                Section("À propos") {
                    NavigationLink {
                        AboutCashDraftView()
                    } label: {
                        Label("Calculs et responsabilité", systemImage: "info.circle")
                    }
                    Text("Vos données restent sur cet appareil, sauf si vous activez la synchronisation iCloud. L’export reste sous votre contrôle.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .contentMargins(.bottom, 72, for: .scrollContent)
            .navigationTitle("Réglages")
        }
        .sheet(isPresented: $profileEditor) { ProfileEditor() }
        .sheet(isPresented: $isImporter) { BackupImporter { url in
            do { backupPreview = try store.previewBackup(from: url) }
            catch { store.errorMessage = "Cette sauvegarde CashDraft est illisible ou incompatible." }
        } }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ShareSheet(url: shareURL) }
        }
        .confirmationDialog("Remplacer les données locales ?", isPresented: Binding(get: { backupPreview != nil }, set: { if !$0 { backupPreview = nil } }), titleVisibility: .visible) {
            Button("Importer et remplacer", role: .destructive) {
                guard let preview = backupPreview else { return }
                do { try store.importBackup(from: preview.url) }
                catch { store.errorMessage = "L’import a échoué. Les données locales n’ont pas été modifiées." }
                backupPreview = nil
            }
            Button("Annuler", role: .cancel) { backupPreview = nil }
        } message: {
            if let preview = backupPreview {
                Text("Sauvegarde du \(Formatters.date.string(from: preview.exportDate)) — \(preview.profileName), \(preview.clientCount) client(s), \(preview.documentCount) document(s) actif(s) et \(preview.trashedDocumentCount) dans la corbeille. Cette action remplace les données actuellement sur cet appareil.")
            }
        }
        .overlay(alignment: .bottom) { if studioNotice { StudioToast() } }
        .alert("Relances", isPresented: Binding(get: { reminderMessage != nil }, set: { if !$0 { reminderMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(reminderMessage ?? "") }
    }
    private func showStudioNotice() { studioNotice = true; Task { try? await Task.sleep(for: .seconds(2.5)); studioNotice = false } }
    private var billingStatus: String {
        if store.isStudioActive { return "Studio actif" }
        if store.license.isProUnlocked { return "Pro Lifetime" }
        if store.trialDocumentsRemaining > 0 { return "Essai : \(store.trialDocumentsRemaining) docs" }
        if store.license.remainingCredits > 0 { return "\(store.license.remainingCredits) crédits" }
        return "Brouillons gratuits"
    }
}

struct TrashView: View {
    @EnvironmentObject private var store: AppStore
    @State private var documentToDelete: BillingDocument?
    @State private var isEmptyingTrash = false

    var body: some View {
        List {
            if store.trashedDocuments.isEmpty {
                ContentUnavailableView(
                    "Corbeille vide",
                    systemImage: "trash",
                    description: Text("Les documents supprimés restent ici jusqu’à leur restauration ou leur suppression définitive.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.trashedDocuments) { document in
                        VStack(alignment: .leading, spacing: 10) {
                            DocumentRow(document: document, client: store.clients.first { $0.id == document.clientID })
                            HStack {
                                Button("Restaurer") {
                                    store.restoreDocument(document)
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Button("Supprimer définitivement", role: .destructive) {
                                    documentToDelete = document
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Un document supprimé définitivement ne peut pas être récupéré. Les numéros de documents ne sont jamais réutilisés.")
                }
            }
        }
        .contentMargins(.bottom, 72, for: .scrollContent)
        .navigationTitle("Corbeille")
        .toolbar {
            if !store.trashedDocuments.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Vider", role: .destructive) {
                        isEmptyingTrash = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Supprimer définitivement ce document ?",
            isPresented: Binding(get: { documentToDelete != nil }, set: { if !$0 { documentToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer définitivement", role: .destructive) {
                if let documentToDelete { store.permanentlyDeleteDocument(documentToDelete) }
                documentToDelete = nil
            }
            Button("Annuler", role: .cancel) { documentToDelete = nil }
        } message: {
            Text("Cette action est irréversible.")
        }
        .confirmationDialog(
            "Vider la corbeille ?",
            isPresented: $isEmptyingTrash,
            titleVisibility: .visible
        ) {
            Button("Vider définitivement la corbeille", role: .destructive) {
                store.emptyTrash()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous les documents présents dans la corbeille seront supprimés définitivement.")
        }
    }
}

struct AboutCashDraftView: View {
    var body: some View {
        List {
            Section("Comment les calculs sont faits") {
                Text("Pour chaque ligne, CashDraft calcule le montant HT en multipliant la quantité par le prix unitaire HT.")
                Text("La TVA de chaque ligne est calculée à partir de son taux de TVA, puis additionnée. Le total TTC correspond au total HT augmenté de la TVA.")
                Text("Le net à payer correspond au TTC, moins la retenue de garantie ou caution éventuelle et moins le montant déjà payé ou l’acompte. Il ne peut pas être négatif.")
                Text("Pour un avoir, les lignes sont négatives et le montant à déduire correspond à la valeur TTC de l’avoir.")
            }
            Section("Important") {
                Label("CashDraft automatise les calculs à partir des données saisies. Il ne fournit pas de conseil juridique, fiscal ou comptable.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Avant émission ou envoi, vérifiez les montants, la TVA, la numérotation, les mentions obligatoires et la conformité de chaque document à votre situation.")
            }
            Section("Données et confidentialité") {
                Text("Les données métier sont conservées localement sur votre appareil. Les sauvegardes et partages PDF ou JSON sont déclenchés et contrôlés par vous.")
            }
            Section {
                Text("CashDraft 1.0")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentMargins(.bottom, 72, for: .scrollContent)
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProfileEditor: View { @EnvironmentObject private var store: AppStore; @Environment(\.dismiss) private var dismiss; @State private var draft: CompanyProfile; @State private var selectedLogo: PhotosPickerItem?; @State private var studioNotice = false
    init() { _draft = State(initialValue: CompanyProfile()) }
    var body: some View { NavigationStack { Form {
        Section("Entreprise") { TextField("Nom ou raison sociale", text: $draft.name); TextField("Statut juridique", text: $draft.legalForm); TextField("SIRET", text: $draft.siret).keyboardType(.numberPad); TextField("Capital social (facultatif)", text: $draft.shareCapital.orEmpty); TextField("Ville RCS (facultatif)", text: $draft.rcsCity.orEmpty); TextField("N° RCS (facultatif)", text: $draft.rcsNumber.orEmpty) }
        Section("Adresse") { AddressFields(value: $draft.addressDetails); TextField("Adresse libre (ancienne donnée)", text: $draft.address, axis: .vertical).lineLimit(2...4) }
        Section("Contact") { TextField("Email", text: $draft.email).keyboardType(.emailAddress); TextField("Téléphone", text: $draft.phone).keyboardType(.phonePad) }
        Section("Identité visuelle") { if store.hasAdvancedAccess { PhotosPicker(selection: $selectedLogo, matching: .images) { Label(draft.logoPath.isEmpty ? "Choisir le logo émetteur" : "Remplacer le logo émetteur", systemImage: "photo") }; TextField("Couleur principale (#0A1A33)", text: $draft.brandColorHex.orEmpty).textInputAutocapitalization(.characters); Picker("Police PDF par défaut", selection: $draft.pdfFontName.orEmpty) { Text("Helvetica Neue").tag("HelveticaNeue"); Text("Avenir Next").tag("AvenirNext-Regular"); Text("Georgia").tag("Georgia"); Text("Courier New").tag("CourierNewPSMT") } } else { StudioLockedRow(title: "Logo, couleur et police", subtitle: "Disponible avec CashDraft Studio") { showStudioNotice() } }; Picker("Devise par défaut", selection: $draft.currencyCode) { Text("Euro (€)").tag("EUR"); Text("Dollar américain ($)").tag("USD"); Text("Livre sterling (£)").tag("GBP"); Text("Franc suisse (CHF)").tag("CHF") } }
        Section("TVA et règlement") { TextField("N° TVA intracommunautaire", text: $draft.vatNumber); TextField("Mention TVA", text: $draft.vatExemptionNotice, axis: .vertical); TextField("Conditions de règlement", text: $draft.defaultPaymentTerms); TextField("IBAN (facultatif)", text: $draft.iban.orEmpty); TextField("BIC (facultatif)", text: $draft.bic.orEmpty); TextField("Escompte paiement anticipé", text: $draft.earlyPaymentDiscountText.orEmpty); TextField("Pénalités de retard", text: $draft.latePaymentPenaltyText.orEmpty); TextField("Indemnité de recouvrement", text: $draft.recoveryIndemnityText.orEmpty) }
        Section("Numérotation") { TextField("Préfixe factures", text: $draft.invoicePrefix.orEmpty); TextField("Préfixe devis", text: $draft.quotePrefix.orEmpty); TextField("Préfixe avoirs", text: $draft.creditNotePrefix.orEmpty); TextField("Préfixe honoraires", text: $draft.honorariumPrefix.orEmpty); Text("Format : PRÉFIXE-ANNÉE-NUMÉRO. Les numéros déjà créés ne sont jamais modifiés.").font(.caption).foregroundStyle(.secondary) }
        Section("Pied de page") { TextField("Texte affiché en bas des documents", text: $draft.footerText.orEmpty, axis: .vertical).lineLimit(3...6) }
    }.navigationTitle("Profil entreprise").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { if let address = draft.addressDetails { draft.address = address.formatted }; store.saveProfile(draft); dismiss() } } }.onAppear { draft = store.profile }.task(id: selectedLogo) { if let selectedLogo, let data = try? await selectedLogo.loadTransferable(type: Data.self), let path = try? LogoStore.save(data) { draft.logoPath = path } } }.overlay(alignment: .bottom) { if studioNotice { StudioToast() } } }
    private func showStudioNotice() { studioNotice = true; Task { try? await Task.sleep(for: .seconds(2.5)); studioNotice = false } }
}

struct StudioLockedRow: View { let title: String; let subtitle: String; let action: () -> Void
    var body: some View { Button(action: action) { HStack { Image(systemName: "lock.fill"); VStack(alignment: .leading) { Text(title); Text(subtitle).font(.caption) }; Spacer(); Image(systemName: "chevron.right") }.foregroundStyle(.secondary).opacity(0.72) }.buttonStyle(.plain) }
}

struct StudioToast: View { var body: some View { Label("Disponible avec CashDraft Studio", systemImage: "lock.fill").font(.footnote.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10).background(.regularMaterial, in: Capsule()).shadow(radius: 8).padding(.bottom, 28) } }

struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore
    private var issued: [BillingDocument] { store.documents.filter { $0.status != .draft && $0.type != .quote } }
    private var totalBilled: Double { issued.reduce(0) { $0 + $1.totalTTC } }
    private var totalReceived: Double { issued.reduce(0) { $0 + $1.paidAmount } }
    private var outstanding: Double { issued.filter { $0.status == .sent }.reduce(0) { $0 + $1.netToPay } }
    private var vat: Double { issued.reduce(0) { $0 + $1.totalVAT } }
    private var topClients: [(String, Double)] {
        var totals: [String: Double] = [:]
        for document in issued {
            let name = store.clients.first(where: { $0.id == document.clientID })?.displayName ?? "Client non renseigné"
            totals[name, default: 0] += document.totalTTC
        }
        return totals.map { (name: $0.key, total: $0.value) }.sorted { $0.total > $1.total }.prefix(5).map { ($0.name, $0.total) }
    }
    var body: some View { List {
        Section("Vue d’ensemble") { LabeledContent("Facturé", value: Formatters.money(totalBilled)); LabeledContent("Encaissé", value: Formatters.money(totalReceived)); LabeledContent("À encaisser", value: Formatters.money(outstanding)); LabeledContent("TVA collectée estimée", value: Formatters.money(vat)) }
        Section("Meilleurs clients") { if topClients.isEmpty { Text("Aucune facture émise.").foregroundStyle(.secondary) } else { ForEach(Array(topClients.enumerated()), id: \.offset) { _, entry in LabeledContent(entry.0, value: Formatters.money(entry.1)) } } }
    }.navigationTitle("Statistiques") }
}

struct CatalogView: View { @EnvironmentObject private var store: AppStore; @State private var item: CatalogItem?
    var body: some View { List { ForEach(store.catalog) { entry in Button { item = entry } label: { HStack { VStack(alignment: .leading) { Text(entry.description); Text("TVA \(entry.vatRate.formatted()) %").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(Formatters.money(entry.unitPriceHT)) } }.foregroundStyle(.primary) }.onDelete { index in index.map { store.catalog[$0] }.forEach(store.deleteCatalogItem) } }.navigationTitle("Catalogue").toolbar { ToolbarItem(placement: .topBarTrailing) { Button { item = CatalogItem() } label: { Image(systemName: "plus") } } }.sheet(item: $item) { CatalogItemEditor(item: $0) } }
}
struct TemplatesView: View { @EnvironmentObject private var store: AppStore; @State private var document: BillingDocument?
    var body: some View { List { if store.templates.isEmpty { ContentUnavailableView("Aucun modèle", systemImage: "bookmark", description: Text("Enregistrez un devis ou une facture comme modèle depuis son écran.")) } else { ForEach(store.templates) { template in Button { document = store.draft(from: template) } label: { VStack(alignment: .leading) { Text(template.name); Text(template.document.type.title).font(.caption).foregroundStyle(.secondary) } }.foregroundStyle(.primary) }.onDelete { index in index.map { store.templates[$0] }.forEach(store.deleteTemplate) } } }.navigationTitle("Modèles").sheet(item: $document) { DocumentEditor(document: $0) } }
}
struct CatalogItemEditor: View { @EnvironmentObject private var store: AppStore; @Environment(\.dismiss) private var dismiss; @State private var draft: CatalogItem
    init(item: CatalogItem) { _draft = State(initialValue: item) }
    var body: some View { NavigationStack { Form { TextField("Libellé", text: $draft.description); Picker("Unité", selection: $draft.unit) { Text("Heure").tag("h"); Text("Jour").tag("jour"); Text("Ticket").tag("ticket"); Text("Kilomètre").tag("km"); Text("Mètre linéaire").tag("ml"); Text("Mètre cube").tag("m³"); Text("Forfait").tag("forfait"); Text("Unité").tag("unité") }; TextField("Prix unitaire HT", value: $draft.unitPriceHT, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad); Picker("TVA", selection: $draft.vatRate) { Text("0 %").tag(0.0); Text("5,5 %").tag(5.5); Text("10 %").tag(10.0); Text("20 %").tag(20.0) } }.navigationTitle("Prestation").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { store.saveCatalogItem(draft); dismiss() }.disabled(draft.description.isEmpty) } } } }
}
struct BackupImporter: UIViewControllerRepresentable { let completion: (URL) -> Void; func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }; func makeUIViewController(context: Context) -> UIDocumentPickerViewController { let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json]); picker.delegate = context.coordinator; return picker }; func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}; final class Coordinator: NSObject, UIDocumentPickerDelegate { let completion: (URL) -> Void; init(completion: @escaping (URL) -> Void) { self.completion = completion }; func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { guard let url = urls.first else { return }; guard url.startAccessingSecurityScopedResource() else { return }; completion(url); url.stopAccessingSecurityScopedResource() } } }

private extension Binding where Value == String? {
    var orEmpty: Binding<String> { Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0.isEmpty ? nil : $0 }) }
}

private extension Binding where Value == Double? {
    var amount: Binding<Double> { Binding<Double>(get: { wrappedValue ?? 0 }, set: { wrappedValue = $0 == 0 ? nil : $0 }) }
}

private extension Binding where Value == Bool? {
    var orFalse: Binding<Bool> { Binding<Bool>(get: { wrappedValue ?? false }, set: { wrappedValue = $0 }) }
}

private extension Binding where Value == OperationCategory? {
    var orService: Binding<OperationCategory?> { Binding<OperationCategory?>(get: { wrappedValue ?? .service }, set: { wrappedValue = $0 }) }
}

private extension Binding where Value == Date? {
    var orToday: Binding<Date> { Binding<Date>(get: { wrappedValue ?? Date() }, set: { wrappedValue = $0 }) }
}

enum LogoStore {
    static func save(_ data: Data) throws -> String {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("CashDraft/Logos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try data.write(to: destination, options: .atomic)
        return destination.path
    }
}
