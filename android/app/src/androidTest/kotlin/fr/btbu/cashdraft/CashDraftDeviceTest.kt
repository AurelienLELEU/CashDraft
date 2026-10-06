package fr.btbu.cashdraft

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer as AndroidPdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import fr.btbu.cashdraft.core.*
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CashDraftDeviceTest {
    @get:Rule val compose = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun databaseRetainsLargeBackupAndImportRollbackWithoutResettingRights() {
        val name = "cashdraft-test-${UUID.randomUUID()}.sqlite"
        val document = BillingDocument(notes = "é".repeat(1_500_000), number = "FAC-2026-001")
        val snapshot = Snapshot(documents = listOf(document))
        var database = CashDatabase(context, name)
        try {
            database.save(snapshot, License(trialRemaining = 2))
            database.close()
            database = CashDatabase(context, name)
            assertEquals(document.notes, database.load().first.documents.single().notes)
            assertEquals(2, database.load().second.trialRemaining)
            database.save(Snapshot(profile = CompanyProfile(name = "Import")), License(trialRemaining = 2), importing = true)
            assertEquals(document.notes, database.previousImport().documents.single().notes)
            assertEquals(2, database.load().second.trialRemaining)
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }

    @Test fun multiPagePdfRendersNonBlankPixels() {
        val client = Client(companyName = "Client test", address = "2 rue du Test, Paris")
        val profile = CompanyProfile(name = "Émetteur test", address = "1 rue du Test, Paris", siret = "12345678900000")
        val document = BillingDocument(number = "FAC-2026-001", clientID = client.id, items = (1..90).map { DocumentItem(description = "Prestation détaillée numéro $it", unitPriceHT = 100.0, vatRate = 20.0) })
        val bytes = PdfRenderer.render(Snapshot(profile = profile, clients = listOf(client)), document, draft = false)
        val file = File(context.cacheDir, "test-${UUID.randomUUID()}.pdf")
        try {
            file.writeBytes(bytes)
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                AndroidPdfRenderer(descriptor).use { renderer ->
                    assertTrue(renderer.pageCount > 1)
                    renderer.openPage(0).use { page ->
                        val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(Color.WHITE)
                            page.render(bitmap, null, null, AndroidPdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            val pixels = IntArray(bitmap.width * bitmap.height)
                            bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                            assertTrue(pixels.count { it != Color.WHITE } > 1000)
                        } finally { bitmap.recycle() }
                    }
                }
            }
        } finally { file.delete() }
    }

    @Test fun navigationOpensClientCatalogueAndSettings() {
        val model = CashViewModel(context.applicationContext as android.app.Application)
        compose.setContent { CashDraftApp(onShare = { _, _ -> }, model = model) }
        compose.waitUntil(10_000) { model.state.value.snapshot != null }
        compose.onNodeWithText("Clients").performClick()
        compose.onNodeWithText("Rechercher un client").assertIsDisplayed()
        compose.onNodeWithText("Catalogue").performClick()
        compose.onNodeWithText("Rechercher un article").assertIsDisplayed()
        compose.onNodeWithText("Réglages").performClick()
        compose.onNodeWithText("Exporter la sauvegarde JSON").assertIsDisplayed()
    }
}