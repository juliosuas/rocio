import Foundation

enum GardenPersistence {
    static let plantsKey = "rocio.ios.garden.plants"
    static let backupPlantsKey = "rocio.ios.garden.plants.backup"
    static let currentSchemaVersion = 2
    private static let pendingRouteKey = "rocio.ios.pendingIntentRoute"
    private static let lock = NSRecursiveLock()

    enum LoadStatus: Equatable {
        case empty
        case loaded
        case migratedLegacy
        case recoveredFromBackup
        case unrecoverableCorruption
    }

    struct LoadResult: Equatable {
        let plants: [GardenPlant]
        let status: LoadStatus
    }

    enum PlantMutationResult: Equatable {
        case updated(GardenPlant)
        case notFound
        case persistenceFailure
    }

    private struct Snapshot: Codable {
        let schemaVersion: Int
        let generation: UInt64?
        let savedAt: Date
        let plants: [GardenPlant]
    }

    private struct SnapshotHeader: Decodable {
        let schemaVersion: Int
    }

    private enum DecodedSnapshot {
        case current(Snapshot)
        case legacy([GardenPlant])
        case future

        var plants: [GardenPlant] {
            switch self {
            case let .current(snapshot): snapshot.plants
            case let .legacy(plants): plants
            case .future: []
            }
        }

        var generation: UInt64 {
            guard case let .current(snapshot) = self else { return 0 }
            return snapshot.generation ?? 0
        }

        var savedAt: Date {
            guard case let .current(snapshot) = self else { return .distantPast }
            return snapshot.savedAt
        }

        var isFuture: Bool {
            if case .future = self { return true }
            return false
        }
    }

    static func loadPlants(defaults: UserDefaults = .standard) -> [GardenPlant] {
        loadSnapshot(defaults: defaults).plants
    }

    static func loadSnapshot(defaults: UserDefaults = .standard) -> LoadResult {
        lock.lock()
        defer { lock.unlock() }

        let primaryData = defaults.data(forKey: plantsKey)
        let backupData = defaults.data(forKey: backupPlantsKey)
        guard primaryData != nil || backupData != nil else {
            return LoadResult(plants: [], status: .empty)
        }

        let primary = primaryData.flatMap(decodeSnapshot)
        let backup = backupData.flatMap(decodeSnapshot)

        // Never overwrite a snapshot written by a newer schema with data this
        // build cannot understand, even if the other copy is readable.
        guard primary?.isFuture != true, backup?.isFuture != true else {
            return LoadResult(plants: [], status: .unrecoverableCorruption)
        }

        // Older builds wrote the live primary as a raw array and did not
        // update this build's versioned backup. A valid legacy primary is
        // therefore newer user intent and must be migrated before considering
        // a stale versioned backup.
        if case let .legacy(plants)? = primary {
            _ = savePlants(plants, defaults: defaults, allowsCorruptionRecovery: true)
            return LoadResult(plants: plants, status: .migratedLegacy)
        }

        if let selected = newestCurrentSnapshot(
            primaryData: primaryData,
            primary: primary,
            backupData: backupData,
            backup: backup
        ) {
            // Repair only the stale/missing slot while holding the same lock
            // used by save and clear. A read must never write an older
            // captured generation over a concurrent save.
            if primaryData != selected.data {
                defaults.set(selected.data, forKey: plantsKey)
            }
            if backupData != selected.data {
                defaults.set(selected.data, forKey: backupPlantsKey)
            }
            return LoadResult(
                plants: selected.snapshot.plants,
                status: selected.isPrimary ? .loaded : .recoveredFromBackup
            )
        }

        if case let .legacy(plants)? = backup {
            _ = savePlants(plants, defaults: defaults, allowsCorruptionRecovery: true)
            return LoadResult(plants: plants, status: .recoveredFromBackup)
        }

        return LoadResult(plants: [], status: .unrecoverableCorruption)
    }

    @discardableResult
    static func savePlants(
        _ plants: [GardenPlant],
        defaults: UserDefaults = .standard,
        allowsCorruptionRecovery: Bool = false
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if !allowsCorruptionRecovery,
           (defaults.data(forKey: plantsKey) != nil || defaults.data(forKey: backupPlantsKey) != nil),
           decodeSnapshot(defaults.data(forKey: plantsKey) ?? Data()) == nil,
           decodeSnapshot(defaults.data(forKey: backupPlantsKey) ?? Data()) == nil {
            return false
        }
        let decodedPrimary = defaults.data(forKey: plantsKey).flatMap(decodeSnapshot)
        let decodedBackup = defaults.data(forKey: backupPlantsKey).flatMap(decodeSnapshot)
        guard decodedPrimary?.isFuture != true, decodedBackup?.isFuture != true else {
            return false
        }
        let previousGeneration = max(
            decodedPrimary?.generation ?? 0,
            decodedBackup?.generation ?? 0
        )
        let snapshot = Snapshot(
            schemaVersion: currentSchemaVersion,
            generation: previousGeneration == UInt64.max ? UInt64.max : previousGeneration + 1,
            savedAt: Date(),
            plants: plants
        )
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot),
              case let .current(decodedSnapshot)? = decodeSnapshot(data),
              decodedSnapshot.plants == plants else {
            return false
        }

        // Write the backup first. If the process stops before the primary
        // write, loadSnapshot selects this higher generation and repairs both.
        defaults.set(data, forKey: backupPlantsKey)
        guard defaults.data(forKey: backupPlantsKey).flatMap(decodeSnapshot)?.plants == plants else {
            return false
        }
        defaults.set(data, forKey: plantsKey)
        guard defaults.data(forKey: plantsKey).flatMap(decodeSnapshot)?.plants == plants else {
            return false
        }
        return true
    }

    static func clearPlants(defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: plantsKey)
        defaults.removeObject(forKey: backupPlantsKey)
    }

    static func updatePlant(
        id: UUID,
        defaults: UserDefaults = .standard,
        mutation: (inout GardenPlant) -> Void
    ) -> PlantMutationResult {
        lock.lock()
        defer { lock.unlock() }

        let loaded = loadSnapshot(defaults: defaults)
        guard loaded.status != .unrecoverableCorruption else {
            return .persistenceFailure
        }
        var plants = loaded.plants
        guard let index = plants.firstIndex(where: { $0.id == id }) else {
            return .notFound
        }
        mutation(&plants[index])
        let updated = plants[index]
        guard savePlants(plants, defaults: defaults) else {
            return .persistenceFailure
        }
        return .updated(updated)
    }

    static func setPendingRoute(_ route: IntentRoute) {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.set(route.rawValue, forKey: pendingRouteKey)
    }

    static func takePendingRoute() -> IntentRoute? {
        lock.lock()
        defer { lock.unlock() }
        guard let raw = UserDefaults.standard.string(forKey: pendingRouteKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingRouteKey)
        return IntentRoute(rawValue: raw)
    }

    private static func decodeSnapshot(_ data: Data) -> DecodedSnapshot? {
        let decoder = JSONDecoder()
        if let header = try? decoder.decode(SnapshotHeader.self, from: data),
           header.schemaVersion > currentSchemaVersion {
            return .future
        }
        if let snapshot = try? decoder.decode(Snapshot.self, from: data),
           (1...currentSchemaVersion).contains(snapshot.schemaVersion) {
            return .current(snapshot)
        }
        if let legacyPlants = try? decoder.decode([GardenPlant].self, from: data) {
            return .legacy(legacyPlants)
        }
        return nil
    }

    private static func newestCurrentSnapshot(
        primaryData: Data?,
        primary: DecodedSnapshot?,
        backupData: Data?,
        backup: DecodedSnapshot?
    ) -> (data: Data, snapshot: Snapshot, isPrimary: Bool)? {
        let primaryCurrent: (Data, Snapshot)? = {
            guard let primaryData, case let .current(snapshot)? = primary else { return nil }
            return (primaryData, snapshot)
        }()
        let backupCurrent: (Data, Snapshot)? = {
            guard let backupData, case let .current(snapshot)? = backup else { return nil }
            return (backupData, snapshot)
        }()

        switch (primaryCurrent, backupCurrent) {
        case let ((data, snapshot)?, (backupData, backupSnapshot)?):
            let primaryGeneration = snapshot.generation ?? 0
            let backupGeneration = backupSnapshot.generation ?? 0
            let backupIsNewer = backupGeneration > primaryGeneration
                || (backupGeneration == primaryGeneration && backupSnapshot.savedAt > snapshot.savedAt)
            return backupIsNewer
                ? (backupData, backupSnapshot, false)
                : (data, snapshot, true)
        case let ((data, snapshot)?, nil):
            return (data, snapshot, true)
        case let (nil, (data, snapshot)?):
            return (data, snapshot, false)
        case (nil, nil):
            return nil
        }
    }
}

enum IntentRoute: String {
    case garden
    case scanner
    case calendar
}

enum IntentHandoffStore {
    static func setPendingRoute(_ route: IntentRoute) {
        GardenPersistence.setPendingRoute(route)
    }

    static func takePendingRoute() -> IntentRoute? {
        GardenPersistence.takePendingRoute()
    }
}

struct GardenExport: Codable, Equatable {
    let exportedAt: Date
    let appVersion: String
    let bundleIdentifier: String
    let plants: [GardenPlant]

    static func payload(
        plants: [GardenPlant],
        exportedAt: Date = Date(),
        appVersion: String = "1.0",
        bundleIdentifier: String = "com.juliosuas.rocio"
    ) -> String {
        let export = GardenExport(
            exportedAt: exportedAt,
            appVersion: appVersion,
            bundleIdentifier: bundleIdentifier,
            plants: plants
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(export),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
