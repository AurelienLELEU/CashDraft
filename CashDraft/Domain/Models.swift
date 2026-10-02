import Foundation

enum DocumentType: String, Codable, CaseIterable, Identifiable {
    case invoice = "INVOICE"
    case quote = "QUOTE"
    case creditNote = "CREDIT_NOTE"
    case honorariumNote = "HONORARIUM_NOTE"
    var id: String { rawValue }
    var title: String { switch self { case .invoice: "Facture"; case .quote: "Devis"; case .creditNote: "Avoir"; case .honorariumNote: "Note d’honoraires" } }
    var shortTitle: String { self == .honorariumNote ? "Honoraires" : title }
    var prefix: String { switch self { case .invoice: "FAC"; case .quote: "DEV"; case .creditNote: "AVO"; case .honorariumNote: "HON" } }
}

enum DocumentStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "DRAFT", sent = "SENT", paid = "PAID", cancelled = "CANCELLED"
    var id: String { rawValue }
    var title: String { switch self { case .draft: "Brouillon"; case .sent: "Envoyée"; case .paid: "Payée"; case .cancelled: "Annulée" } }
}

struct PostalAddress: Codable, Hashable {
    var number = ""
    var street = ""
    var postalCode = ""
    var city = ""
    var country = "France"

    var formatted: String {
        let firstLine = [number, street].filter { !$0.isEmpty }.joined(separator: " ")
        let secondLine = [postalCode, city].filter { !$0.isEmpty }.joined(separator: " ")
        return [firstLine, secondLine, country].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct CommercialEntity: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name = ""
    var legalForm = ""
    var registrationNumber = ""
    var vatNumber = ""
    var address = PostalAddress()
    var usesParentAddress = false
    var email = ""
    var phone = ""
    var logoPath = ""

    var displayName: String { name.isEmpty ? "Entité sans nom" : name }
}

struct CompanyProfile: Codable, Equatable {
    var id: Int = 1
    var name = ""
    var legalForm = "Auto-entrepreneur"
    var address = ""
    var siret = ""
    var vatNumber = ""
    var vatExemptionNotice = "TVA non applicable, art. 293 B du CGI"
    var email = ""
    var phone = ""
    var logoPath = ""
    var defaultPaymentTerms = "Paiement à réception"
    var currencyCode = "EUR"
    var addressDetails: PostalAddress?
    var footerText: String?
    var earlyPaymentDiscountText: String? = "Escompte pour paiement anticipé : néant."
    var latePaymentPenaltyText: String? = "Pénalités de retard exigibles dès le jour suivant la date de règlement, au taux de trois fois le taux d’intérêt légal."
    var recoveryIndemnityText: String? = "Indemnité forfaitaire pour frais de recouvrement : 40 € (articles L441-10 et D441-5 du Code de commerce)."
    var commercialEntities: [CommercialEntity]?
    var brandColorHex: String?
    var pdfFontName: String? = "HelveticaNeue"
    var shareCapital: String?
    var rcsCity: String?
    var rcsNumber: String?
    var iban: String?
    var bic: String?
    var invoicePrefix: String? = nil
    var quotePrefix: String? = nil
    var creditNotePrefix: String? = nil
    var honorariumPrefix: String? = nil

    func prefix(for type: DocumentType) -> String {
        switch type {
        case .invoice: return invoicePrefix?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? invoicePrefix! : "FAC"
        case .quote: return quotePrefix?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? quotePrefix! : "DEV"
        case .creditNote: return creditNotePrefix?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? creditNotePrefix! : "AVO"
        case .honorariumNote: return honorariumPrefix?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? honorariumPrefix! : "HON"
        }
    }
}

struct ClientContact: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name = ""
    var role = ""
    var email = ""
    var phone = ""
}

struct Client: Identifiable, Codable, Hashable {
    var id: String
    var companyName: String
    var contactName: String
    var address: String
    var email: String
    var phone: String
    var siret: String
    var contacts: [ClientContact]
    var createdAt: Date
    var addressDetails: PostalAddress?
    var vatNumber: String?
    var logoPath: String?
    var commercialEntities: [CommercialEntity]?
    var legalForm: String?
    var siren: String?
    var deliveryAddress: PostalAddress?

    init(id: String = UUID().uuidString, companyName: String = "", contactName: String = "", address: String = "", email: String = "", phone: String = "", siret: String = "", contacts: [ClientContact] = [], createdAt: Date = Date(), addressDetails: PostalAddress? = nil, vatNumber: String? = nil, logoPath: String? = nil, commercialEntities: [CommercialEntity]? = nil, legalForm: String? = nil, siren: String? = nil, deliveryAddress: PostalAddress? = nil) {
        self.id = id
        self.companyName = companyName
        self.contactName = contactName
        self.address = address
        self.email = email
        self.phone = phone
        self.siret = siret
        self.contacts = contacts
        self.createdAt = createdAt
        self.addressDetails = addressDetails
        self.vatNumber = vatNumber
        self.logoPath = logoPath
        self.commercialEntities = commercialEntities
        self.legalForm = legalForm
        self.siren = siren
        self.deliveryAddress = deliveryAddress
    }

    private enum CodingKeys: String, CodingKey { case id, companyName, contactName, address, email, phone, siret, contacts, createdAt, addressDetails, vatNumber, logoPath, commercialEntities, legalForm, siren, deliveryAddress }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName) ?? ""
        contactName = try container.decodeIfPresent(String.self, forKey: .contactName) ?? ""
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        siret = try container.decodeIfPresent(String.self, forKey: .siret) ?? ""
        contacts = try container.decodeIfPresent([ClientContact].self, forKey: .contacts) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        addressDetails = try container.decodeIfPresent(PostalAddress.self, forKey: .addressDetails)
        vatNumber = try container.decodeIfPresent(String.self, forKey: .vatNumber)
        logoPath = try container.decodeIfPresent(String.self, forKey: .logoPath)
        commercialEntities = try container.decodeIfPresent([CommercialEntity].self, forKey: .commercialEntities)
        legalForm = try container.decodeIfPresent(String.self, forKey: .legalForm)
        siren = try container.decodeIfPresent(String.self, forKey: .siren)
        deliveryAddress = try container.decodeIfPresent(PostalAddress.self, forKey: .deliveryAddress)
    }

    var displayName: String { companyName.isEmpty ? contactName : companyName }
}

struct CatalogItem: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var description = ""
    var unitPriceHT: Double = 0
    var vatRate: Double = 0
    var unit = "unité"
}

struct DocumentItem: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var description = ""
    var quantity: Double = 1
    var unitPriceHT: Double = 0
    var vatRate: Double = 0
    var note: String? = nil
    var unitLabel: String? = "unité"
    var discountPercent: Double? = nil
    var grossLineHT: Double { quantity * unitPriceHT }
    var discountAmount: Double { grossLineHT * min(max(discountPercent ?? 0, 0), 100) / 100 }
    var totalLineHT: Double { grossLineHT - discountAmount }
    var vatAmount: Double { totalLineHT * vatRate / 100 }
    var displayedUnit: String { unitLabel?.isEmpty == false ? unitLabel ?? "unité" : "unité" }
    var formattedQuantity: String { "\(quantity.formatted()) \(displayedUnit)" }
}

struct DocumentPayment: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var date = Date()
    var amount: Double = 0
    var method = "Virement"
    var reference = ""
    var notes = ""
}

struct DocumentEvent: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var date = Date()
    var title = ""
    var details = ""
}

enum SignatureParty: String, Codable, CaseIterable, Identifiable {
    case issuer, recipient
    var id: String { rawValue }
    var title: String { self == .issuer ? "Émetteur" : "Réceptionnaire" }
}

struct SignaturePoint: Codable, Hashable {
    var x: Double
    var y: Double
}

struct DocumentSignature: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var party: SignatureParty = .recipient
    var signerName = ""
    var signerRole = ""
    var signedAt = Date()
    var strokes: [[SignaturePoint]] = []
}

struct DocumentAttachment: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var filename = "Pièce jointe"
    var mimeType = "application/octet-stream"
    var data: Data? = nil
    var createdAt = Date()
}

struct DocumentTemplate: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name = ""
    var document: BillingDocument
    var createdAt = Date()
}

enum OperationCategory: String, Codable, CaseIterable, Identifiable {
    case service, goods, mixed
    var id: String { rawValue }
    var title: String { switch self { case .service: "Prestation de services"; case .goods: "Livraison de biens"; case .mixed: "Biens et prestations" } }
}

struct BillingDocument: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var type: DocumentType = .invoice
    var number = ""
    var clientID = ""
    var status: DocumentStatus = .draft
    var issueDate = Date()
    var dueDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    var notes = ""
    var items: [DocumentItem] = []
    var issuerEntityID: String? = nil
    var clientEntityID: String? = nil
    var projectTitle: String? = nil
    var projectReference: String? = nil
    var purchaseOrderNumber: String? = nil
    var sourceDocumentID: String? = nil
    var sourceDocumentNumber: String? = nil
    var creditReason: String? = nil
    var serviceDate: Date? = nil
    var retentionAmount: Double? = nil
    var depositAmount: Double? = nil
    var alreadyPaidAmount: Double? = nil
    var currencyCode: String? = nil
    var deletedAt: Date? = nil
    var globalDiscountPercent: Double? = nil
    var globalDiscountAmount: Double? = nil
    var payments: [DocumentPayment]? = nil
    var events: [DocumentEvent]? = nil
    var lockedAt: Date? = nil
    var deliveryAddress: PostalAddress? = nil
    var operationCategory: OperationCategory? = nil
    var vatOnDebits: Bool? = nil
    var signatures: [DocumentSignature]? = nil
    var attachments: [DocumentAttachment]? = nil
    var archivedPDFData: Data? = nil
    var archivedAt: Date? = nil
    var subtotalHT: Double { items.reduce(0) { $0 + $1.totalLineHT } }
    var globalDiscountValue: Double {
        if let globalDiscountAmount { return min(max(globalDiscountAmount, 0), max(subtotalHT, 0)) }
        return subtotalHT * min(max(globalDiscountPercent ?? 0, 0), 100) / 100
    }
    var totalHT: Double { subtotalHT - globalDiscountValue }
    var totalVAT: Double {
        guard subtotalHT != 0 else { return 0 }
        return items.reduce(0) { $0 + $1.vatAmount } * (totalHT / subtotalHT)
    }
    var totalTTC: Double { totalHT + totalVAT }
    var paidAmount: Double { (depositAmount ?? 0) + (alreadyPaidAmount ?? 0) + (payments ?? []).reduce(0) { $0 + $1.amount } }
    var netToPay: Double { type == .creditNote ? totalTTC : max(0, totalTTC - (retentionAmount ?? 0) - paidAmount) }
    var creditAmount: Double { abs(totalTTC) }
    var vatBreakdown: [(rate: Double, base: Double, vat: Double)] {
        let ratio = subtotalHT == 0 ? 1 : totalHT / subtotalHT
        let grouped = Dictionary(grouping: items, by: \.vatRate)
        return grouped.map { rate, rows in
            let base = rows.reduce(0) { $0 + $1.totalLineHT } * ratio
            return (rate, base, base * rate / 100)
        }.sorted { $0.rate < $1.rate }
    }
}

struct AppLicense: Codable, Equatable {
    var isProUnlocked = false
    var remainingCredits = 5
    var purchaseDate: Date?
    var transactionID = ""
    var activeProfilesCount = 1
    var processedTransactionIDs: [String]? = nil
    /// Kept optional so existing on-device databases migrate safely.
    var trialDocumentsRemaining: Int? = nil
    var studioExpirationDate: Date? = nil
}

struct BackupPayload: Codable {
    var version = "1.0"
    var appName = "CashDraft"
    var exportDate = Date()
    var profile: CompanyProfile
    var clients: [Client]
    var catalog: [CatalogItem]
    var documents: [BillingDocument]
    var templates: [DocumentTemplate]? = nil
}

struct BackupImportPreview: Identifiable {
    let id = UUID()
    let url: URL
    let exportDate: Date
    let profileName: String
    let clientCount: Int
    let documentCount: Int
    let trashedDocumentCount: Int
}
