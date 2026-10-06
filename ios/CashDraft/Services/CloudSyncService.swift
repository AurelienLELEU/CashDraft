import CloudKit
import Foundation

struct CloudSnapshot: Codable {
    var version = 1
    var modifiedAt = Date()
    var profile: CompanyProfile
    var clients: [Client]
    var catalog: [CatalogItem]
    var documents: [BillingDocument]
    var templates: [DocumentTemplate]? = nil
    var license: AppLicense
}

enum CloudSyncError: LocalizedError {
    case incompatible

    var errorDescription: String? { "La sauvegarde iCloud CashDraft est incompatible." }
}

/// A single private CloudKit record. It belongs to the user's Apple Account and
/// does not require a CashDraft server or an account managed by BTBU.
final class CloudSyncService {
    static let containerIdentifier = "iCloud.com.cashdraft.app"
    private let database = CKContainer(identifier: CloudSyncService.containerIdentifier).privateCloudDatabase
    private let recordID = CKRecord.ID(recordName: "cashdraft-state-v1")

    func fetch() async throws -> CloudSnapshot? {
        do {
            let record = try await database.record(for: recordID)
            let data: Data
            if let asset = record["payloadAsset"] as? CKAsset, let url = asset.fileURL {
                data = try Data(contentsOf: url)
            } else if let legacyData = record["payload"] as? Data {
                // Keeps the first CloudKit snapshots made before attachment support readable.
                data = legacyData
            } else {
                throw CloudSyncError.incompatible
            }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CloudSnapshot.self, from: data)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func upload(_ snapshot: CloudSnapshot) async throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let payloadURL = FileManager.default.temporaryDirectory.appendingPathComponent("cashdraft-cloud-\(UUID().uuidString).json")
        try encoder.encode(snapshot).write(to: payloadURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: payloadURL) }
        let record = CKRecord(recordType: "CashDraftState", recordID: recordID)
        // CKAsset avoids CloudKit's much smaller inline Data-field limit when a
        // customer backs up PDF archives or local document attachments.
        record["payloadAsset"] = CKAsset(fileURL: payloadURL)
        record["modifiedAt"] = snapshot.modifiedAt as CKRecordValue
        _ = try await database.save(record)
    }
}
