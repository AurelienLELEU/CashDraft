package fr.btbu.cashdraft.core

import java.time.Instant
import java.time.ZoneOffset
import java.util.Base64

object DocumentRules {
    fun nextNumber(snapshot: Snapshot, type: DocumentType, year: Int = java.time.LocalDate.now().year): String {
        val prefix = "${snapshot.profile.prefix(type)}-$year-"
        val sequence = snapshot.documents.mapNotNull { it.number.takeIf { number -> number.startsWith(prefix) }?.removePrefix(prefix)?.toIntOrNull() }.maxOrNull() ?: 0
        require(sequence < Int.MAX_VALUE) { "Séquence de numérotation épuisée." }
        return prefix + (sequence + 1).toString().padStart(3, '0')
    }

    fun validation(snapshot: Snapshot, document: BillingDocument): List<String> = buildList {
        if (snapshot.profile.name.isBlank()) add("Renseignez la raison sociale de l'émetteur.")
        if (snapshot.profile.legalForm.isBlank()) add("Renseignez la forme juridique.")
        if (snapshot.profile.address.isBlank()) add("Renseignez l'adresse de l'émetteur.")
        if (snapshot.profile.siret.isBlank()) add("Renseignez le SIRET de l'émetteur.")
        if (snapshot.profile.defaultPaymentTerms.isBlank()) add("Renseignez les conditions de règlement.")
        val client = snapshot.clients.find { it.id == document.clientID }
        if (client == null || client.displayName.isBlank() || client.address.isBlank()) add("Sélectionnez un client avec un nom et une adresse.")
        if (document.number.isBlank()) add("Le numéro du document est obligatoire.")
        if (snapshot.documents.any { it.id != document.id && it.number == document.number }) add("Ce numéro de document est déjà utilisé.")
        if (document.items.isEmpty() || document.items.any { it.description.isBlank() || !it.quantity.isFinite() || it.quantity <= 0 || !it.unitPriceHT.isFinite() || !it.vatRate.isFinite() || it.vatRate !in 0.0..100.0 || !(it.discountPercent ?: 0.0).isFinite() }) add("Vérifiez les descriptions, quantités et montants des lignes.")
        if (Instant.parse(document.dueDate) < Instant.parse(document.issueDate)) add("L'échéance précède l'émission.")
    }

    fun saveDraft(snapshot: Snapshot, document: BillingDocument): Snapshot {
        val previous = snapshot.documents.find { it.id == document.id }
        require(previous == null || previous.status == DocumentStatus.DRAFT) { "Un document émis ne peut pas être modifié. Créez un avoir." }
        require(document.status == DocumentStatus.DRAFT) { "Utilisez l'émission pour quitter l'état brouillon." }
        require(snapshot.documents.none { it.id != document.id && it.number == document.number && document.number.isNotBlank() }) { "Numéro déjà utilisé." }
        return snapshot.copy(documents = snapshot.documents.filterNot { it.id == document.id } + document.copy(archivedPDFData = null, archivedAt = null, lockedAt = null))
    }

    fun issue(snapshot: Snapshot, license: License, id: String, pdf: ByteArray): Pair<Snapshot, License> {
        val document = snapshot.documents.first { it.id == id }
        if (document.status != DocumentStatus.DRAFT) return snapshot to license
        val problems = validation(snapshot, document)
        require(problems.isEmpty()) { problems.joinToString("\n") }
        require(pdf.size >= 5 && pdf.take(5).toByteArray().toString(Charsets.US_ASCII) == "%PDF-") { "Le PDF n'a pas été créé." }
        val updatedLicense = license.afterEmission()
        val updated = document.copy(status = DocumentStatus.SENT, lockedAt = now(), archivedAt = now(), archivedPDFData = Base64.getEncoder().encodeToString(pdf), events = (document.events ?: emptyList()) + DocumentEvent(title = "Document émis", details = "PDF archivé sur cet appareil."))
        return snapshot.copy(documents = snapshot.documents.map { if (it.id == id) updated else it }) to updatedLicense
    }

    fun payment(snapshot: Snapshot, id: String, payment: DocumentPayment): Snapshot {
        require(payment.amount.isFinite() && payment.amount > 0) { "Le montant doit être positif." }
        val document = snapshot.documents.first { it.id == id }
        require(document.status == DocumentStatus.SENT || document.status == DocumentStatus.PAID) { "Émettez d'abord le document." }
        require(document.type != DocumentType.CREDIT_NOTE) { "Un avoir ne reçoit pas de paiement." }
        val withPayment = document.copy(payments = (document.payments ?: emptyList()) + payment, events = (document.events ?: emptyList()) + DocumentEvent(title = "Paiement enregistré", details = payment.method))
        val updated = withPayment.copy(status = if (withPayment.netToPay.cents().signum() == 0) DocumentStatus.PAID else DocumentStatus.SENT)
        return snapshot.copy(documents = snapshot.documents.map { if (it.id == id) updated else it })
    }

    fun convertQuote(snapshot: Snapshot, quote: BillingDocument): BillingDocument {
        require(quote.type == DocumentType.QUOTE)
        return quote.copy(id = newId(), type = DocumentType.INVOICE, number = nextNumber(snapshot, DocumentType.INVOICE), status = DocumentStatus.DRAFT, issueDate = dateAt(), dueDate = dateAt(30), sourceDocumentID = quote.id, sourceDocumentNumber = quote.number, payments = null, events = null, lockedAt = null, archivedPDFData = null, archivedAt = null, deletedAt = null)
    }

    fun creditNote(snapshot: Snapshot, source: BillingDocument): BillingDocument {
        require(source.type == DocumentType.INVOICE || source.type == DocumentType.HONORARIUM_NOTE)
        val discountPercent = if (source.subtotalHT.signum() == 0) 0.0 else source.globalDiscountValue.divide(source.subtotalHT, java.math.MathContext.DECIMAL128).movePointRight(2).toDouble()
        return BillingDocument(type = DocumentType.CREDIT_NOTE, number = nextNumber(snapshot, DocumentType.CREDIT_NOTE), clientID = source.clientID, dueDate = dateAt(), items = source.items.map { it.copy(id = newId(), unitPriceHT = -kotlin.math.abs(it.unitPriceHT)) }, globalDiscountPercent = discountPercent, currencyCode = source.currencyCode, sourceDocumentID = source.id, sourceDocumentNumber = source.number, creditReason = "Correction du document ${source.number}")
    }

    fun year(document: BillingDocument): Int = Instant.parse(document.issueDate).atZone(ZoneOffset.UTC).year
}