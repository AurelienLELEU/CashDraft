package fr.btbu.cashdraft.core

import java.time.Instant
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

object BackupCodec {
    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = true }

    fun decode(text: String): Snapshot {
        require(text.toByteArray(Charsets.UTF_8).size <= 50_000_000) { "Sauvegarde trop volumineuse (50 Mo maximum)." }
        val original = json.parseToJsonElement(text).jsonObject
        require(original["appName"]?.jsonPrimitive?.content == "CashDraft") { "Ce fichier n'est pas une sauvegarde CashDraft." }
        require(original["version"]?.jsonPrimitive?.content == "1.0") { "Version de sauvegarde non prise en charge." }
        require(listOf("profile", "clients", "catalog", "documents").all(original::containsKey)) { "Sauvegarde incomplète." }
        val snapshot = json.decodeFromString<Snapshot>(text).copy(original = original)
        require(snapshot.clients.map { it.id }.distinct().size == snapshot.clients.size) { "Identifiants clients dupliqués." }
        require(snapshot.documents.map { it.id }.distinct().size == snapshot.documents.size) { "Identifiants documents dupliqués." }
        snapshot.documents.forEach { document ->
            Instant.parse(document.issueDate)
            Instant.parse(document.dueDate)
            require(document.items.all { it.quantity.isFinite() && it.unitPriceHT.isFinite() && it.vatRate.isFinite() && (it.discountPercent ?: 0.0).isFinite() }) { "Montants invalides." }
            require(listOf(document.globalDiscountPercent, document.globalDiscountAmount, document.depositAmount, document.retentionAmount, document.alreadyPaidAmount).all { it == null || it.isFinite() }) { "Montants invalides." }
        }
        return snapshot
    }

    fun encode(snapshot: Snapshot): String {
        val updated = json.parseToJsonElement(json.encodeToString(snapshot.copy(exportDate = now()))).jsonObject
        return json.encodeToString(merge(snapshot.original, updated))
    }

    private fun merge(original: JsonElement?, updated: JsonElement): JsonElement = when {
        original is JsonObject && updated is JsonObject -> JsonObject(original + updated.mapValues { (key, value) -> merge(original[key], value) })
        original is JsonArray && updated is JsonArray -> {
            val previous = original.filterIsInstance<JsonObject>().associateBy { it["id"] }
            JsonArray(updated.map { value -> if (value is JsonObject && value.containsKey("id")) merge(previous[value["id"]], value) else value })
        }
        else -> updated
    }
}