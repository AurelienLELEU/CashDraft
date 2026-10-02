import XCTest
@testable import CashDraft

final class CashDraftTests: XCTestCase {
    func testLineAndGlobalDiscountsAreAppliedBeforeVAT() {
        var item = DocumentItem(description: "Prestation", quantity: 2, unitPriceHT: 100, vatRate: 20)
        item.discountPercent = 10
        var document = BillingDocument(items: [item])
        document.globalDiscountPercent = 5

        XCTAssertEqual(item.totalLineHT, 180, accuracy: 0.001)
        XCTAssertEqual(document.subtotalHT, 180, accuracy: 0.001)
        XCTAssertEqual(document.totalHT, 171, accuracy: 0.001)
        XCTAssertEqual(document.totalVAT, 34.2, accuracy: 0.001)
        XCTAssertEqual(document.totalTTC, 205.2, accuracy: 0.001)
    }

    func testPaymentsReduceRemainingBalance() {
        var document = BillingDocument(items: [DocumentItem(description: "Forfait", quantity: 1, unitPriceHT: 100, vatRate: 20)])
        document.payments = [DocumentPayment(amount: 30), DocumentPayment(amount: 20)]
        XCTAssertEqual(document.paidAmount, 50, accuracy: 0.001)
        XCTAssertEqual(document.netToPay, 70, accuracy: 0.001)
    }

    func testCreditNoteIsNegativeAndUsesAbsoluteCreditAmount() {
        let credit = BillingDocument(type: .creditNote, items: [DocumentItem(description: "Correction", quantity: 1, unitPriceHT: -100, vatRate: 20)])
        XCTAssertEqual(credit.totalTTC, -120, accuracy: 0.001)
        XCTAssertEqual(credit.creditAmount, 120, accuracy: 0.001)
    }

    func testBackupPreviewCountsDeletedDocuments() throws {
        let active = BillingDocument(number: "FAC-2026-001")
        var deleted = BillingDocument(number: "FAC-2026-002")
        deleted.deletedAt = Date()
        let payload = BackupPayload(profile: CompanyProfile(name: "Entreprise test"), clients: [], catalog: [], documents: [active, deleted])
        let data = try JSONEncoder.cashDraft.encode(payload)
        let decoded = try JSONDecoder.cashDraft.decode(BackupPayload.self, from: data)
        XCTAssertEqual(decoded.documents.filter { $0.deletedAt == nil }.count, 1)
        XCTAssertEqual(decoded.documents.filter { $0.deletedAt != nil }.count, 1)
    }

    func testSignatureIsPreservedInDocumentBackup() throws {
        let signature = DocumentSignature(party: .recipient, signerName: "Camille Martin", signerRole: "Direction", strokes: [[SignaturePoint(x: 0.1, y: 0.2), SignaturePoint(x: 0.9, y: 0.8)]])
        let document = BillingDocument(number: "DEV-2026-010", signatures: [signature])
        let data = try JSONEncoder.cashDraft.encode(document)
        let decoded = try JSONDecoder.cashDraft.decode(BillingDocument.self, from: data)
        XCTAssertEqual(decoded.signatures?.first?.signerName, "Camille Martin")
        XCTAssertEqual(decoded.signatures?.first?.strokes.first?.count, 2)
    }

    func testVATBreakdownGroupsRatesAfterDiscount() {
        var document = BillingDocument(items: [
            DocumentItem(description: "Main-d’œuvre", quantity: 1, unitPriceHT: 100, vatRate: 20),
            DocumentItem(description: "Fourniture", quantity: 1, unitPriceHT: 50, vatRate: 10)
        ])
        document.globalDiscountPercent = 10

        XCTAssertEqual(document.vatBreakdown.count, 2)
        XCTAssertEqual(document.vatBreakdown[0].rate, 10, accuracy: 0.001)
        XCTAssertEqual(document.vatBreakdown[0].base, 45, accuracy: 0.001)
        XCTAssertEqual(document.vatBreakdown[0].vat, 4.5, accuracy: 0.001)
        XCTAssertEqual(document.vatBreakdown[1].base, 90, accuracy: 0.001)
        XCTAssertEqual(document.vatBreakdown[1].vat, 18, accuracy: 0.001)
    }

    func testArchivedPDFAndAttachmentSurviveBackupEncoding() throws {
        let attachment = DocumentAttachment(filename: "commande.pdf", mimeType: "application/pdf", data: Data([1, 2, 3]))
        let original = BillingDocument(number: "FAC-2026-010", status: .sent, attachments: [attachment], archivedPDFData: Data([4, 5, 6]), archivedAt: Date())
        let data = try JSONEncoder.cashDraft.encode(original)
        let decoded = try JSONDecoder.cashDraft.decode(BillingDocument.self, from: data)
        XCTAssertEqual(decoded.attachments?.first?.filename, "commande.pdf")
        XCTAssertEqual(decoded.archivedPDFData, Data([4, 5, 6]))
    }
}

private extension JSONEncoder {
    static var cashDraft: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
}

private extension JSONDecoder {
    static var cashDraft: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}
