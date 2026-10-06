package fr.btbu.cashdraft

import android.content.ClipData
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { CashDraftApp(onShare = ::sharePdf) }
    }

    private fun sharePdf(bytes: ByteArray, number: String) {
        val directory = File(cacheDir, "pdf").apply { mkdirs() }
        directory.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 24 * 60 * 60 * 1000 }?.forEach { it.delete() }
        val safeName = number.replace(Regex("[^A-Za-z0-9_-]"), "_").take(100).ifBlank { "CashDraft" }
        val file = File(directory, "$safeName.pdf").apply { writeBytes(bytes) }
        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("Document CashDraft", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "Partager le PDF"))
    }
}