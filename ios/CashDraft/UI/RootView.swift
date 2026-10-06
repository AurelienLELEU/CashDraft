import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection = 0
    @State private var showNewDocument = false
    @State private var showStorefrontPaywall = false
    @State private var newDocumentType: DocumentType = .invoice
    @State private var documentStatusFilter: DocumentStatus?
    @State private var screenshotDestination: ScreenshotDestination?

    var body: some View {
        Group {
            if store.isReady {
                TabView(selection: $selection) {
                    LegalNoticeContainer {
                        DashboardView(showNewDocument: $showNewDocument, newDocumentType: $newDocumentType) { status in
                            documentStatusFilter = status
                            selection = 1
                        }
                    }.tabItem { Label("Accueil", systemImage: "house.fill") }.tag(0)
                    LegalNoticeContainer {
                        DocumentsView(statusFilter: $documentStatusFilter)
                    }.tabItem { Label("Documents", systemImage: "doc.text.fill") }.tag(1)
                    LegalNoticeContainer {
                        ClientsView()
                    }.tabItem { Label("Clients", systemImage: "person.2.fill") }.tag(2)
                    LegalNoticeContainer {
                        SettingsView()
                    }.tabItem { Label("Réglages", systemImage: "gearshape.fill") }.tag(3)
                }
                .tint(Color(hex: store.profile.brandColorHex) ?? Color(red: 0.12, green: 0.65, blue: 0.52))
                .sheet(isPresented: $showNewDocument) { DocumentEditor(document: BillingDocument(type: newDocumentType, number: store.nextNumber(for: newDocumentType))) }
                .sheet(isPresented: $showStorefrontPaywall) { PaywallView() }
                .fullScreenCover(item: $screenshotDestination) { destination in
                    switch destination {
                    case .invoice:
                        DocumentDetailView(document: store.documents.first { $0.type == .invoice } ?? BillingDocument())
                    case .editor:
                        DocumentEditor(document: BillingDocument(type: .invoice, number: store.nextNumber(for: .invoice)))
                    case .preview:
                        if let document = store.documents.first(where: { $0.type == .invoice }), let url = store.pdfURL(for: document) { PDFPreviewSheet(url: url) }
                    case .trash:
                        NavigationStack { TrashView() }
                    case .statistics:
                        NavigationStack { StatisticsView() }
                    }
                }
                .onAppear {
                    switch ProcessInfo.processInfo.environment["CASHDRAFT_SCREENSHOT_TAB"] {
                    case "documents": selection = 1
                    case "clients": selection = 2
                    case "settings": selection = 3
                    default: break
                    }
                    if ProcessInfo.processInfo.environment["CASHDRAFT_SCREENSHOT_DOCUMENT_STATUS"] == "sent" {
                        documentStatusFilter = .sent
                    }
                    if ProcessInfo.processInfo.environment["CASHDRAFT_SCREENSHOT_PAYWALL"] == "1" { showStorefrontPaywall = true }
                    switch ProcessInfo.processInfo.environment["CASHDRAFT_SCREENSHOT_SCREEN"] {
                    case "invoice": screenshotDestination = .invoice
                    case "editor": screenshotDestination = .editor
                    case "preview": screenshotDestination = .preview
                    case "trash": screenshotDestination = .trash
                    case "statistics": screenshotDestination = .statistics
                    default: break
                    }
                }
            } else { ProgressView("Préparation de CashDraft…") }
        }
        .alert("CashDraft", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "") }
    }
}

private enum ScreenshotDestination: String, Identifiable {
    case invoice, editor, preview, trash, statistics
    var id: String { rawValue }
}

private struct LegalNoticeContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .safeAreaPadding(.bottom, 34)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComplianceNotice()
            }
    }
}

struct ComplianceNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption2)
            Text("Vérifiez vos documents : vos saisies déterminent les calculs et vous restez responsable de leur conformité.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showNewDocument: Bool
    @Binding var newDocumentType: DocumentType
    let openDocuments: (DocumentStatus) -> Void
    private var unpaid: [BillingDocument] { store.documents.filter { ($0.type == .invoice || $0.type == .honorariumNote) && $0.status == .sent } }
    private var outstanding: Double { store.documents.filter { $0.status == .sent && ($0.type == .invoice || $0.type == .honorariumNote || $0.type == .creditNote) }.reduce(0) { $0 + $1.totalTTC } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) { Text("Bonjour").font(.title3); Text(store.profile.name.isEmpty ? "Prêt à facturer ?" : store.profile.name).font(.largeTitle.bold()) }
                    HStack(spacing: 12) {
                        Button { openDocuments(.sent) } label: { MetricCard(title: "À encaisser", value: Formatters.money(outstanding), icon: "eurosign.circle.fill", color: .orange) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Ouvre les documents envoyés à encaisser")
                        Button { openDocuments(.sent) } label: { MetricCard(title: "En attente", value: "\(unpaid.count)", icon: "clock.fill", color: .blue) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Ouvre les documents envoyés en attente de paiement")
                    }
                    if !store.license.isProUnlocked { CreditBanner() }
                    Text("Factures récentes").font(.headline)
                    if store.documents.isEmpty { ContentUnavailableView("Aucun document", systemImage: "doc.badge.plus", description: Text("Créez votre première facture en moins d’une minute."))
                    } else { ForEach(store.documents.prefix(5)) { document in NavigationLink { DocumentDetailView(document: document) } label: { DocumentRow(document: document, client: store.clients.first(where: { $0.id == document.clientID })) }.buttonStyle(.plain) } }
                }
                .padding()
                .padding(.bottom, 72)
            }
            .navigationTitle("CashDraft")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nouvelle facture") { newDocumentType = .invoice; showNewDocument = true }
                        Button("Nouveau devis") { newDocumentType = .quote; showNewDocument = true }
                        Button("Nouvelle note d’honoraires") { newDocumentType = .honorariumNote; showNewDocument = true }
                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
            }
        }
    }
}

private struct MetricCard: View { let title: String; let value: String; let icon: String; let color: Color
    var body: some View { VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).foregroundStyle(color); Text(value).font(.title3.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16)) }
}
private struct CreditBanner: View { @EnvironmentObject private var store: AppStore
    var body: some View { NavigationLink(destination: PaywallView()) { HStack { Image(systemName: "bolt.circle.fill").foregroundStyle(.mint); VStack(alignment: .leading) { Text(bannerTitle).font(.subheadline.bold()); Text(bannerSubtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }.padding().background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain) }
    private var bannerTitle: String { store.trialDocumentsRemaining > 0 ? "\(store.trialDocumentsRemaining) documents d’essai restants" : store.license.remainingCredits > 0 ? "\(store.license.remainingCredits) documents restants" : "Brouillons gratuits illimités" }
    private var bannerSubtitle: String { store.trialDocumentsRemaining > 0 ? "Toutes les fonctions sont incluses pendant l’essai." : store.license.remainingCredits > 0 ? "Émettez vos documents de base quand vous voulez." : "Passez à Pro ou Studio pour émettre un nouveau document." }
}

struct DocumentRow: View { let document: BillingDocument; let client: Client?
    var body: some View { HStack { Image(systemName: document.type == .invoice ? "doc.text.fill" : document.type == .honorariumNote ? "person.text.rectangle.fill" : document.type == .creditNote ? "arrow.uturn.backward.circle.fill" : "doc.plaintext.fill").foregroundStyle(document.type == .invoice ? .blue : document.type == .honorariumNote ? .teal : document.type == .creditNote ? .purple : .orange).frame(width: 30); VStack(alignment: .leading) { Text(document.number).font(.subheadline.bold()); Text(client?.displayName ?? "Client à préciser").font(.caption).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing) { Text(document.type == .creditNote ? "Avoir : " + Formatters.money(document.creditAmount) : Formatters.money(document.totalTTC)).font(.subheadline.bold()); Text(document.status.title).font(.caption).foregroundStyle(document.status == .paid ? .green : .secondary) } }.padding(.vertical, 7) }
}

struct DocumentsView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var statusFilter: DocumentStatus?
    @State private var type: DocumentType = .invoice
    @State private var editor: BillingDocument?
    @State private var query = ""
    @State private var clientID = ""
    @State private var dateFilter: DocumentDateFilter = .all
    @State private var sort: DocumentSort = .dateNewest
    @State private var documentPendingDeletion: BillingDocument?

    private var visibleDocuments: [BillingDocument] {
        let calendar = Calendar.current
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let matching = store.documents.filter { document in
            guard document.type == type,
                  (statusFilter == nil || document.status == statusFilter),
                  (clientID.isEmpty || document.clientID == clientID),
                  dateFilter.includes(document.issueDate, calendar: calendar) else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            let client = store.clients.first { $0.id == document.clientID }
            let content = [document.number, document.notes, document.projectTitle ?? "", document.projectReference ?? "", document.purchaseOrderNumber ?? "", client?.displayName ?? "", client?.contactName ?? ""] + document.items.flatMap { [$0.description, $0.note ?? ""] }
            return content.joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalizedQuery)
        }
        return matching.sorted { sort.areInIncreasingOrder($0, $1, clients: store.clients) }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Type", selection: $type) { ForEach(DocumentType.allCases) { Text($0.shortTitle).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
                if clientID.isEmpty == false || dateFilter != .all || statusFilter != nil {
                    Section { HStack { Text("Filtres actifs").foregroundStyle(.secondary); Spacer(); Button("Réinitialiser") { clientID = ""; dateFilter = .all; statusFilter = nil } } }
                }
                ForEach(visibleDocuments) { doc in
                    NavigationLink { DocumentDetailView(document: doc) } label: { DocumentRow(document: doc, client: store.clients.first { $0.id == doc.clientID }) }
                }
                .onDelete { index in documentPendingDeletion = index.first.map { visibleDocuments[$0] } }
            }
            .contentMargins(.bottom, 72, for: .scrollContent)
            .overlay { if visibleDocuments.isEmpty { ContentUnavailableView(query.isEmpty ? "Aucun \(type.title.lowercased())" : "Aucun résultat", systemImage: query.isEmpty ? "doc.badge.plus" : "magnifyingglass") } }
            .searchable(text: $query, prompt: "N°, client, affaire, ligne, note…")
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Section("Client") { Button("Tous les clients") { clientID = "" }; ForEach(store.clients) { client in Button(client.displayName) { clientID = client.id } } }
                        Section("Statut") { Button { statusFilter = nil } label: { Label("Tous les statuts", systemImage: statusFilter == nil ? "checkmark" : "circle") }; ForEach(DocumentStatus.allCases) { status in Button { statusFilter = status } label: { Label(status.title, systemImage: statusFilter == status ? "checkmark" : "circle") } } }
                        Section("Date") { ForEach(DocumentDateFilter.allCases) { filter in Button { dateFilter = filter } label: { Label(filter.title, systemImage: dateFilter == filter ? "checkmark" : "calendar") } } }
                        Section("Trier par") { ForEach(DocumentSort.allCases) { option in Button { sort = option } label: { Label(option.title, systemImage: sort == option ? "checkmark" : option.icon) } } }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button { editor = BillingDocument(type: type, number: store.nextNumber(for: type)) } label: { Image(systemName: "plus") } }
            }
        }
        .sheet(item: $editor) { DocumentEditor(document: $0) }
        .confirmationDialog(
            documentPendingDeletion?.status == .draft ? "Mettre ce brouillon dans la corbeille ?" : "Mettre ce document émis dans la corbeille ?",
            isPresented: Binding(get: { documentPendingDeletion != nil }, set: { if !$0 { documentPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Mettre dans la corbeille", role: .destructive) {
                if let documentPendingDeletion { store.deleteDocument(documentPendingDeletion) }
                documentPendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { documentPendingDeletion = nil }
        } message: {
            if let document = documentPendingDeletion, document.status != .draft {
                Text("Une facture ou note émise ne doit pas être supprimée pour corriger une erreur : privilégiez un avoir. Le document restera récupérable dans la corbeille.")
            } else {
                Text("Le document restera récupérable dans la corbeille.")
            }
        }
    }
}

private enum DocumentDateFilter: String, CaseIterable, Identifiable {
    case all, today, currentMonth, currentYear
    var id: String { rawValue }
    var title: String { switch self { case .all: "Toutes les dates"; case .today: "Aujourd’hui"; case .currentMonth: "Ce mois"; case .currentYear: "Cette année" } }
    func includes(_ date: Date, calendar: Calendar) -> Bool {
        switch self {
        case .all: return true
        case .today: return calendar.isDateInToday(date)
        case .currentMonth: return calendar.isDate(date, equalTo: Date(), toGranularity: .month)
        case .currentYear: return calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        }
    }
}

private enum DocumentSort: String, CaseIterable, Identifiable {
    case dateNewest, dateOldest, client, title, project
    var id: String { rawValue }
    var title: String { switch self { case .dateNewest: "Date : récent d’abord"; case .dateOldest: "Date : ancien d’abord"; case .client: "Client"; case .title: "Titre / numéro"; case .project: "Affaire / contrat" } }
    var icon: String { switch self { case .dateNewest, .dateOldest: "calendar"; case .client: "person"; case .title: "textformat"; case .project: "briefcase" } }
    func areInIncreasingOrder(_ lhs: BillingDocument, _ rhs: BillingDocument, clients: [Client]) -> Bool {
        switch self {
        case .dateNewest: return lhs.issueDate > rhs.issueDate
        case .dateOldest: return lhs.issueDate < rhs.issueDate
        case .client: return (clients.first { $0.id == lhs.clientID }?.displayName ?? "").localizedCaseInsensitiveCompare(clients.first { $0.id == rhs.clientID }?.displayName ?? "") == .orderedAscending
        case .title: return lhs.number.localizedCaseInsensitiveCompare(rhs.number) == .orderedAscending
        case .project: return (lhs.projectTitle ?? lhs.projectReference ?? "").localizedCaseInsensitiveCompare(rhs.projectTitle ?? rhs.projectReference ?? "") == .orderedAscending
        }
    }
}

struct DocumentDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let document: BillingDocument
    @State private var edit = false
    @State private var creditNote: BillingDocument?
    @State private var shareURL: URL?
    @State private var previewURL: URL?
    @State private var payment: DocumentPayment?
    @State private var signature: DocumentSignature?
    @State private var duplicate: BillingDocument?
    @State private var isAttachmentImporter = false
    @State private var showTemplateName = false
    @State private var templateName = ""
    @State private var validationMessages: [String] = []
    @State private var wantsUnlock = false
    @State private var showPaywall = false
    @State private var studioNotice = false
    private var currentDocument: BillingDocument { store.documents.first { $0.id == document.id } ?? document }
    var body: some View {
        List {
            Section("Client") { Text(store.clients.first { $0.id == currentDocument.clientID }?.displayName ?? "Non renseigné") }
            Section("Lignes") {
                ForEach(currentDocument.items) { item in
                    HStack { Text(item.description); Spacer(); Text(Formatters.money(item.totalLineHT)) }
                }
            }
            Section("Total") {
                if currentDocument.globalDiscountValue > 0 { LabeledContent("Sous-total HT", value: Formatters.money(currentDocument.subtotalHT)); LabeledContent("Remise globale", value: "− " + Formatters.money(currentDocument.globalDiscountValue)) }
                LabeledContent("HT", value: Formatters.money(currentDocument.totalHT))
                LabeledContent("TVA", value: Formatters.money(currentDocument.totalVAT))
                LabeledContent(currentDocument.type == .creditNote ? "Avoir TTC" : "TTC") { Text(Formatters.money(currentDocument.totalTTC)).bold() }
                if currentDocument.type == .creditNote { LabeledContent("À déduire") { Text(Formatters.money(currentDocument.creditAmount)).bold() } }
            }
            if currentDocument.type != .quote && currentDocument.type != .creditNote {
                Section("Règlements") {
                    ForEach(currentDocument.payments ?? []) { entry in
                        HStack { VStack(alignment: .leading) { Text(Formatters.date.string(from: entry.date)); Text([entry.method, entry.reference].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(Formatters.money(entry.amount)).bold(); Button(role: .destructive) { store.deletePayment(entry, from: currentDocument) } label: { Image(systemName: "trash") } }
                    }
                    Button { payment = DocumentPayment() } label: { Label("Ajouter un règlement", systemImage: "plus.circle") }
                    if currentDocument.paidAmount > 0 { LabeledContent("Déjà réglé", value: Formatters.money(currentDocument.paidAmount)) }
                    LabeledContent("Reste à payer", value: Formatters.money(currentDocument.netToPay))
                }
            }
            if currentDocument.lockedAt != nil { Section { Label("Document verrouillé depuis son émission. Toute modification doit être justifiée et reste inscrite dans l’historique.", systemImage: "lock.fill").font(.footnote).foregroundStyle(.orange) } }
            if !(currentDocument.events ?? []).isEmpty { Section("Historique") { ForEach((currentDocument.events ?? []).sorted { $0.date > $1.date }) { event in VStack(alignment: .leading, spacing: 3) { Text(event.title).font(.subheadline.weight(.semibold)); Text(event.details).font(.caption).foregroundStyle(.secondary); Text(Formatters.date.string(from: event.date)).font(.caption2).foregroundStyle(.tertiary) } } } }
            Section("Signatures") {
                ForEach(currentDocument.signatures ?? []) { signed in
                    VStack(alignment: .leading, spacing: 3) { Text("\(signed.party.title) — \(signed.signerName)").font(.subheadline.weight(.semibold)); Text([signed.signerRole, Formatters.date.string(from: signed.signedAt)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                }
                if store.hasAdvancedAccess { Button("Signer côté émetteur") { signature = DocumentSignature(party: .issuer) }; Button("Signer côté réceptionnaire") { signature = DocumentSignature(party: .recipient) } }
                else { StudioLockedRow(title: "Signature CashDraft", subtitle: "Disponible avec CashDraft Studio") { showStudioNotice() } }
            }
            Section("Pièces jointes") {
                ForEach(currentDocument.attachments ?? []) { attachment in
                    HStack { Image(systemName: "paperclip"); Text(attachment.filename).lineLimit(1); Spacer(); Button(role: .destructive) { store.deleteAttachment(attachment, from: currentDocument) } label: { Image(systemName: "trash") } }
                }
                Button("Ajouter une pièce jointe") { isAttachmentImporter = true }
                Text("Bon de commande, photo de réception ou justificatif — conservé dans la sauvegarde CashDraft.").font(.caption).foregroundStyle(.secondary)
            }
            if currentDocument.type == .creditNote { Section("Origine de l’avoir") { Text(currentDocument.sourceDocumentNumber ?? "Facture d’origine à préciser"); if let reason = currentDocument.creditReason, !reason.isEmpty { Text(reason).foregroundStyle(.secondary) } } }
            Section {
                Picker("Statut", selection: Binding(get: { currentDocument.status }, set: { status in updateStatus(status) })) {
                    ForEach(DocumentStatus.allCases) { status in Text(status.title).tag(status) }
                }
            }
        }
        .contentMargins(.bottom, 72, for: .scrollContent)
        .navigationTitle(document.number)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if currentDocument.type == .quote {
                    Button("Facturer") {
                        if store.convertQuoteToInvoice(currentDocument) != nil { dismiss() } else { showPaywall = true }
                    }
                }
                if currentDocument.type == .invoice || currentDocument.type == .honorariumNote { Button("Créer un avoir") { creditNote = store.creditNoteDraft(for: currentDocument) } }
                Button { duplicate = store.duplicateDraft(for: currentDocument) } label: { Image(systemName: "plus.square.on.square") }.accessibilityLabel("Dupliquer en brouillon")
                if store.hasAdvancedAccess { Button { templateName = currentDocument.projectTitle ?? currentDocument.number; showTemplateName = true } label: { Image(systemName: "bookmark") }.accessibilityLabel("Enregistrer comme modèle") }
                if currentDocument.lockedAt == nil { Button { edit = true } label: { Image(systemName: "pencil") } } else { Button { wantsUnlock = true } label: { Image(systemName: "lock.fill") } }
                Button { previewURL = store.pdfURL(for: currentDocument, draftWatermark: currentDocument.status == .draft) } label: { Image(systemName: "eye") }
                Button { shareDocument() } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(isPresented: $edit) { DocumentEditor(document: currentDocument) }
        .sheet(item: $payment) { payment in PaymentEditor(payment: payment) { store.addPayment($0, to: currentDocument) } }
        .sheet(item: $signature) { signature in SignatureEditor(signature: signature) { store.addSignature($0, to: currentDocument) } }
        .sheet(item: $duplicate) { DocumentEditor(document: $0) }
        .fileImporter(isPresented: $isAttachmentImporter, allowedContentTypes: [.pdf, .image, .data]) { result in
            guard case .success(let url) = result, url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.preferredMIMEType) ?? "application/octet-stream"
            store.addAttachment(data: data, filename: url.lastPathComponent, mimeType: type, to: currentDocument)
        }
        .sheet(item: $creditNote) { DocumentEditor(document: $0) }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) { if let previewURL { PDFPreviewSheet(url: previewURL) } }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) { if let shareURL { ShareSheet(url: shareURL) } }
        .alert("Document incomplet", isPresented: Binding(get: { !validationMessages.isEmpty }, set: { if !$0 { validationMessages = [] } })) { Button("OK", role: .cancel) {} } message: { Text(validationMessages.joined(separator: "\n• ")) }
        .alert("Enregistrer comme modèle", isPresented: $showTemplateName) { TextField("Nom du modèle", text: $templateName); Button("Enregistrer") { guard !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; store.saveTemplate(store.templateDraft(for: currentDocument, name: templateName)) }; Button("Annuler", role: .cancel) {} } message: { Text("Le modèle crée un nouveau brouillon et ne consomme jamais de crédit à lui seul.") }
        .confirmationDialog("Déverrouiller ce document ?", isPresented: $wantsUnlock, titleVisibility: .visible) { Button("Déverrouiller", role: .destructive) { store.unlockDocument(currentDocument) }; Button("Annuler", role: .cancel) {} } message: { Text("La modification d’un document émis doit être exceptionnelle. En cas d’erreur de facturation, privilégiez un avoir.") }
        .overlay(alignment: .bottom) { if studioNotice { StudioToast() } }
    }

    private func updateStatus(_ status: DocumentStatus) {
        if status == .sent || status == .paid {
            let messages = store.validationMessages(for: currentDocument)
            guard messages.isEmpty else { validationMessages = messages; return }
        }
        var copy = currentDocument
        copy.status = status
        if !store.issueDocument(copy) { showPaywall = true }
    }

    private func shareDocument() {
        var documentToShare = currentDocument
        if documentToShare.status == .draft {
            let messages = store.validationMessages(for: documentToShare)
            guard messages.isEmpty else { validationMessages = messages; return }
            documentToShare.status = .sent
            guard store.issueDocument(documentToShare) else { showPaywall = true; return }
        }
        let preservedDocument = store.documents.first { $0.id == documentToShare.id } ?? documentToShare
        shareURL = store.pdfURL(for: preservedDocument, draftWatermark: preservedDocument.status == .draft)
    }

    private func showStudioNotice() { studioNotice = true; Task { try? await Task.sleep(for: .seconds(2.5)); studioNotice = false } }
}

struct PaymentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DocumentPayment
    let onSave: (DocumentPayment) -> Void

    init(payment: DocumentPayment, onSave: @escaping (DocumentPayment) -> Void) {
        _draft = State(initialValue: payment)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                TextField("Montant", value: $draft.amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                Picker("Mode de règlement", selection: $draft.method) { Text("Virement").tag("Virement"); Text("Carte").tag("Carte"); Text("Chèque").tag("Chèque"); Text("Espèces").tag("Espèces"); Text("Autre").tag("Autre") }
                TextField("Référence (facultatif)", text: $draft.reference)
                TextField("Note (facultatif)", text: $draft.notes, axis: .vertical)
            }
            .navigationTitle("Règlement")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { onSave(draft); dismiss() }.disabled(draft.amount <= 0) } }
        }
    }
}

struct SignatureEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DocumentSignature
    @State private var strokes: [[SignaturePoint]]
    let onSave: (DocumentSignature) -> Void

    init(signature: DocumentSignature, onSave: @escaping (DocumentSignature) -> Void) { _draft = State(initialValue: signature); _strokes = State(initialValue: signature.strokes); self.onSave = onSave }

    var body: some View { NavigationStack { Form {
        Picker("Signataire", selection: $draft.party) { ForEach(SignatureParty.allCases) { Text($0.title).tag($0) } }
        TextField("Nom du signataire", text: $draft.signerName)
        TextField("Fonction (facultatif)", text: $draft.signerRole)
        DatePicker("Date", selection: $draft.signedAt, displayedComponents: [.date, .hourAndMinute])
        Section("Signature") { SignatureCanvas(strokes: $strokes).frame(height: 180); Button("Effacer la signature", role: .destructive) { strokes = [] } }
        Section { Text("Signature CashDraft : trace de réception ou de bon pour accord. Ce n’est pas une signature électronique qualifiée au sens eIDAS/UE.").font(.footnote).foregroundStyle(.secondary) }
    }.navigationTitle("Signature CashDraft").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { draft.strokes = strokes; onSave(draft); dismiss() }.disabled(draft.signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || strokes.flatMap { $0 }.isEmpty) } } } }
}

struct SignatureCanvas: View {
    @Binding var strokes: [[SignaturePoint]]
    @State private var isDrawing = false
    var body: some View { GeometryReader { geometry in
        Canvas { context, size in
            for stroke in strokes where stroke.count > 1 {
                var path = Path(); path.move(to: CGPoint(x: stroke[0].x * size.width, y: stroke[0].y * size.height))
                for point in stroke.dropFirst() { path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height)) }
                context.stroke(path, with: .color(.primary), lineWidth: 2.2)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.35)) }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let point = SignaturePoint(x: min(1, max(0, value.location.x / geometry.size.width)), y: min(1, max(0, value.location.y / geometry.size.height)))
            if !isDrawing { strokes.append([]); isDrawing = true }
            strokes[strokes.count - 1].append(point)
        }.onEnded { _ in isDrawing = false })
    } }
}

struct PDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    var body: some View { NavigationStack { PDFPreview(url: url).navigationTitle("Aperçu du document").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } } } }
}

struct PDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayDirection = .vertical; view.displayMode = .singlePageContinuous; return view }
    func updateUIView(_ view: PDFView, context: Context) { view.document = PDFDocument(url: url) }
}

struct ShareSheet: UIViewControllerRepresentable { let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
