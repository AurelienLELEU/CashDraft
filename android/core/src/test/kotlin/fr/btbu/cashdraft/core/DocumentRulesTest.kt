package fr.btbu.cashdraft.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

class DocumentRulesTest {
    private val profile = CompanyProfile(name = "Entreprise test", address = "1 rue Test", siret = "12345678900000")
    private val client = Client(companyName = "Client test", address = "2 rue Test")
    private fun document() = BillingDocument(number = "FAC-2026-001", clientID = client.id, items = listOf(DocumentItem(description = "Forfait", unitPriceHT = 100.0, vatRate = 20.0)))
    private fun snapshot(document: BillingDocument) = Snapshot(profile = profile, clients = listOf(client), documents = listOf(document))

    @Test fun discountsBeforeVat() {
        val line = DocumentItem(description = "Prestation", quantity = 2.0, unitPriceHT = 100.0, vatRate = 20.0, discountPercent = 10.0)
        val document = BillingDocument(items = listOf(line), globalDiscountPercent = 5.0)
        assertEquals(180.0, line.totalLineHT.toDouble(), 0.001)
        assertEquals(171.0, document.totalHT.toDouble(), 0.001)
        assertEquals(34.2, document.totalVAT.toDouble(), 0.001)
        assertEquals(205.2, document.totalTTC.toDouble(), 0.001)
    }

    @Test fun paymentsReduceBalance() {
        val document = document().copy(payments = listOf(DocumentPayment(amount = 30.0), DocumentPayment(amount = 20.0)))
        assertEquals(50.0, document.paidAmount.toDouble(), 0.001)
        assertEquals(70.0, document.netToPay.toDouble(), 0.001)
    }

    @Test fun creditNoteIsNegative() {
        val document = document().copy(type = DocumentType.CREDIT_NOTE, items = listOf(DocumentItem(unitPriceHT = -100.0, vatRate = 20.0)))
        assertEquals(-120.0, document.totalTTC.toDouble(), 0.001)
        assertEquals(120.0, document.creditAmount.toDouble(), 0.001)
    }

    @Test fun vatGroupedAfterGlobalDiscount() {
        val document = BillingDocument(items = listOf(DocumentItem(unitPriceHT = 100.0, vatRate = 20.0), DocumentItem(unitPriceHT = 50.0, vatRate = 10.0)), globalDiscountPercent = 10.0)
        assertEquals(listOf(10.0, 20.0), document.vatBreakdown.map { it.rate })
        assertEquals(45.0, document.vatBreakdown[0].base.toDouble(), 0.001)
        assertEquals(4.5, document.vatBreakdown[0].vat.toDouble(), 0.001)
        assertEquals(18.0, document.vatBreakdown[1].vat.toDouble(), 0.001)
    }

    @Test fun archivedPdfIsStableAndEmissionIsIdempotent() {
        val document = document()
        val emitted = DocumentRules.issue(snapshot(document), License(), document.id, "%PDF-original".toByteArray())
        assertEquals(4, emitted.second.trialRemaining)
        val repeated = DocumentRules.issue(emitted.first, emitted.second, document.id, "%PDF-new".toByteArray())
        assertEquals(emitted, repeated)
        assertFailsWith<IllegalArgumentException> { DocumentRules.saveDraft(emitted.first, document.copy(notes = "Modification")) }
        val paid = DocumentRules.payment(emitted.first, document.id, DocumentPayment(amount = 120.0))
        assertEquals(DocumentStatus.PAID, paid.documents.first().status)
        assertEquals(emitted.first.documents.first().archivedPDFData, paid.documents.first().archivedPDFData)
    }

    @Test fun failedEmissionDoesNotConsumeAllowance() {
        val document = document().copy(items = emptyList())
        assertFailsWith<IllegalArgumentException> { DocumentRules.issue(snapshot(document), License(), document.id, "%PDF-file".toByteArray()) }
        val valid = document()
        assertFailsWith<IllegalStateException> { DocumentRules.issue(snapshot(valid), License(trialRemaining = 0), valid.id, "%PDF-file".toByteArray()) }
    }

    @Test fun numberingIncludesTrash() {
        val trashed = document().copy(number = "FAC-2026-009", deletedAt = now())
        assertEquals("FAC-2026-010", DocumentRules.nextNumber(snapshot(trashed), DocumentType.INVOICE, 2026))
    }

    @Test fun unknownIosFieldsAndBinaryArchivesSurviveBackup() {
        val encoded = BackupCodec.encode(snapshot(document()))
        val tree = BackupCodec.json.parseToJsonElement(encoded).jsonObject
        val document = tree["documents"]!!.jsonArray.first().jsonObject
        val extendedDocument = kotlinx.serialization.json.JsonObject(document + ("signatures" to BackupCodec.json.parseToJsonElement("[{\"id\":\"s1\",\"signerName\":\"Camille\",\"strokes\":[[{\"x\":0.1,\"y\":0.2}]]}]")) + ("archivedPDFData" to kotlinx.serialization.json.JsonPrimitive("AQID")))
        val extended = kotlinx.serialization.json.JsonObject(tree + ("documents" to kotlinx.serialization.json.JsonArray(listOf(extendedDocument))))
        val decoded = BackupCodec.decode(extended.toString())
        val result = BackupCodec.json.parseToJsonElement(BackupCodec.encode(decoded)).jsonObject["documents"]!!.jsonArray.first().jsonObject
        assertEquals(extendedDocument["signatures"], result["signatures"])
        assertEquals(extendedDocument["archivedPDFData"], result["archivedPDFData"])
    }

    @Test fun rejectsForeignAndIncompleteBackups() {
        assertFailsWith<IllegalArgumentException> { BackupCodec.decode("{\"appName\":\"Other\",\"version\":\"1.0\"}") }
        assertFailsWith<IllegalArgumentException> { BackupCodec.decode("{\"appName\":\"CashDraft\",\"version\":\"1.0\"}") }
        assertTrue(DocumentRules.validation(Snapshot(), document()).isNotEmpty())
    }

    @Test fun exportMatchesRequiredIosFieldsAndDateFormat() {
        val tree = BackupCodec.json.parseToJsonElement(BackupCodec.encode(snapshot(document()))).jsonObject
        assertTrue(tree["profile"]!!.jsonObject.containsKey("logoPath"))
        assertTrue(Regex("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z").matches(now()))
    }

    @Test fun creditNoteRetainsFixedGlobalDiscount() {
        val source = document().copy(globalDiscountAmount = 10.0)
        val credit = DocumentRules.creditNote(snapshot(source), source)
        assertEquals(-source.totalTTC.toDouble(), credit.totalTTC.toDouble(), 0.001)
        assertEquals(source.id, credit.sourceDocumentID)
    }
}