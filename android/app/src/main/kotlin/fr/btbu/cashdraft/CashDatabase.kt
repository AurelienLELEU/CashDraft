package fr.btbu.cashdraft

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import fr.btbu.cashdraft.core.BackupCodec
import fr.btbu.cashdraft.core.License
import fr.btbu.cashdraft.core.Snapshot
import kotlinx.serialization.encodeToString

class CashDatabase(context: Context, name: String = "cashdraft.sqlite") : SQLiteOpenHelper(context, name, null, 1) {
    override fun onCreate(database: SQLiteDatabase) {
        database.execSQL("CREATE TABLE app_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL, license TEXT NOT NULL)")
        database.execSQL("CREATE TABLE before_import (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)")
        database.insertOrThrow("app_state", null, values(Snapshot(), License()))
    }

    override fun onUpgrade(database: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        error("Migration de base de données non disponible : $oldVersion vers $newVersion")
    }

    fun load(): Pair<Snapshot, License> = readableDatabase.rawQuery("SELECT license FROM app_state WHERE id=1", null).use { cursor ->
        check(cursor.moveToFirst()) { "Données locales introuvables. Aucune réinitialisation automatique n'a été effectuée." }
        BackupCodec.decode(readPayload("app_state")) to BackupCodec.json.decodeFromString<License>(cursor.getString(0))
    }

    fun save(snapshot: Snapshot, license: License, importing: Boolean = false) {
        val values = values(snapshot, license)
        val database = writableDatabase
        database.beginTransaction()
        try {
            if (importing) {
                database.execSQL("INSERT OR REPLACE INTO before_import (id, payload) SELECT id, payload FROM app_state WHERE id=1")
            }
            check(database.update("app_state", values, "id=1", null) == 1)
            database.setTransactionSuccessful()
        } finally {
            database.endTransaction()
        }
    }

    fun previousImport(): Snapshot = BackupCodec.decode(readPayload("before_import"))

    private fun readPayload(table: String): String {
        val length = readableDatabase.rawQuery("SELECT length(payload) FROM $table WHERE id=1", null).use { cursor ->
            require(cursor.moveToFirst()) { "Aucune sauvegarde disponible." }
            cursor.getInt(0)
        }
        return buildString {
            var offset = 1
            while (offset <= length) {
                readableDatabase.rawQuery("SELECT substr(payload, ?, 131072) FROM $table WHERE id=1", arrayOf(offset.toString())).use { cursor ->
                    check(cursor.moveToFirst())
                    append(cursor.getString(0))
                }
                offset += 131072
            }
        }
    }

    private fun values(snapshot: Snapshot, license: License) = ContentValues().apply {
        val payload = BackupCodec.encode(snapshot)
        require(payload.toByteArray(Charsets.UTF_8).size <= 50_000_000) { "La base atteint la limite de sauvegarde de cette version (50 Mo). Exportez une sauvegarde avant de poursuivre." }
        put("id", 1)
        put("payload", payload)
        put("license", BackupCodec.json.encodeToString(license))
    }
}