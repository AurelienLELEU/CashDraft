import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var profile = CompanyProfile()
    @Published private(set) var clients: [Client] = []
    @Published private(set) var catalog: [CatalogItem] = []
    @Published private(set) var templates: [DocumentTemplate] = []
    @Published private(set) var documents: [BillingDocument] = []
    @Published private(set) var trashedDocuments: [BillingDocument] = []
    @Published private(set) var license = AppLicense()
    @Published private(set) var iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "cashdraft.iCloudSyncEnabled")
    @Published private(set) var iCloudSyncStatus = "Désactivée"
    @Published var errorMessage: String?
    @Published private(set) var isReady = false
    private var database: Database?
    private let cloudSync = CloudSyncService()
    private var cloudSyncTask: Task<Void, Never>?
    private var lastLocalChange = UserDefaults.standard.object(forKey: "cashdraft.lastLocalChange") as? Date ?? .distantPast

    func bootstrap() async {
        if ProcessInfo.processInfo.environment["CASHDRAFT_SHOWCASE_MODE"] == "1" {
            loadStorefrontShowcase()
            isReady = true
            return
        }
        do {
            let database = try Database(); self.database = database
            profile = try database.fetch(CompanyProfile.self, kind: "profile").first ?? CompanyProfile()
            var migratedProfile = profile
            if migratedProfile.earlyPaymentDiscountText?.isEmpty ?? true { migratedProfile.earlyPaymentDiscountText = "Escompte pour paiement anticipé : néant." }
            if migratedProfile.latePaymentPenaltyText?.isEmpty ?? true { migratedProfile.latePaymentPenaltyText = "Pénalités de retard exigibles dès le jour suivant la date de règlement, au taux de trois fois le taux d’intérêt légal." }
            if migratedProfile.recoveryIndemnityText?.isEmpty ?? true { migratedProfile.recoveryIndemnityText = "Indemnité forfaitaire pour frais de recouvrement : 40 € (articles L441-10 et D441-5 du Code de commerce)." }
            if migratedProfile != profile { profile = migratedProfile; try database.save(profile, kind: "profile", id: "1") }
            clients = try database.fetch(Client.self, kind: "client")
            catalog = try database.fetch(CatalogItem.self, kind: "catalog")
            templates = try database.fetch(DocumentTemplate.self, kind: "template")
            let storedDocuments = try database.fetch(BillingDocument.self, kind: "document")
            documents = storedDocuments.filter { $0.deletedAt == nil }
            trashedDocuments = storedDocuments.filter { $0.deletedAt != nil }
            if let current = try database.fetchLicense() { license = current
            } else if let preserved = DeviceIdentity.loadLicense() {
                license = preserved
                try database.saveLicense(license)
            } else {
                // The secure identity establishes the inaugural 5-document allowance.
                let identity = DeviceIdentity.existingOrCreate()
                license = AppLicense(isProUnlocked: false, remainingCredits: 0, trialDocumentsRemaining: identity.isNew ? 5 : 0)
                try database.saveLicense(license)
                DeviceIdentity.saveLicense(license)
            }
            migrateLicenseIfNeeded()
            try seedDemoDataIfRequested(using: database)
            if ProcessInfo.processInfo.environment["CASHDRAFT_CREATE_B2B_EXAMPLE"] == "1" { createB2BExample() }
            if ProcessInfo.processInfo.environment["CASHDRAFT_CREATE_PERSONNEL_EXAMPLE"] == "1" { createPersonnelInvoiceExample() }
            isReady = true
            if iCloudSyncEnabled { await syncWithICloud() }
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadStorefrontShowcase() {
        let company = CompanyProfile(name: "Entreprise Démo", legalForm: "EI", address: "1 rue Exemple\n00000 Ville Démo\nFrance", siret: "00000000000000", vatNumber: "FR00000000000", vatExemptionNotice: "", email: "bonjour@exemple.test", phone: "00 00 00 00 00", logoPath: "", defaultPaymentTerms: "Paiement à 30 jours", currencyCode: "EUR", addressDetails: PostalAddress(number: "1", street: "rue Exemple", postalCode: "00000", city: "Ville Démo", country: "France"), footerText: "Données fictives de démonstration", earlyPaymentDiscountText: "Escompte pour paiement anticipé : néant.", latePaymentPenaltyText: "Pénalités de retard applicables.", recoveryIndemnityText: "Indemnité forfaitaire de recouvrement : 40 €.", commercialEntities: nil, brandColorHex: "#005EAA", pdfFontName: "HelveticaNeue")
        let clientA = Client(companyName: "Client exemple A", contactName: "Contact principal", address: "2 avenue Exemple\n00000 Ville Démo\nFrance", email: "client-a@exemple.test", phone: "00 00 00 00 01", siret: "00000000000000", contacts: [ClientContact(name: "Contact principal", role: "Contact", email: "client-a@exemple.test", phone: "00 00 00 00 01")], addressDetails: PostalAddress(number: "2", street: "avenue Exemple", postalCode: "00000", city: "Ville Démo", country: "France"))
        let clientB = Client(companyName: "Client exemple B", contactName: "Contact facturation", address: "3 place Exemple\n00000 Ville Démo\nFrance", email: "client-b@exemple.test", phone: "00 00 00 00 02", siret: "00000000000000")
        let date = Date()
        let items = [DocumentItem(description: "Prestation de conseil", quantity: 2, unitPriceHT: 250, vatRate: 20, note: "Deux demi-journées incluses.", unitLabel: "jour"), DocumentItem(description: "Frais de déplacement", quantity: 2, unitPriceHT: 30, vatRate: 20, unitLabel: "forfait")]
        let invoice = BillingDocument(type: .invoice, number: "FAC-2026-014", clientID: clientA.id, status: .sent, issueDate: date, dueDate: Calendar.current.date(byAdding: .day, value: 30, to: date) ?? date, notes: "Données fictives de démonstration.", items: items, projectTitle: "Mission exemple", projectReference: "EX-2026-14", purchaseOrderNumber: "BC-EX-048", serviceDate: date, depositAmount: 120, currencyCode: "EUR")
        let quote = BillingDocument(type: .quote, number: "DEV-2026-008", clientID: clientB.id, status: .sent, issueDate: date, dueDate: Calendar.current.date(byAdding: .day, value: 30, to: date) ?? date, notes: "Données fictives de démonstration.", items: [DocumentItem(description: "Audit de démarrage", quantity: 1, unitPriceHT: 350, vatRate: 20, unitLabel: "forfait")], projectTitle: "Projet exemple", projectReference: "EX-2026-08", currencyCode: "EUR")
        let honorarium = BillingDocument(type: .honorariumNote, number: "HON-2026-003", clientID: clientA.id, status: .paid, issueDate: Calendar.current.date(byAdding: .day, value: -8, to: date) ?? date, dueDate: date, notes: "Données fictives de démonstration.", items: [DocumentItem(description: "Conseil ponctuel", quantity: 3, unitPriceHT: 60, vatRate: 20, unitLabel: "h")], projectTitle: "Accompagnement exemple", currencyCode: "EUR")
        profile = company
        clients = [clientA, clientB]
        catalog = [CatalogItem(description: "Journée de conseil", unitPriceHT: 250, vatRate: 20, unit: "jour"), CatalogItem(description: "Heure de mission", unitPriceHT: 60, vatRate: 20, unit: "h")]
        documents = [invoice, quote, honorarium]
        trashedDocuments = []
        license = AppLicense(isProUnlocked: false, remainingCredits: 0, trialDocumentsRemaining: 5)
    }

    func saveProfile(_ value: CompanyProfile) { profile = value; persist(value, kind: "profile", id: "1"); scheduleCloudUpload() }
    func saveClient(_ value: Client) { upsert(value, in: &clients, kind: "client", id: value.id); scheduleCloudUpload() }
    func deleteClient(_ value: Client) { clients.removeAll { $0.id == value.id }; delete(kind: "client", id: value.id); scheduleCloudUpload() }
    func saveCatalogItem(_ value: CatalogItem) { upsert(value, in: &catalog, kind: "catalog", id: value.id); scheduleCloudUpload() }
    func deleteCatalogItem(_ value: CatalogItem) { catalog.removeAll { $0.id == value.id }; delete(kind: "catalog", id: value.id); scheduleCloudUpload() }
    func saveTemplate(_ value: DocumentTemplate) { upsert(value, in: &templates, kind: "template", id: value.id); scheduleCloudUpload() }
    func deleteTemplate(_ value: DocumentTemplate) { templates.removeAll { $0.id == value.id }; delete(kind: "template", id: value.id); scheduleCloudUpload() }
    func saveDocument(_ value: BillingDocument, allowUnlocked: Bool = false) {
        var activeDocument = value
        let previous = documents.first { $0.id == activeDocument.id }
        activeDocument.deletedAt = nil
        if previous == nil {
            activeDocument.events = (activeDocument.events ?? []) + [DocumentEvent(title: "Document créé", details: "Brouillon créé dans CashDraft.")]
        } else if previous?.status != activeDocument.status {
            activeDocument.events = (activeDocument.events ?? []) + [DocumentEvent(title: "Statut modifié", details: "Statut : \(activeDocument.status.title).")]
        }
        if !allowUnlocked && activeDocument.type != .quote && activeDocument.status != .draft && activeDocument.lockedAt == nil {
            activeDocument.lockedAt = Date()
            activeDocument.events = (activeDocument.events ?? []) + [DocumentEvent(title: "Document verrouillé", details: "Document émis : modifications consignées dans l’historique.")]
        }
        trashedDocuments.removeAll { $0.id == activeDocument.id }
        upsert(activeDocument, in: &documents, kind: "document", id: activeDocument.id)
        documents.sort { $0.issueDate > $1.issueDate }
        if activeDocument.status == .paid || activeDocument.status == .cancelled {
            ReminderManager.remove(for: activeDocument)
        } else if activeDocument.status == .sent {
            ReminderManager.schedule(for: activeDocument)
        }
        scheduleCloudUpload()
    }

    func deleteDocument(_ value: BillingDocument) {
        guard var document = documents.first(where: { $0.id == value.id }) else { return }
        document.deletedAt = Date()
        document.events = (document.events ?? []) + [DocumentEvent(title: "Placée dans la corbeille", details: "Document retiré de la liste active.")]
        documents.removeAll { $0.id == document.id }
        trashedDocuments.append(document)
        trashedDocuments.sort { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        persist(document, kind: "document", id: document.id)
        scheduleCloudUpload()
    }

    func restoreDocument(_ value: BillingDocument) {
        guard var document = trashedDocuments.first(where: { $0.id == value.id }) else { return }
        document.deletedAt = nil
        document.events = (document.events ?? []) + [DocumentEvent(title: "Document restauré", details: "Document rétabli depuis la corbeille.")]
        trashedDocuments.removeAll { $0.id == document.id }
        documents.append(document)
        documents.sort { $0.issueDate > $1.issueDate }
        persist(document, kind: "document", id: document.id)
        scheduleCloudUpload()
    }

    func permanentlyDeleteDocument(_ value: BillingDocument) {
        trashedDocuments.removeAll { $0.id == value.id }
        delete(kind: "document", id: value.id)
        scheduleCloudUpload()
    }

    func unlockDocument(_ value: BillingDocument) {
        guard var document = documents.first(where: { $0.id == value.id }) else { return }
        document.lockedAt = nil
        document.events = (document.events ?? []) + [DocumentEvent(title: "Document déverrouillé", details: "Modification manuelle autorisée ; vérifiez la conformité avant un nouvel envoi.")]
        saveDocument(document, allowUnlocked: true)
    }

    func addPayment(_ payment: DocumentPayment, to value: BillingDocument) {
        guard var document = documents.first(where: { $0.id == value.id }) else { return }
        document.payments = (document.payments ?? []) + [payment]
        document.events = (document.events ?? []) + [DocumentEvent(title: "Paiement enregistré", details: "\(Formatters.money(payment.amount, currencyCode: document.currencyCode ?? profile.currencyCode)) — \(payment.method).")]
        saveDocument(document)
    }

    func deletePayment(_ payment: DocumentPayment, from value: BillingDocument) {
        guard var document = documents.first(where: { $0.id == value.id }) else { return }
        document.payments?.removeAll { $0.id == payment.id }
        document.events = (document.events ?? []) + [DocumentEvent(title: "Paiement supprimé", details: "Historique de règlement modifié.")]
        saveDocument(document)
    }

    func addSignature(_ signature: DocumentSignature, to value: BillingDocument) {
        guard hasAdvancedAccess, var document = documents.first(where: { $0.id == value.id }) else { return }
        var signatures = document.signatures ?? []
        signatures.removeAll { $0.party == signature.party }
        signatures.append(signature)
        document.signatures = signatures
        document.events = (document.events ?? []) + [DocumentEvent(title: "Signature CashDraft ajoutée", details: "\(signature.party.title) : \(signature.signerName) — \(Formatters.date.string(from: signature.signedAt)).")]
        // Signing is an auditable operation, not a content edit; an issued document remains locked.
        saveDocument(document, allowUnlocked: true)
    }

    func addAttachment(data: Data, filename: String, mimeType: String, to value: BillingDocument) {
        guard data.count <= 12_000_000, var document = documents.first(where: { $0.id == value.id }) else { errorMessage = "La pièce jointe dépasse 12 Mo."; return }
        document.attachments = (document.attachments ?? []) + [DocumentAttachment(filename: filename, mimeType: mimeType, data: data)]
        document.events = (document.events ?? []) + [DocumentEvent(title: "Pièce jointe ajoutée", details: filename)]
        saveDocument(document, allowUnlocked: true)
    }

    func deleteAttachment(_ attachment: DocumentAttachment, from value: BillingDocument) {
        guard var document = documents.first(where: { $0.id == value.id }) else { return }
        document.attachments?.removeAll { $0.id == attachment.id }
        document.events = (document.events ?? []) + [DocumentEvent(title: "Pièce jointe retirée", details: attachment.filename)]
        saveDocument(document, allowUnlocked: true)
    }

    func validationMessages(for document: BillingDocument) -> [String] {
        var messages: [String] = []
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append("Renseignez la raison sociale de l’émetteur.") }
        if profile.legalForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append("Renseignez la forme juridique de l’émetteur.") }
        if (profile.addressDetails?.formatted ?? profile.address).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append("Renseignez l’adresse de l’émetteur.") }
        if profile.siret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append("Renseignez le SIRET de l’émetteur.") }
        if document.clientID.isEmpty { messages.append("Sélectionnez un client.") }
        if let client = clients.first(where: { $0.id == document.clientID }), client.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append("Renseignez le nom ou la raison sociale du client.") }
        if document.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append("Renseignez le numéro du document.") }
        if document.items.isEmpty || document.items.contains(where: { $0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.quantity <= 0 }) { messages.append("Chaque ligne doit avoir une description et une quantité positive.") }
        if document.dueDate < document.issueDate { messages.append("L’échéance ne peut pas précéder la date d’émission.") }
        if profile.defaultPaymentTerms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append("Renseignez les conditions de règlement par défaut.") }
        return messages
    }

    func emptyTrash() {
        let identifiers = trashedDocuments.map(\.id)
        trashedDocuments.removeAll()
        identifiers.forEach { delete(kind: "document", id: $0) }
        scheduleCloudUpload()
    }

    @discardableResult
    func convertQuoteToInvoice(_ quote: BillingDocument) -> BillingDocument? {
        var invoice = quote
        invoice.id = UUID().uuidString
        invoice.type = .invoice
        invoice.number = nextNumber(for: .invoice)
        invoice.status = .draft
        invoice.issueDate = Date()
        invoice.dueDate = Calendar.current.date(byAdding: .day, value: 30, to: invoice.issueDate) ?? invoice.issueDate
        invoice.notes = ["Facture issue du devis \(quote.number).", quote.notes]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        saveDocument(invoice)
        return invoice
    }

    func creditNoteDraft(for invoice: BillingDocument) -> BillingDocument {
        BillingDocument(
            type: .creditNote,
            number: nextNumber(for: .creditNote),
            clientID: invoice.clientID,
            status: .draft,
            issueDate: Date(),
            dueDate: Date(),
            notes: "Avoir établi suite à la facture \(invoice.number).",
            items: invoice.items.map { item in
                var credit = item
                credit.id = UUID().uuidString
                credit.unitPriceHT = -abs(item.unitPriceHT)
                return credit
            },
            issuerEntityID: invoice.issuerEntityID,
            clientEntityID: invoice.clientEntityID,
            projectTitle: invoice.projectTitle,
            projectReference: invoice.projectReference,
            purchaseOrderNumber: invoice.purchaseOrderNumber,
            sourceDocumentID: invoice.id,
            sourceDocumentNumber: invoice.number,
            creditReason: "Motif à préciser (litige, erreur de facturation, annulation…)",
            serviceDate: invoice.serviceDate,
            currencyCode: invoice.currencyCode
        )
    }

    func duplicateDraft(for source: BillingDocument) -> BillingDocument {
        var duplicate = source
        duplicate.id = UUID().uuidString
        duplicate.number = nextNumber(for: source.type)
        duplicate.status = .draft
        duplicate.issueDate = Date()
        duplicate.dueDate = Calendar.current.date(byAdding: .day, value: 30, to: duplicate.issueDate) ?? duplicate.issueDate
        duplicate.lockedAt = nil
        duplicate.archivedPDFData = nil
        duplicate.archivedAt = nil
        duplicate.signatures = nil
        duplicate.events = [DocumentEvent(title: "Document dupliqué", details: "Copie de \(source.number). Aucun crédit n’est utilisé tant que la copie reste un brouillon.")]
        duplicate.items = source.items.map { var item = $0; item.id = UUID().uuidString; return item }
        saveDocument(duplicate)
        return duplicate
    }

    func templateDraft(for source: BillingDocument, name: String) -> DocumentTemplate {
        var document = source; document.id = UUID().uuidString; document.status = .draft; document.number = ""; document.lockedAt = nil; document.archivedPDFData = nil; document.archivedAt = nil; document.signatures = nil; document.events = nil
        document.items = source.items.map { var item = $0; item.id = UUID().uuidString; return item }
        return DocumentTemplate(name: name, document: document)
    }

    func draft(from template: DocumentTemplate) -> BillingDocument {
        var document = template.document; document.id = UUID().uuidString; document.number = nextNumber(for: document.type); document.issueDate = Date(); document.dueDate = Calendar.current.date(byAdding: .day, value: 30, to: document.issueDate) ?? document.issueDate
        document.items = document.items.map { var item = $0; item.id = UUID().uuidString; return item }
        saveDocument(document); return document
    }

    func exportAccountingCSV() throws -> URL {
        let header = ["Type", "Numéro", "Date", "Échéance", "Client", "Statut", "HT", "TVA", "TTC", "Encaissé", "Reste", "Devise"].joined(separator: ";")
        let rows = documents.filter { $0.status != .draft }.sorted { $0.issueDate < $1.issueDate }.map { document in
            let client = clients.first { $0.id == document.clientID }?.displayName ?? ""
            return [document.type.title, document.number, ISO8601DateFormatter().string(from: document.issueDate), ISO8601DateFormatter().string(from: document.dueDate), client, document.status.title, csv(document.totalHT), csv(document.totalVAT), csv(document.totalTTC), csv(document.paidAmount), csv(document.netToPay), document.currencyCode ?? profile.currencyCode].map(csv).joined(separator: ";")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CashDraft-export-comptable-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).csv")
        guard let data = ([header] + rows).joined(separator: "\n").data(using: .utf8) else { throw DatabaseError.decode }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func csv(_ value: Double) -> String { String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",") }
    private func csv(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }

    var trialDocumentsRemaining: Int { license.trialDocumentsRemaining ?? 0 }
    var isStudioActive: Bool { (license.studioExpirationDate ?? .distantPast) > Date() }
    var hasAdvancedAccess: Bool { isStudioActive || trialDocumentsRemaining > 0 }
    var canIssueDocument: Bool { isStudioActive || license.isProUnlocked || license.remainingCredits > 0 || trialDocumentsRemaining > 0 }

    /// Drafts are always available. A credit is used only on the first issue of a document.
    @discardableResult
    func consumeIssuanceIfNeeded() -> Bool {
        guard canIssueDocument else { return false }
        if isStudioActive || license.isProUnlocked { return true }
        if trialDocumentsRemaining > 0 { license.trialDocumentsRemaining = trialDocumentsRemaining - 1 }
        else { license.remainingCredits -= 1 }
        persistLicense()
        return true
    }

    @discardableResult
    func issueDocument(_ value: BillingDocument) -> Bool {
        let wasIssued = documents.first(where: { $0.id == value.id })?.status != .draft
        guard wasIssued || consumeIssuanceIfNeeded() else { return false }
        var issued = value
        if !wasIssued {
            issued.archivedAt = Date()
            if let url = try? PDFRenderer.render(document: issued, client: clients.first { $0.id == issued.clientID }, company: profile), let data = try? Data(contentsOf: url) { issued.archivedPDFData = data }
            issued.events = (issued.events ?? []) + [DocumentEvent(title: "PDF archivé", details: "Le rendu émis est conservé avec ce document.")]
        }
        saveDocument(issued)
        if !wasIssued { ReminderManager.schedule(for: issued) }
        return true
    }

    func pdfURL(for document: BillingDocument, draftWatermark: Bool = false) -> URL? {
        if document.status != .draft, let data = document.archivedPDFData {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(document.id).pdf")
            try? data.write(to: url, options: .atomic)
            return url
        }
        return try? PDFRenderer.render(document: document, client: clients.first { $0.id == document.clientID }, company: profile, draftWatermark: draftWatermark)
    }

    func enableDueDateReminders() async -> Bool {
        let granted = await ReminderManager.requestAuthorization()
        guard granted else { return false }
        documents.forEach(ReminderManager.schedule)
        return true
    }
    func addCredits(_ amount: Int) { license.remainingCredits += amount; persistLicense() }
    func unlockPro(transactionID: String = "") { license.isProUnlocked = true; license.purchaseDate = Date(); license.transactionID = transactionID; persistLicense() }
    func applyPurchase(productID: String, transactionID: String, expirationDate: Date? = nil) {
        var processed = Set(license.processedTransactionIDs ?? [])
        guard !processed.contains(transactionID) else { return }
        switch productID {
        case LicenseManager.lifetimeID:
            license.isProUnlocked = true
            license.purchaseDate = Date()
            license.transactionID = transactionID
        case LicenseManager.creditsID:
            license.remainingCredits += 20
        case LicenseManager.studioMonthlyID, LicenseManager.studioYearlyID:
            license.studioExpirationDate = expirationDate
        default:
            return
        }
        processed.insert(transactionID)
        license.processedTransactionIDs = Array(processed.suffix(200))
        persistLicense()
    }

    private func migrateLicenseIfNeeded() {
        guard license.trialDocumentsRemaining == nil else { return }
        // Previous versions used remainingCredits for the five-document trial.
        if !license.isProUnlocked, license.remainingCredits <= 5, license.purchaseDate == nil {
            license.trialDocumentsRemaining = license.remainingCredits
            license.remainingCredits = 0
        } else {
            license.trialDocumentsRemaining = 0
        }
        persistLicense()
    }

    func createB2BExample() {
        var issuer = profile
        issuer.name = "SOLETANCHE BACHY FRANCE"
        issuer.legalForm = "SAS"
        issuer.siret = "71203015400611"
        issuer.vatNumber = "FR27712030154"
        issuer.vatExemptionNotice = ""
        issuer.addressDetails = PostalAddress(number: "280", street: "avenue Napoléon Bonaparte", postalCode: "92500", city: "Rueil-Malmaison", country: "France")
        issuer.address = issuer.addressDetails?.formatted ?? issuer.address
        issuer.phone = "+33 1 47 76 42 62"
        issuer.email = ""
        issuer.defaultPaymentTerms = "Paiement à 30 jours date de facture"
        issuer.earlyPaymentDiscountText = "Escompte pour paiement anticipé : néant."
        issuer.latePaymentPenaltyText = "Pénalités de retard exigibles dès le jour suivant la date de règlement, au taux de trois fois le taux d’intérêt légal."
        issuer.recoveryIndemnityText = "Indemnité forfaitaire pour frais de recouvrement : 40 € (articles L441-10 et D441-5 du Code de commerce)."
        issuer.footerText = "SOLETANCHE BACHY FRANCE — SAS — RCS Nanterre 712 030 154"
        issuer.brandColorHex = "#005EAA"
        let issuerEntity = CommercialEntity(name: "Direction Grands Projets", legalForm: "", registrationNumber: "", vatNumber: "", address: PostalAddress(), usesParentAddress: true, email: "", phone: "", logoPath: "")
        issuer.commercialEntities = [issuerEntity]
        saveProfile(issuer)

        var paris = clients.first { $0.siret == "21750001600019" || $0.companyName.caseInsensitiveCompare("Ville de Paris") == .orderedSame } ?? Client(companyName: "Ville de Paris")
        paris.companyName = "Ville de Paris"
        paris.contactName = "Direction des Finances et des Achats"
        paris.siret = "21750001600019"
        paris.addressDetails = PostalAddress(number: "7", street: "avenue de la Porte d'Ivry", postalCode: "75013", city: "Paris", country: "France")
        paris.address = paris.addressDetails?.formatted ?? paris.address
        paris.email = ""
        paris.phone = ""
        let parisEntity = CommercialEntity(name: "Direction des Finances et des Achats", legalForm: "Collectivité territoriale", registrationNumber: "21750001600019", vatNumber: "", address: PostalAddress(), usesParentAddress: true, email: "", phone: "", logoPath: "")
        paris.commercialEntities = [parisEntity]
        if paris.contacts.isEmpty { paris.contacts = [ClientContact(name: "Service facturier", role: "Direction des Finances et des Achats", email: "", phone: "")] }
        saveClient(paris)

        guard !documents.contains(where: { $0.notes.contains("EXEMPLE CASHDRAFT — B2B") }) else { return }
        let calendar = Calendar.current
        let issueDate = Date()
        let serviceDate = calendar.date(byAdding: .day, value: -7, to: issueDate) ?? issueDate
        let dueDate = calendar.date(byAdding: .day, value: 30, to: issueDate) ?? issueDate
        let items = [
            DocumentItem(description: "Études géotechniques et note de calcul", quantity: 1, unitPriceHT: 42500, vatRate: 20, note: "Mission d’exécution — hypothèses, dimensionnement et visa interne."),
            DocumentItem(description: "Paroi moulée — phase 1", quantity: 1, unitPriceHT: 118000, vatRate: 20, note: "Installation, excavation, bétonnage et contrôles qualité."),
            DocumentItem(description: "Contrôles et dossier de récolement", quantity: 1, unitPriceHT: 12500, vatRate: 20, note: "PV de contrôle, DOE et transmission au maître d’ouvrage.")
        ]
        let document = BillingDocument(type: .invoice, number: nextNumber(for: .invoice, date: issueDate), clientID: paris.id, status: .sent, issueDate: issueDate, dueDate: dueDate, notes: "EXEMPLE CASHDRAFT — B2B. Données, références et montants de démonstration uniquement.", items: items, issuerEntityID: issuerEntity.id, clientEntityID: parisEntity.id, projectTitle: "Ouvrage de soutènement — Paris 13 (exemple)", projectReference: "MARCHÉ-EX-2026-042", purchaseOrderNumber: "BC-PARIS-EX-2026-017", serviceDate: serviceDate, retentionAmount: 8650, depositAmount: 27000, currencyCode: "EUR")
        saveDocument(document)
    }

    func createPersonnelInvoiceExample() {
        guard !documents.contains(where: { $0.notes.contains("EXEMPLE CASHDRAFT — FACTURATION PERSONNEL") }) else { return }
        var client = clients.first { $0.companyName == "Bâtir & Co — Exemple" } ?? Client(companyName: "Bâtir & Co — Exemple")
        client.companyName = "Bâtir & Co — Exemple"
        client.contactName = "Service achats — démonstration"
        client.siret = "00000000000000"
        client.addressDetails = PostalAddress(number: "18", street: "rue des Ateliers", postalCode: "92100", city: "Boulogne-Billancourt", country: "France")
        client.address = client.addressDetails?.formatted ?? client.address
        client.contacts = [ClientContact(name: "Service achats", role: "Contact de démonstration", email: "", phone: "")]
        saveClient(client)

        let calendar = Calendar.current
        let issueDate = Date()
        let serviceDate = calendar.date(byAdding: .day, value: -30, to: issueDate) ?? issueDate
        let dueDate = calendar.date(byAdding: .day, value: 30, to: issueDate) ?? issueDate
        let items = [
            DocumentItem(description: "Heures de mission — opérateur chantier", quantity: 151.67, unitPriceHT: 46, vatRate: 20, note: "Mission d’intérim / mise à disposition — période de démonstration.", unitLabel: "h"),
            DocumentItem(description: "Heures majorées de mission", quantity: 12, unitPriceHT: 58, vatRate: 20, note: "Majoration fictive pour intervention hors horaires usuels.", unitLabel: "h"),
            DocumentItem(description: "Tickets restaurant", quantity: 18, unitPriceHT: 12.5, vatRate: 20, note: "Exemple : taux de TVA à adapter selon le régime applicable.", unitLabel: "ticket"),
            DocumentItem(description: "Indemnités de déplacement", quantity: 18, unitPriceHT: 18.2, vatRate: 20, note: "Forfait journalier fictif.", unitLabel: "jour"),
            DocumentItem(description: "Indemnités kilométriques", quantity: 260, unitPriceHT: 0.72, vatRate: 20, note: "Barème de démonstration — à paramétrer selon votre politique.", unitLabel: "km")
        ]
        let document = BillingDocument(type: .invoice, number: nextNumber(for: .invoice, date: issueDate), clientID: client.id, status: .sent, issueDate: issueDate, dueDate: dueDate, notes: "EXEMPLE CASHDRAFT — FACTURATION PERSONNEL. Données, client et montants fictifs ; ne pas transmettre comme pièce comptable.", items: items, projectTitle: "Mission renfort chantier — exemple", projectReference: "MIS-EX-2026-091", purchaseOrderNumber: "BC-EX-PERS-2026-018", serviceDate: serviceDate, depositAmount: 2500, currencyCode: profile.currencyCode)
        saveDocument(document)
    }

    func nextNumber(for type: DocumentType, date: Date = Date()) -> String {
        let year = Calendar.current.component(.year, from: date)
        let prefix = "\(profile.prefix(for: type))-\(year)-"
        let highest = (documents + trashedDocuments).filter { $0.type == type && $0.number.hasPrefix(prefix) }.compactMap { Int($0.number.replacingOccurrences(of: prefix, with: "")) }.max() ?? 0
        return prefix + String(format: "%03d", highest + 1)
    }

    func exportBackup() throws -> URL {
        let payload = BackupPayload(profile: profile, clients: clients, catalog: catalog, documents: documents + trashedDocuments, templates: templates)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CashDraft-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).json")
        try encoder.encode(payload).write(to: url, options: .atomic); return url
    }
    func importBackup(from url: URL) throws {
        let imported = try decodeBackup(from: url)
        try database?.replaceAll(profile: imported.profile, clients: imported.clients, catalog: imported.catalog, documents: imported.documents, templates: imported.templates ?? [])
        profile = imported.profile; clients = imported.clients; catalog = imported.catalog
        documents = imported.documents.filter { $0.deletedAt == nil }
        trashedDocuments = imported.documents.filter { $0.deletedAt != nil }
        templates = imported.templates ?? []
        scheduleCloudUpload()
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        iCloudSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "cashdraft.iCloudSyncEnabled")
        iCloudSyncStatus = enabled ? "Connexion à iCloud…" : "Désactivée"
        cloudSyncTask?.cancel()
        if enabled { cloudSyncTask = Task { await syncWithICloud() } }
    }

    func syncWithICloud() async {
        guard iCloudSyncEnabled else { return }
        do {
            let remote = try await cloudSync.fetch()
            if let remote, remote.modifiedAt > lastLocalChange {
                try database?.replaceAll(profile: remote.profile, clients: remote.clients, catalog: remote.catalog, documents: remote.documents, templates: remote.templates ?? [])
                profile = remote.profile; clients = remote.clients; catalog = remote.catalog; license = remote.license
                documents = remote.documents.filter { $0.deletedAt == nil }
                trashedDocuments = remote.documents.filter { $0.deletedAt != nil }
                templates = remote.templates ?? []
                persistLicense()
                lastLocalChange = remote.modifiedAt
                UserDefaults.standard.set(lastLocalChange, forKey: "cashdraft.lastLocalChange")
                iCloudSyncStatus = "Synchronisée"
            } else {
                try await cloudSync.upload(currentCloudSnapshot())
                iCloudSyncStatus = "Synchronisée"
            }
        } catch {
            iCloudSyncStatus = "Indisponible"
        }
    }

    private func currentCloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(modifiedAt: lastLocalChange, profile: profile, clients: clients, catalog: catalog, documents: documents + trashedDocuments, templates: templates, license: license)
    }

    private func scheduleCloudUpload() {
        lastLocalChange = Date()
        UserDefaults.standard.set(lastLocalChange, forKey: "cashdraft.lastLocalChange")
        guard iCloudSyncEnabled else { return }
        cloudSyncTask?.cancel()
        cloudSyncTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            do { try await cloudSync.upload(currentCloudSnapshot()); iCloudSyncStatus = "Synchronisée" }
            catch { iCloudSyncStatus = "En attente de connexion" }
        }
    }

    func previewBackup(from url: URL) throws -> BackupImportPreview {
        let imported = try decodeBackup(from: url)
        return BackupImportPreview(
            url: url,
            exportDate: imported.exportDate,
            profileName: imported.profile.name.isEmpty ? "Profil sans nom" : imported.profile.name,
            clientCount: imported.clients.count,
            documentCount: imported.documents.filter { $0.deletedAt == nil }.count,
            trashedDocumentCount: imported.documents.filter { $0.deletedAt != nil }.count
        )
    }

    private func decodeBackup(from url: URL) throws -> BackupPayload {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode(BackupPayload.self, from: Data(contentsOf: url))
        guard imported.appName == "CashDraft", imported.version == "1.0" else { throw DatabaseError.decode }
        return imported
    }

    private func upsert<T: Identifiable & Codable>(_ value: T, in array: inout [T], kind: String, id: String) where T.ID == String {
        if let index = array.firstIndex(where: { $0.id == value.id }) { array[index] = value } else { array.append(value) }; persist(value, kind: kind, id: id)
    }
    private func persist<T: Codable>(_ value: T, kind: String, id: String) { do { try database?.save(value, kind: kind, id: id) } catch { errorMessage = error.localizedDescription } }
    private func delete(kind: String, id: String) { do { try database?.delete(kind: kind, id: id) } catch { errorMessage = error.localizedDescription } }
    private func persistLicense() { do { try database?.saveLicense(license); DeviceIdentity.saveLicense(license); scheduleCloudUpload() } catch { errorMessage = error.localizedDescription } }

    private func seedDemoDataIfRequested(using database: Database) throws {
        let hasOnlyDemoData = profile.name == "Studio Atlas — Démonstration"
        guard ProcessInfo.processInfo.environment["CASHDRAFT_SEED_DEMO"] == "1",
              (profile.name.isEmpty && clients.isEmpty && catalog.isEmpty && documents.isEmpty) || hasOnlyDemoData else { return }

        let calendar = Calendar.current
        let issueDate = calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let dueDate = calendar.date(byAdding: .day, value: 30, to: issueDate) ?? issueDate
        let year = calendar.component(.year, from: issueDate)
        var company = CompanyProfile(
            name: "Studio Atlas — Démonstration",
            legalForm: "SASU",
            address: "42 rue de l'Exemple, 69002 Lyon",
            siret: "00000000000000",
            vatNumber: "FR00000000000",
            vatExemptionNotice: "",
            email: "bonjour@studio-atlas.demo",
            phone: "06 00 00 00 00",
            logoPath: "",
            defaultPaymentTerms: "Paiement à 30 jours",
            currencyCode: "EUR"
        )
        company.brandColorHex = "#5B2C6F"
        company.footerText = "Studio Atlas — facturation de démonstration"
        company.earlyPaymentDiscountText = "Escompte pour paiement anticipé : néant."
        company.latePaymentPenaltyText = "Pénalités de retard exigibles sans rappel."
        company.recoveryIndemnityText = "Indemnité forfaitaire pour frais de recouvrement : 40 €"
        let client = Client(companyName: "Maison Luma — Démonstration", contactName: "Camille Martin", address: "15 quai de la Démo, 69002 Lyon", email: "camille@maison-luma.demo", phone: "04 00 00 00 00", siret: "00000000000000", contacts: [ClientContact(name: "Adrien Robert", role: "Direction artistique", email: "adrien@maison-luma.demo", phone: "06 00 00 00 01")])
        let catalog = [
            CatalogItem(description: "Audit et cadrage", unitPriceHT: 450, vatRate: 0),
            CatalogItem(description: "Conception d'interface", unitPriceHT: 750, vatRate: 20)
        ]
        let items = [
            DocumentItem(description: "Audit et cadrage", quantity: 1, unitPriceHT: 450, vatRate: 0),
            DocumentItem(description: "Conception d'interface", quantity: 1, unitPriceHT: 750, vatRate: 20, note: "Maquettes desktop et mobile, deux cycles de retours inclus.")
        ]
        let quote = BillingDocument(type: .quote, number: "DEV-\(year)-001", clientID: client.id, status: .sent, issueDate: issueDate, dueDate: dueDate, notes: "Démo : devis accepté.", items: items, projectTitle: "Refonte du portail Maison Luma", projectReference: "ENG-2026-047", purchaseOrderNumber: "BC-ML-428", serviceDate: issueDate, currencyCode: "EUR")
        let invoice = BillingDocument(type: .invoice, number: "FAC-\(year)-001", clientID: client.id, status: .sent, issueDate: issueDate, dueDate: dueDate, notes: "Démo : facture créée à partir du devis DEV-\(year)-001.", items: items, projectTitle: "Refonte du portail Maison Luma", projectReference: "ENG-2026-047", purchaseOrderNumber: "BC-ML-428", serviceDate: issueDate, retentionAmount: 50, alreadyPaidAmount: 100, currencyCode: "EUR")

        try database.replaceAll(profile: company, clients: [client], catalog: catalog, documents: [quote, invoice])
        profile = company
        clients = [client]
        self.catalog = catalog
        documents = [invoice, quote]

        let documentsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let exportedPDF = try PDFRenderer.render(document: invoice, client: client, company: company)
        let destination = documentsDirectory.appendingPathComponent("CashDraft-demo-FAC-\(year)-001.pdf")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: exportedPDF, to: destination)
    }
}

enum ReminderManager {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(for document: BillingDocument) {
        guard (document.type == .invoice || document.type == .honorariumNote), document.status == .sent else { return }
        let center = UNUserNotificationCenter.current()
        let base = "cashdraft.due.\(document.id)"
        center.removePendingNotificationRequests(withIdentifiers: ["\(base).7", "\(base).0", "\(base).late"])
        let entries: [(String, Int, String, String)] = [
            ("7", -7, "Échéance dans 7 jours", "\(document.number) arrive bientôt à échéance."),
            ("0", 0, "Échéance aujourd’hui", "\(document.number) est due aujourd’hui."),
            ("late", 1, "Facture en retard", "\(document.number) est en retard de règlement.")
        ]
        for (suffix, offset, title, body) in entries {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: document.dueDate), date > Date() else { continue }
            var components = Calendar.current.dateComponents([.year, .month, .day], from: date); components.hour = 9
            let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
            center.add(UNNotificationRequest(identifier: "\(base).\(suffix)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))) { _ in }
        }
    }

    static func remove(for document: BillingDocument) {
        let base = "cashdraft.due.\(document.id)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(base).7", "\(base).0", "\(base).late"])
    }
}
