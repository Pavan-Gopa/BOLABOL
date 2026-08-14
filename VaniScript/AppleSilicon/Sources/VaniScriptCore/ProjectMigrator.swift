import Foundation

public enum ProjectMigrationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidSchemaVersion
}

public enum ProjectMigrator {
    public static let currentSchemaVersion = 4

    public static func validateSchemaVersion(_ version: Int) throws {
        guard (1...currentSchemaVersion).contains(version) else {
            throw ProjectMigrationError.unsupportedSchemaVersion(version)
        }
    }

    public static func resolvedSchemaVersion(_ version: Int?, legacyVersion: Int = 1) throws -> Int {
        let resolved = version ?? legacyVersion
        try validateSchemaVersion(resolved)
        return resolved
    }

    /// Migrates a record decoded from a project archive. The non-throwing form
    /// is useful for the legacy archive reader, where the surrounding format has
    /// already been identified. Bundle readers use the throwing overload below
    /// so an unknown schema can never be silently accepted.
    public static func migrate(
        _ record: ProjectRecord,
        fromSchemaVersion: Int? = nil
    ) -> ProjectRecord {
        var migrated = record
        migrated.session.chunks = migrated.session.chunks.map { chunk in
            var migratedChunk = chunk
            if migratedChunk.sourceAnchor == nil {
                migratedChunk.sourceAnchor = .media(
                    startSec: migratedChunk.startSec,
                    endSec: migratedChunk.endSec
                )
            }
            // ChunkData keeps both fields synchronized through property
            // observers. Reassigning the disposition also repairs records that
            // were produced by early v4 previews with inconsistent booleans.
            let disposition = migratedChunk.reviewDisposition
            migratedChunk.reviewDisposition = disposition
            return migratedChunk
        }
        return migrated
    }

    public static func migrate(
        record: ProjectRecord,
        fromSchemaVersion: Int
    ) throws -> ProjectRecord {
        try validateSchemaVersion(fromSchemaVersion)
        return migrate(record, fromSchemaVersion: Optional(fromSchemaVersion))
    }

    public static func migrate(
        record: ProjectRecord,
        schemaVersion: Int
    ) throws -> ProjectRecord {
        try migrate(record: record, fromSchemaVersion: schemaVersion)
    }
}
