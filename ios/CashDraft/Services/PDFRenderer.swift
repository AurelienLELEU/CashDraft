import UIKit

enum PDFRenderer {
    static func render(document: BillingDocument, client: Client?, company: CompanyProfile, draftWatermark: Bool = false) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(document.number.isEmpty ? "document" : document.number).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            let navy = UIColor(hex: company.brandColorHex) ?? UIColor(red: 0.04, green: 0.10, blue: 0.20, alpha: 1)
            let mint = UIColor(red: 0.12, green: 0.78, blue: 0.60, alpha: 1)
            let currencyCode = document.currencyCode ?? company.currencyCode
            let bodyFontName = company.pdfFontName ?? "HelveticaNeue"
            func bodyFont(_ size: CGFloat) -> UIFont { UIFont(name: bodyFontName, size: size) ?? .systemFont(ofSize: size) }
            func text(_ content: String, _ rect: CGRect, font: UIFont, color: UIColor = navy, alignment: NSTextAlignment = .left) {
                let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = .byWordWrapping
                (content as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
            }
            func drawDraftWatermark() {
                guard draftWatermark else { return }
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: page.midX, y: page.midY)
                context.cgContext.rotate(by: -.pi / 5)
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 42), .foregroundColor: UIColor.gray.withAlphaComponent(0.17)]
                for y in stride(from: -520 as CGFloat, through: 520, by: 130) {
                    for x in stride(from: -450 as CGFloat, through: 450, by: 250) { ("BROUILLON" as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes) }
                }
                context.cgContext.restoreGState()
            }

            let issuerEntity = company.commercialEntities?.first { $0.id == document.issuerEntityID }
            let clientEntity = client?.commercialEntities?.first { $0.id == document.clientEntityID }
            let issuerForm = issuerEntity?.legalForm.isEmpty == false ? issuerEntity?.legalForm ?? "" : company.legalForm
            let issuerBusiness = issuerEntity?.name.isEmpty == false ? issuerEntity?.name ?? "" : company.name
            let issuerName = [issuerForm, issuerBusiness].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
            let issuerAddress = (issuerEntity?.usesParentAddress == false ? issuerEntity?.address.formatted : nil) ?? company.addressDetails?.formatted ?? company.address
            let issuerRegistration = issuerEntity?.registrationNumber.isEmpty == false ? issuerEntity?.registrationNumber ?? "" : company.siret
            let issuerVAT = issuerEntity?.vatNumber.isEmpty == false ? issuerEntity?.vatNumber ?? "" : company.vatNumber
            let issuerLogoPath = issuerEntity?.logoPath.isEmpty == false ? issuerEntity?.logoPath ?? "" : company.logoPath
            let clientName = clientEntity?.name.isEmpty == false ? clientEntity?.name ?? "" : client?.displayName ?? "Client non renseigné"
            let clientAddress = (clientEntity?.usesParentAddress == false ? clientEntity?.address.formatted : nil) ?? client?.addressDetails?.formatted ?? client?.address ?? ""
            let clientRegistration = clientEntity?.registrationNumber.isEmpty == false ? clientEntity?.registrationNumber ?? "" : client?.siret ?? ""
            let clientVAT = clientEntity?.vatNumber.isEmpty == false ? clientEntity?.vatNumber ?? "" : client?.vatNumber ?? ""
            let clientLogoPath = clientEntity?.logoPath.isEmpty == false ? clientEntity?.logoPath : client?.logoPath

            func drawTop(continuation: Bool) {
                context.cgContext.setFillColor(navy.cgColor)
                context.cgContext.fill(CGRect(x: 0, y: 0, width: page.width, height: continuation ? 78 : 110))
                if !continuation, let logo = UIImage(contentsOfFile: issuerLogoPath) { logo.draw(in: CGRect(x: 42, y: 25, width: 60, height: 60)) }
                text(issuerName.isEmpty ? "Votre entreprise" : issuerName, CGRect(x: issuerLogoPath.isEmpty || continuation ? 42 : 116, y: continuation ? 25 : 35, width: 260, height: 28), font: .boldSystemFont(ofSize: 17), color: .white)
                text(document.type.title.uppercased() + (continuation ? " — SUITE" : ""), CGRect(x: 330, y: continuation ? 22 : 40, width: 220, height: 25), font: .boldSystemFont(ofSize: document.type == .honorariumNote ? 14 : 17), color: mint, alignment: .right)
                text(document.number, CGRect(x: 360, y: continuation ? 48 : 68, width: 190, height: 16), font: .systemFont(ofSize: 10), color: .white, alignment: .right)
                drawDraftWatermark()
            }
            func drawTableHeader(at y: CGFloat) {
                context.cgContext.setFillColor(navy.cgColor); context.cgContext.fill(CGRect(x: 42, y: y, width: 511, height: 27))
                text("DESCRIPTION", CGRect(x: 52, y: y + 8, width: 205, height: 13), font: .boldSystemFont(ofSize: 8), color: .white)
                text("QTÉ", CGRect(x: 265, y: y + 8, width: 35, height: 13), font: .boldSystemFont(ofSize: 8), color: .white, alignment: .right)
                text("PU HT", CGRect(x: 315, y: y + 8, width: 70, height: 13), font: .boldSystemFont(ofSize: 8), color: .white, alignment: .right)
                text("TVA", CGRect(x: 397, y: y + 8, width: 42, height: 13), font: .boldSystemFont(ofSize: 8), color: .white, alignment: .right)
                text("TOTAL HT", CGRect(x: 455, y: y + 8, width: 85, height: 13), font: .boldSystemFont(ofSize: 8), color: .white, alignment: .right)
            }
            func continuationPage(withTable: Bool) -> CGFloat {
                context.beginPage(); drawTop(continuation: true)
                if withTable { drawTableHeader(at: 98); return 133 }
                return 104
            }

            context.beginPage(); drawTop(continuation: false)
            var y: CGFloat = 145
            text("ÉMETTEUR", CGRect(x: 42, y: y, width: 220, height: 16), font: .boldSystemFont(ofSize: 9), color: .gray); y += 18
            let rcs = [company.rcsCity, company.rcsNumber].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            let issuerDetails = [issuerAddress, issuerRegistration.isEmpty ? "" : "SIRET : \(issuerRegistration)", issuerVAT.isEmpty ? "" : "TVA : \(issuerVAT)", company.shareCapital.map { "Capital social : \($0)" } ?? "", rcs.isEmpty ? "" : "RCS : \(rcs)", issuerEntity?.email.isEmpty == false ? issuerEntity?.email ?? "" : company.email].filter { !$0.isEmpty }.joined(separator: "\n")
            text(issuerDetails, CGRect(x: 42, y: y, width: 230, height: 100), font: bodyFont(9))
            text("CLIENT", CGRect(x: 320, y: 145, width: 220, height: 16), font: .boldSystemFont(ofSize: 9), color: .gray)
            if let path = clientLogoPath, let logo = UIImage(contentsOfFile: path) { logo.draw(in: CGRect(x: 505, y: 145, width: 38, height: 38)) }
            let clientDetails = [clientName, client?.legalForm ?? "", client?.contactName ?? "", clientAddress, clientRegistration.isEmpty ? "" : "SIRET : \(clientRegistration)", client?.siren.map { "SIREN : \($0)" } ?? "", clientVAT.isEmpty ? "" : "TVA : \(clientVAT)", clientEntity?.email.isEmpty == false ? clientEntity?.email ?? "" : client?.email ?? "", clientEntity?.phone.isEmpty == false ? clientEntity?.phone ?? "" : client?.phone ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
            text(clientDetails, CGRect(x: 320, y: 163, width: 230, height: 100), font: bodyFont(9))
            text("Émise le \(Formatters.date.string(from: document.issueDate))  •  Échéance \(Formatters.date.string(from: document.dueDate))", CGRect(x: 42, y: 255, width: 510, height: 16), font: .systemFont(ofSize: 10), color: .darkGray)
            var metadataY: CGFloat = 273
            if let serviceDate = document.serviceDate { text("Date effective de prestation / livraison : \(Formatters.date.string(from: serviceDate))", CGRect(x: 42, y: metadataY, width: 510, height: 15), font: .systemFont(ofSize: 9), color: .darkGray); metadataY += 18 }
            let reference = [document.type == .creditNote ? document.sourceDocumentNumber.map { "Avoir relatif à la facture : \($0)" } : nil, document.projectTitle, document.projectReference.map { "Engagement / contrat : \($0)" }, document.purchaseOrderNumber.map { "BC : \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
            if !reference.isEmpty { text(reference, CGRect(x: 42, y: metadataY, width: 510, height: 28), font: .systemFont(ofSize: 9), color: .darkGray); metadataY += 25 }
            if let category = document.operationCategory { text("Nature de l’opération : \(category.title)\(document.vatOnDebits == true ? " • TVA sur les débits" : "")", CGRect(x: 42, y: metadataY, width: 510, height: 15), font: .systemFont(ofSize: 9), color: .darkGray); metadataY += 18 }
            if let delivery = document.deliveryAddress ?? client?.deliveryAddress, !delivery.formatted.isEmpty { text("Adresse de livraison : \(delivery.formatted.replacingOccurrences(of: "\n", with: ", "))", CGRect(x: 42, y: metadataY, width: 510, height: 24), font: .systemFont(ofSize: 9), color: .darkGray); metadataY += 24 }

            y = max(305, metadataY + 4); drawTableHeader(at: y); y += 35
            for item in document.items {
                let lineHeight: CGFloat = item.note?.isEmpty == false ? 42 : 29
                if y + lineHeight > 650 { y = continuationPage(withTable: true) }
                text(item.description, CGRect(x: 52, y: y, width: 205, height: 18), font: bodyFont(10))
                if let note = item.note, !note.isEmpty { text(note, CGRect(x: 52, y: y + 16, width: 205, height: 16), font: bodyFont(8), color: .darkGray) }
                text(item.formattedQuantity, CGRect(x: 250, y: y, width: 50, height: 18), font: bodyFont(9), alignment: .right)
                text(Formatters.money(item.unitPriceHT, currencyCode: currencyCode), CGRect(x: 315, y: y, width: 70, height: 18), font: bodyFont(10), alignment: .right)
                text("\(item.vatRate.formatted()) %", CGRect(x: 397, y: y, width: 42, height: 18), font: bodyFont(10), alignment: .right)
                text(Formatters.money(item.totalLineHT, currencyCode: currencyCode), CGRect(x: 455, y: y, width: 85, height: 18), font: bodyFont(10), alignment: .right)
                context.cgContext.setStrokeColor(UIColor.systemGray5.cgColor); context.cgContext.stroke(CGRect(x: 42, y: y + lineHeight - 6, width: 511, height: 0.5)); y += lineHeight
            }

            let vatRows = document.vatBreakdown.count
            let totalRows = 3 + vatRows + (document.globalDiscountValue > 0 ? 1 : 0) + (document.type == .creditNote ? 1 : 1 + ((document.retentionAmount ?? 0) > 0 ? 1 : 0) + (document.paidAmount > 0 ? 1 : 0))
            if y + CGFloat(totalRows * 24 + 45) > 650 { y = continuationPage(withTable: false) }
            y += 15
            if vatRows > 0 {
                text("RÉCAPITULATIF TVA", CGRect(x: 42, y: y, width: 170, height: 14), font: .boldSystemFont(ofSize: 8), color: .gray)
                text("Taux", CGRect(x: 230, y: y, width: 48, height: 14), font: .boldSystemFont(ofSize: 8), color: .gray, alignment: .right)
                text("Base HT", CGRect(x: 292, y: y, width: 80, height: 14), font: .boldSystemFont(ofSize: 8), color: .gray, alignment: .right)
                text("TVA", CGRect(x: 382, y: y, width: 70, height: 14), font: .boldSystemFont(ofSize: 8), color: .gray, alignment: .right)
                y += 15
                for entry in document.vatBreakdown {
                    text("TVA \(entry.rate.formatted()) %", CGRect(x: 42, y: y, width: 180, height: 14), font: .systemFont(ofSize: 8), color: .darkGray)
                    text("\(entry.rate.formatted()) %", CGRect(x: 230, y: y, width: 48, height: 14), font: .systemFont(ofSize: 8), color: .darkGray, alignment: .right)
                    text(Formatters.money(entry.base, currencyCode: currencyCode), CGRect(x: 292, y: y, width: 80, height: 14), font: .systemFont(ofSize: 8), color: .darkGray, alignment: .right)
                    text(Formatters.money(entry.vat, currencyCode: currencyCode), CGRect(x: 382, y: y, width: 70, height: 14), font: .systemFont(ofSize: 8), color: .darkGray, alignment: .right)
                    y += 15
                }
                y += 3
            }
            if document.globalDiscountValue > 0 { text("Remise globale HT", CGRect(x: 365, y: y, width: 85, height: 20), font: .systemFont(ofSize: 10), alignment: .right); text("− " + Formatters.money(document.globalDiscountValue, currencyCode: currencyCode), CGRect(x: 460, y: y, width: 80, height: 20), font: .systemFont(ofSize: 10), color: .darkGray, alignment: .right); y += 24 }
            for (label, amount) in [("Total HT", document.totalHT), ("TVA", document.totalVAT), (document.type == .creditNote ? "Total avoir TTC" : "Total TTC", document.totalTTC)] { let prominent = label.contains("TTC"); text(label, CGRect(x: 365, y: y, width: 85, height: 20), font: prominent ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 10), alignment: .right); text(Formatters.money(amount, currencyCode: currencyCode), CGRect(x: 460, y: y, width: 80, height: 20), font: prominent ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 10), color: prominent ? navy : .darkGray, alignment: .right); y += 24 }
            if document.type == .creditNote { text("Avoir à déduire", CGRect(x: 365, y: y, width: 85, height: 20), font: .boldSystemFont(ofSize: 12), alignment: .right); text(Formatters.money(document.creditAmount, currencyCode: currencyCode), CGRect(x: 460, y: y, width: 80, height: 20), font: .boldSystemFont(ofSize: 12), color: navy, alignment: .right); y += 24
            } else {
                for (label, amount) in [("Retenue de garantie / caution", document.retentionAmount ?? 0), ("À déduire (déjà payé / acompte)", document.paidAmount)].filter({ $0.1 > 0 }) { text(label, CGRect(x: 330, y: y, width: 120, height: 20), font: .systemFont(ofSize: 10), alignment: .right); text("− " + Formatters.money(amount, currencyCode: currencyCode), CGRect(x: 460, y: y, width: 80, height: 20), font: .systemFont(ofSize: 10), color: .darkGray, alignment: .right); y += 22 }
                text("Net à payer", CGRect(x: 365, y: y, width: 85, height: 20), font: .boldSystemFont(ofSize: 12), alignment: .right); text(Formatters.money(document.netToPay, currencyCode: currencyCode), CGRect(x: 460, y: y, width: 80, height: 20), font: .boldSystemFont(ofSize: 12), color: navy, alignment: .right); y += 24
            }
            if !(document.signatures ?? []).isEmpty {
                if y + 118 > 650 { y = continuationPage(withTable: false) }
                text("SIGNATURES CASHDRAFT", CGRect(x: 42, y: y + 10, width: 240, height: 16), font: .boldSystemFont(ofSize: 9), color: .gray)
                let signatures = Array((document.signatures ?? []).prefix(2))
                for (index, signature) in signatures.enumerated() {
                    let x: CGFloat = 42 + CGFloat(index) * 260
                    let box = CGRect(x: x, y: y + 30, width: 230, height: 58)
                    context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor); context.cgContext.stroke(box)
                    text("\(signature.party.title) — \(signature.signerName)", CGRect(x: x + 7, y: y + 34, width: 215, height: 12), font: .systemFont(ofSize: 8), color: .darkGray)
                    text(Formatters.date.string(from: signature.signedAt), CGRect(x: x + 7, y: y + 46, width: 215, height: 10), font: .systemFont(ofSize: 7), color: .gray)
                    context.cgContext.saveGState(); context.cgContext.clip(to: CGRect(x: x + 95, y: y + 31, width: 128, height: 52))
                    for stroke in signature.strokes where stroke.count > 1 {
                        let drawRect = CGRect(x: x + 95, y: y + 31, width: 128, height: 52)
                        context.cgContext.beginPath(); context.cgContext.move(to: CGPoint(x: drawRect.minX + CGFloat(stroke[0].x) * drawRect.width, y: drawRect.minY + CGFloat(stroke[0].y) * drawRect.height))
                        for point in stroke.dropFirst() { context.cgContext.addLine(to: CGPoint(x: drawRect.minX + CGFloat(point.x) * drawRect.width, y: drawRect.minY + CGFloat(point.y) * drawRect.height)) }
                        context.cgContext.setStrokeColor(navy.cgColor); context.cgContext.setLineWidth(1.4); context.cgContext.strokePath()
                    }
                    context.cgContext.restoreGState()
                }
                y += 105
            }
            let paymentSummary = (document.payments ?? []).isEmpty ? "" : "Règlements enregistrés : \((document.payments ?? []).map { "\(Formatters.date.string(from: $0.date)) — \(Formatters.money($0.amount, currencyCode: currencyCode)) \($0.method)" }.joined(separator: " • "))"
            let footer = [company.vatExemptionNotice, company.defaultPaymentTerms, company.earlyPaymentDiscountText, company.latePaymentPenaltyText, company.recoveryIndemnityText, company.iban.map { "IBAN : \($0)" }, company.bic.map { "BIC : \($0)" }, company.footerText, paymentSummary, (document.signatures ?? []).isEmpty ? nil : "Signature CashDraft : trace de réception ou de bon pour accord, non qualifiée eIDAS/UE.", document.creditReason.map { "Motif de l’avoir : \($0)" }, document.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            if y + 35 > 735 { y = continuationPage(withTable: false) }
            text(footer, CGRect(x: 42, y: max(y + 20, 660), width: 510, height: 135), font: .systemFont(ofSize: 8), color: .darkGray)
        }
        return url
    }
}

private extension UIColor {
    convenience init?(hex: String?) {
        guard let hex else { return nil }
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
