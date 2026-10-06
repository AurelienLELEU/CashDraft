package fr.btbu.cashdraft

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import fr.btbu.cashdraft.core.*
import java.io.ByteArrayOutputStream
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

data class AppState(
    val snapshot: Snapshot? = null,
    val license: License = License(),
    val busy: Boolean = false,
    val error: String? = null,
    val importPreview: Snapshot? = null,
    val notice: String? = null,
)

class CashViewModel(application: Application) : AndroidViewModel(application) {
    private val database = CashDatabase(application)
    private val mutableState = MutableStateFlow(AppState())
    val state = mutableState.asStateFlow()
    private val mutex = Mutex()

    init { load() }

    fun load() = perform { current ->
        val (snapshot, license) = database.load()
        current.copy(snapshot = snapshot, license = license)
    }

    private fun perform(onSuccess: () -> Unit = {}, operation: suspend (AppState) -> AppState) {
        viewModelScope.launch {
            mutex.withLock {
                val current = mutableState.value
                mutableState.value = current.copy(busy = true, error = null, notice = null)
                try {
                    mutableState.value = withContext(Dispatchers.IO) { operation(current) }.copy(busy = false)
                    onSuccess()
                } catch (error: Exception) {
                    mutableState.value = current.copy(busy = false, error = error.message ?: "Opération impossible. Les données n'ont pas été remplacées.")
                }
            }
        }
    }

    private fun change(onSuccess: () -> Unit = {}, transform: (Snapshot) -> Snapshot) = perform(onSuccess) { current ->
        val snapshot = transform(requireNotNull(current.snapshot))
        database.save(snapshot, current.license)
        current.copy(snapshot = snapshot)
    }

    fun saveProfile(profile: CompanyProfile, done: () -> Unit) = change(done) { it.copy(profile = profile) }
    fun saveClient(client: Client, done: () -> Unit) = change(done) { snapshot ->
        require(client.displayName.isNotBlank()) { "Le nom du client est obligatoire." }
        snapshot.copy(clients = snapshot.clients.filterNot { it.id == client.id } + client)
    }
    fun deleteClient(id: String, done: () -> Unit) = change(done) { snapshot ->
        require(snapshot.documents.none { it.clientID == id }) { "Ce client est utilisé par un document, y compris dans la corbeille." }
        snapshot.copy(clients = snapshot.clients.filterNot { it.id == id })
    }
    fun saveCatalog(item: CatalogItem, done: () -> Unit) = change(done) { snapshot ->
        require(item.description.isNotBlank() && item.unitPriceHT.isFinite() && item.unitPriceHT >= 0 && item.vatRate in 0.0..100.0) { "Vérifiez le libellé, le prix et la TVA." }
        snapshot.copy(catalog = snapshot.catalog.filterNot { it.id == item.id } + item)
    }
    fun deleteCatalog(id: String, done: () -> Unit) = change(done) { it.copy(catalog = it.catalog.filterNot { item -> item.id == id }) }
    fun saveDocument(document: BillingDocument, done: () -> Unit) = change(done) { DocumentRules.saveDraft(it, document) }
    fun convertQuote(id: String, done: () -> Unit) = change(done) { snapshot ->
        DocumentRules.saveDraft(snapshot, DocumentRules.convertQuote(snapshot, snapshot.documents.first { it.id == id }))
    }
    fun createCredit(id: String, done: () -> Unit) = change(done) { snapshot ->
        DocumentRules.saveDraft(snapshot, DocumentRules.creditNote(snapshot, snapshot.documents.first { it.id == id }))
    }
    fun addPayment(id: String, payment: DocumentPayment, done: () -> Unit) = change(done) { DocumentRules.payment(it, id, payment) }
    fun trash(id: String, restore: Boolean = false, done: () -> Unit) = change(done) { snapshot ->
        snapshot.copy(documents = snapshot.documents.map { if (it.id == id) it.copy(deletedAt = if (restore) null else now(), events = (it.events ?: emptyList()) + DocumentEvent(title = if (restore) "Document restauré" else "Document mis à la corbeille")) else it })
    }
    fun deleteDraft(id: String, done: () -> Unit) = change(done) { snapshot ->
        require(snapshot.documents.first { it.id == id }.status == DocumentStatus.DRAFT) { "Les documents émis sont conservés dans la corbeille pour préserver la numérotation." }
        snapshot.copy(documents = snapshot.documents.filterNot { it.id == id })
    }

    fun pdf(id: String, preview: Boolean = false, ready: (ByteArray) -> Unit) {
        var bytes: ByteArray? = null
        perform(onSuccess = { bytes?.let(ready) }) { current ->
            val snapshot = requireNotNull(current.snapshot)
            val document = snapshot.documents.first { it.id == id }
            if (document.status != DocumentStatus.DRAFT) {
                val archive = document.archivedPDFData ?: error("Ce document importé ne possède pas de PDF archivé. Réexportez-le depuis l'appareil d'origine ; CashDraft ne recrée pas un document émis.")
                bytes = Base64.getDecoder().decode(archive)
                current
            } else if (preview) {
                bytes = PdfRenderer.render(snapshot, document, true)
                current
            } else {
                val problems = DocumentRules.validation(snapshot, document)
                require(problems.isEmpty()) { problems.joinToString("\n") }
                bytes = PdfRenderer.render(snapshot, document, false)
                val (issued, license) = DocumentRules.issue(snapshot, current.license, id, requireNotNull(bytes))
                database.save(issued, license)
                current.copy(snapshot = issued, license = license)
            }
        }
    }

    fun exportBackup(uri: Uri) = perform { current ->
        val bytes = BackupCodec.encode(requireNotNull(current.snapshot)).toByteArray(Charsets.UTF_8)
        getApplication<Application>().contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } ?: error("Impossible d'écrire le fichier.")
        current.copy(notice = "Sauvegarde exportée.")
    }

    fun previewBackup(uri: Uri) = perform { current ->
        val text = getApplication<Application>().contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(8192)
            val output = ByteArrayOutputStream()
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= 50_000_000) { "Sauvegarde trop volumineuse (50 Mo maximum)." }
                output.write(buffer, 0, count)
            }
            output.toString("UTF-8")
        } ?: error("Impossible de lire le fichier.")
        current.copy(importPreview = BackupCodec.decode(text))
    }

    fun restorePrevious() = perform { it.copy(importPreview = database.previousImport()) }
    fun confirmImport() = perform { current ->
        val imported = requireNotNull(current.importPreview)
        database.save(imported, current.license, importing = true)
        current.copy(snapshot = imported, importPreview = null, notice = "Sauvegarde restaurée. Les droits d'émission sont inchangés.")
    }
    fun dismissImport() { mutableState.value = mutableState.value.copy(importPreview = null) }
    fun dismissError() { mutableState.value = mutableState.value.copy(error = null, notice = null) }

    override fun onCleared() { database.close() }
}