import Foundation
import SQLite3

enum DatabaseError: LocalizedError { case open, execute(String), decode
    var errorDescription: String? { switch self { case .open: "Impossible d’ouvrir la base locale."; case .execute(let detail): detail; case .decode: "Données locales invalides." } }
}

final class Database {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CashDraft", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard sqlite3_open_v2(directory.appendingPathComponent("cashdraft.sqlite").path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw DatabaseError.open }
        try execute("PRAGMA foreign_keys = ON;")
        try execute("CREATE TABLE IF NOT EXISTS entity_store (kind TEXT NOT NULL, id TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(kind, id));")
        try execute("CREATE TABLE IF NOT EXISTS app_license (id INTEGER PRIMARY KEY CHECK (id = 1), payload BLOB NOT NULL);")
    }

    deinit { sqlite3_close(db) }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "Erreur SQLite inconnue"; sqlite3_free(error); throw DatabaseError.execute(message)
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ string: String) {
        sqlite3_bind_text(statement, index, string, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ data: Data) {
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }

    func save<T: Codable>(_ value: T, kind: String, id: String) throws {
        let sql = "INSERT OR REPLACE INTO entity_store (kind, id, payload) VALUES (?, ?, ?);"
        var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.execute("Préparation SQLite impossible.") }
        bind(statement, 1, kind); bind(statement, 2, id); bind(statement, 3, try encoder.encode(value))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.execute("Enregistrement local impossible.") }
    }

    func fetch<T: Codable>(_ type: T.Type, kind: String) throws -> [T] {
        let sql = "SELECT payload FROM entity_store WHERE kind = ? ORDER BY rowid DESC;"
        var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.execute("Lecture SQLite impossible.") }
        bind(statement, 1, kind)
        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pointer = sqlite3_column_blob(statement, 0) else { continue }
            let length = Int(sqlite3_column_bytes(statement, 0))
            values.append(try decoder.decode(T.self, from: Data(bytes: pointer, count: length)))
        }
        return values
    }

    func delete(kind: String, id: String) throws {
        var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "DELETE FROM entity_store WHERE kind = ? AND id = ?;", -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.execute("Suppression SQLite impossible.") }
        bind(statement, 1, kind); bind(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.execute("Suppression locale impossible.") }
    }

    func saveLicense(_ license: AppLicense) throws {
        var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO app_license (id, payload) VALUES (1, ?);", -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.execute("Licence inaccessible.") }
        bind(statement, 1, try encoder.encode(license)); guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.execute("Licence non enregistrée.") }
    }

    func fetchLicense() throws -> AppLicense? {
        var statement: OpaquePointer?; defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT payload FROM app_license WHERE id = 1;", -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.execute("Licence inaccessible.") }
        guard sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_blob(statement, 0) else { return nil }
        return try decoder.decode(AppLicense.self, from: Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 0))))
    }

    func replaceAll(profile: CompanyProfile, clients: [Client], catalog: [CatalogItem], documents: [BillingDocument], templates: [DocumentTemplate] = []) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute("DELETE FROM entity_store;")
            try save(profile, kind: "profile", id: "1")
            for item in clients { try save(item, kind: "client", id: item.id) }
            for item in catalog { try save(item, kind: "catalog", id: item.id) }
            for item in documents { try save(item, kind: "document", id: item.id) }
            for item in templates { try save(item, kind: "template", id: item.id) }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }
}
