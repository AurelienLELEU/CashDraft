package fr.btbu.cashdraft

import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import fr.btbu.cashdraft.core.*
import java.io.ByteArrayOutputStream
import java.math.BigDecimal
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Currency
import java.util.Locale

fun money(amount: BigDecimal, code: String = "EUR"): String = NumberFormat.getCurrencyInstance(Locale.FRANCE).apply {
    currency = runCatching { Currency.getInstance(code) }.getOrDefault(Currency.getInstance("EUR"))
}.format(amount.cents())

fun frenchDate(value: String): String = runCatching {
    DateTimeFormatter.ofPattern("dd/MM/yyyy").withZone(ZoneOffset.UTC).format(Instant.parse(value))
}.getOrDefault(value)

object PdfRenderer {
    fun render(snapshot: Snapshot, document: BillingDocument, draft: Boolean): ByteArray {
        val client = snapshot.clients.find { it.id == document.clientID }
        val currency = document.currencyCode ?: snapshot.profile.currencyCode
        val pdf = PdfDocument()
        try {
            val writer = Writer(pdf, snapshot.profile, client, document, draft)
            writer.newPage()
            writer.line("Description", "Qté / PU HT / TVA", "Total HT", true)
            document.items.forEach { item ->
                writer.ensure(38f)
                val top = writer.position
                writer.right(money(item.totalLineHT, currency), top, 553f, true)
                writer.text("${item.quantity} ${item.unitLabel ?: "unité"} × ${money(decimal(item.unitPriceHT), currency)} · TVA ${item.vatRate} %", 270f, top, 9f)
                writer.paragraph(item.description, width = 218f)
                if ((item.discountPercent ?: 0.0) != 0.0) writer.paragraph("Remise de ligne : ${item.discountPercent} %", 9f)
                item.note?.takeIf { it.isNotBlank() }?.let { writer.paragraph(it, 9f) }
                writer.position += 10f
            }
            writer.ensure(150f)
            writer.line("Sous-total HT", "", money(document.subtotalHT, currency))
            if (document.globalDiscountValue.signum() != 0) writer.line("Remise globale", "", money(document.globalDiscountValue, currency))
            writer.line("Total HT", "", money(document.totalHT, currency), true)
            document.vatBreakdown.forEach { writer.line("TVA ${it.rate} %", "Base ${money(it.base, currency)}", money(it.vat, currency)) }
            writer.line("Total TTC", "", money(document.totalTTC, currency), true)
            if (document.type == DocumentType.CREDIT_NOTE) {
                writer.line("Montant de l'avoir", "", money(document.creditAmount, currency), true)
            } else {
                if (document.paidAmount.signum() != 0) writer.line("Acomptes et encaissements", "", money(document.paidAmount, currency))
                if ((document.retentionAmount ?: 0.0) != 0.0) writer.line("Retenue", "", money(decimal(document.retentionAmount ?: 0.0), currency))
                writer.line("Net à payer", "", money(document.netToPay, currency), true)
            }
            writer.position += 16f
            listOfNotNull(document.projectTitle, document.projectReference?.let { "Référence : $it" }, document.purchaseOrderNumber?.let { "Bon de commande : $it" }, document.sourceDocumentNumber?.let { "Document d'origine : $it" }, document.creditReason, document.notes.takeIf { it.isNotBlank() }).forEach { writer.paragraph(it) }
            writer.paragraph("Conditions de règlement : ${snapshot.profile.defaultPaymentTerms}")
            snapshot.profile.iban?.takeIf { it.isNotBlank() }?.let { writer.paragraph("IBAN : $it · BIC : ${snapshot.profile.bic.orEmpty()}") }
            if (document.items.all { it.vatRate == 0.0 }) writer.paragraph(snapshot.profile.vatExemptionNotice, 9f)
            listOfNotNull(snapshot.profile.earlyPaymentDiscountText, snapshot.profile.latePaymentPenaltyText, snapshot.profile.recoveryIndemnityText, snapshot.profile.footerText).filter { it.isNotBlank() }.forEach { writer.paragraph(it, 9f) }
            writer.finishPage()
            return ByteArrayOutputStream().use { output -> pdf.writeTo(output); output.toByteArray() }
        } finally {
            pdf.close()
        }
    }

    private class Writer(val pdf: PdfDocument, val profile: CompanyProfile, val client: Client?, val document: BillingDocument, val draft: Boolean) {
        private lateinit var page: PdfDocument.Page
        private var pageNumber = 0
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        var position = 0f

        fun newPage() {
            page = pdf.startPage(PdfDocument.PageInfo.Builder(595, 842, ++pageNumber).create())
            page.canvas.drawColor(Color.WHITE)
            text("CashDraft", 42f, 44f, 15f, true, Color.rgb(23, 105, 76))
            right("${document.type.title} ${document.number}", 44f, 553f, true)
            text("${if (draft) "BROUILLON · " else ""}Émission : ${frenchDate(document.issueDate)} · Échéance : ${frenchDate(document.dueDate)}", 42f, 72f, 10f)
            var issuerY = 101f
            var clientY = 101f
            listOf(profile.name, profile.legalForm, profile.address, "SIRET : ${profile.siret}", profile.vatNumber.takeIf { it.isNotBlank() }?.let { "TVA : $it" }.orEmpty(), profile.email, profile.phone).filter { it.isNotBlank() }.forEach { value ->
                wrap(value, 238f, 10f).forEach { text(it, 42f, issuerY, 10f); issuerY += 14f }
            }
            listOfNotNull(client?.displayName, client?.address, client?.siret?.takeIf { it.isNotBlank() }?.let { "SIRET : $it" }, client?.vatNumber?.takeIf { it.isNotBlank() }?.let { "TVA : $it" }, client?.email).filter { it.isNotBlank() }.forEach { value ->
                wrap(value, 248f, 10f).forEach { text(it, 305f, clientY, 10f); clientY += 14f }
            }
            position = maxOf(issuerY, clientY) + 28f
            require(position < 600f) { "Les coordonnées sont trop longues pour le PDF. Raccourcissez-les." }
        }

        fun finishPage() {
            text("${if (draft) "Brouillon non émis · " else ""}CashDraft · ${document.number}", 42f, 810f, 8f)
            right("Page $pageNumber", 810f, 553f)
            pdf.finishPage(page)
        }

        fun ensure(height: Float) {
            if (position + height > 764f) { finishPage(); newPage() }
        }

        fun text(value: String, left: Float, baseline: Float, size: Float = 10f, bold: Boolean = false, color: Int = Color.DKGRAY) {
            paint.textSize = size
            paint.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            paint.color = color
            paint.textAlign = Paint.Align.LEFT
            page.canvas.drawText(value, left, baseline, paint)
        }

        fun right(value: String, baseline: Float, edge: Float, bold: Boolean = false) {
            paint.textSize = 10f
            paint.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            paint.color = Color.DKGRAY
            paint.textAlign = Paint.Align.RIGHT
            page.canvas.drawText(value, edge, baseline, paint)
        }

        fun line(label: String, middle: String, amount: String, bold: Boolean = false) {
            ensure(23f)
            text(label, 42f, position, 10f, bold)
            text(middle, 270f, position, 9f)
            right(amount, position, 553f, bold)
            position += 23f
        }

        fun paragraph(value: String, size: Float = 10f, width: Float = 511f) {
            wrap(value, width, size).forEach { line -> ensure(size + 7f); text(line, 42f, position, size); position += size + 5f }
            position += 4f
        }

        fun wrap(value: String, width: Float, size: Float): List<String> = buildList {
            paint.textSize = size
            paint.typeface = Typeface.DEFAULT
            value.lines().forEach { paragraph ->
                var rest = paragraph
                if (rest.isEmpty()) add("")
                while (rest.isNotEmpty()) {
                    val count = paint.breakText(rest, true, width, null).coerceAtLeast(1)
                    val space = if (count < rest.length) rest.lastIndexOf(' ', count) else -1
                    val end = if (space > 0) space else count
                    add(rest.substring(0, end))
                    rest = rest.substring(end).trimStart()
                }
            }
        }
    }
}