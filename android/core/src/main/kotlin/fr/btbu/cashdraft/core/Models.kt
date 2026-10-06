package fr.btbu.cashdraft.core

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import kotlinx.serialization.json.JsonObject

fun newId(): String = UUID.randomUUID().toString()
fun now(): String = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()
fun dateAt(days: Long = 0): String = LocalDate.now().plusDays(days).atStartOfDay().toInstant(ZoneOffset.UTC).toString()
fun decimal(value: Double): BigDecimal = BigDecimal.valueOf(value)
fun BigDecimal.cents(): BigDecimal = setScale(2, RoundingMode.HALF_UP)

@Serializable
enum class DocumentType(val title: String, val prefix: String) {
    INVOICE("Facture", "FAC"), QUOTE("Devis", "DEV"), CREDIT_NOTE("Avoir", "AVO"), HONORARIUM_NOTE("Note d'honoraires", "HON")
}

@Serializable
enum class DocumentStatus(val title: String) {
    DRAFT("Brouillon"), SENT("Envoyé"), PAID("Payé"), CANCELLED("Annulé")
}

@Serializable
data class CompanyProfile(
    val id: Int = 1,
    val name: String = "",
    val legalForm: String = "Auto-entrepreneur",
    val address: String = "",
    val siret: String = "",
    val vatNumber: String = "",
    val vatExemptionNotice: String = "TVA non applicable, art. 293 B du CGI",
    val email: String = "",
    val phone: String = "",
    val logoPath: String = "",
    val defaultPaymentTerms: String = "Paiement à réception",
    val currencyCode: String = "EUR",
    val footerText: String? = null,
    val earlyPaymentDiscountText: String? = "Escompte pour paiement anticipé : néant.",
    val latePaymentPenaltyText: String? = "Pénalités de retard : trois fois le taux d'intérêt légal.",
    val recoveryIndemnityText: String? = "Indemnité forfaitaire de recouvrement : 40 € (articles L441-10 et D441-5 du Code de commerce).",
    val iban: String? = null,
    val bic: String? = null,
    val invoicePrefix: String? = null,
    val quotePrefix: String? = null,
    val creditNotePrefix: String? = null,
    val honorariumPrefix: String? = null,
) {
    fun prefix(type: DocumentType): String = when (type) {
        DocumentType.INVOICE -> invoicePrefix
        DocumentType.QUOTE -> quotePrefix
        DocumentType.CREDIT_NOTE -> creditNotePrefix
        DocumentType.HONORARIUM_NOTE -> honorariumPrefix
    }?.trim()?.takeIf { it.isNotEmpty() } ?: type.prefix
}

@Serializable
data class Client(
    val id: String = newId(),
    val companyName: String = "",
    val contactName: String = "",
    val address: String = "",
    val email: String = "",
    val phone: String = "",
    val siret: String = "",
    val vatNumber: String? = null,
    val createdAt: String = now(),
) {
    val displayName: String get() = companyName.ifBlank { contactName }
}

@Serializable
data class CatalogItem(
    val id: String = newId(),
    val description: String = "",
    val unitPriceHT: Double = 0.0,
    val vatRate: Double = 0.0,
    val unit: String = "unité",
)

@Serializable
data class DocumentItem(
    val id: String = newId(),
    val description: String = "",
    val quantity: Double = 1.0,
    val unitPriceHT: Double = 0.0,
    val vatRate: Double = 0.0,
    val note: String? = null,
    val unitLabel: String? = "unité",
    val discountPercent: Double? = null,
) {
    val grossLineHT: BigDecimal get() = decimal(quantity).multiply(decimal(unitPriceHT))
    val totalLineHT: BigDecimal get() = grossLineHT.multiply(BigDecimal.ONE.subtract(decimal((discountPercent ?: 0.0).coerceIn(0.0, 100.0)).movePointLeft(2)))
    val vatAmount: BigDecimal get() = totalLineHT.multiply(decimal(vatRate)).movePointLeft(2)
}

@Serializable
data class DocumentPayment(
    val id: String = newId(),
    val date: String = now(),
    val amount: Double = 0.0,
    val method: String = "Virement",
    val reference: String = "",
    val notes: String = "",
)

@Serializable
data class DocumentEvent(
    val id: String = newId(),
    val date: String = now(),
    val title: String = "",
    val details: String = "",
)

data class VatRow(val rate: Double, val base: BigDecimal, val vat: BigDecimal)

@Serializable
data class BillingDocument(
    val id: String = newId(),
    val type: DocumentType = DocumentType.INVOICE,
    val number: String = "",
    val clientID: String = "",
    val status: DocumentStatus = DocumentStatus.DRAFT,
    val issueDate: String = dateAt(),
    val dueDate: String = dateAt(30),
    val notes: String = "",
    val items: List<DocumentItem> = emptyList(),
    val projectTitle: String? = null,
    val projectReference: String? = null,
    val purchaseOrderNumber: String? = null,
    val sourceDocumentID: String? = null,
    val sourceDocumentNumber: String? = null,
    val creditReason: String? = null,
    val retentionAmount: Double? = null,
    val depositAmount: Double? = null,
    val alreadyPaidAmount: Double? = null,
    val currencyCode: String? = null,
    val deletedAt: String? = null,
    val globalDiscountPercent: Double? = null,
    val globalDiscountAmount: Double? = null,
    val payments: List<DocumentPayment>? = null,
    val events: List<DocumentEvent>? = null,
    val lockedAt: String? = null,
    val archivedPDFData: String? = null,
    val archivedAt: String? = null,
) {
    val subtotalHT: BigDecimal get() = items.fold(BigDecimal.ZERO) { amount, item -> amount.add(item.totalLineHT) }
    val globalDiscountValue: BigDecimal get() = globalDiscountAmount?.let { decimal(it).max(BigDecimal.ZERO).min(subtotalHT.max(BigDecimal.ZERO)) }
        ?: subtotalHT.multiply(decimal((globalDiscountPercent ?: 0.0).coerceIn(0.0, 100.0))).movePointLeft(2)
    val totalHT: BigDecimal get() = subtotalHT.subtract(globalDiscountValue)
    private val ratio: BigDecimal get() = if (subtotalHT.signum() == 0) BigDecimal.ZERO else totalHT.divide(subtotalHT, MathContext.DECIMAL128)
    val totalVAT: BigDecimal get() = items.fold(BigDecimal.ZERO) { amount, item -> amount.add(item.vatAmount) }.multiply(ratio)
    val totalTTC: BigDecimal get() = totalHT.add(totalVAT)
    val paidAmount: BigDecimal get() = (payments ?: emptyList()).fold(decimal(depositAmount ?: 0.0).add(decimal(alreadyPaidAmount ?: 0.0))) { amount, payment -> amount.add(decimal(payment.amount)) }
    val netToPay: BigDecimal get() = if (type == DocumentType.CREDIT_NOTE) totalTTC else totalTTC.subtract(decimal(retentionAmount ?: 0.0)).subtract(paidAmount).max(BigDecimal.ZERO)
    val creditAmount: BigDecimal get() = totalTTC.abs()
    val vatBreakdown: List<VatRow> get() = items.groupBy { it.vatRate }.toSortedMap().map { (rate, lines) ->
        val base = lines.fold(BigDecimal.ZERO) { total, line -> total.add(line.totalLineHT) }.multiply(if (subtotalHT.signum() == 0) BigDecimal.ONE else ratio)
        VatRow(rate, base, base.multiply(decimal(rate)).movePointLeft(2))
    }
}

@Serializable
data class Snapshot(
    val version: String = "1.0",
    val appName: String = "CashDraft",
    val exportDate: String = now(),
    val profile: CompanyProfile = CompanyProfile(),
    val clients: List<Client> = emptyList(),
    val catalog: List<CatalogItem> = emptyList(),
    val documents: List<BillingDocument> = emptyList(),
    val templates: List<JsonObject>? = null,
    @Transient val original: JsonObject? = null,
)

@Serializable
data class License(val trialRemaining: Int = 5, val credits: Int = 0) {
    fun afterEmission(): License = when {
        trialRemaining > 0 -> copy(trialRemaining = trialRemaining - 1)
        credits > 0 -> copy(credits = credits - 1)
        else -> error("Les cinq émissions d'essai sont épuisées. Les offres Google Play ne sont pas encore activées.")
    }
}