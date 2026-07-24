import Foundation

enum GardenPersistence {
    static let plantsKey = "rocio.ios.garden.plants"
    static let backupPlantsKey = "rocio.ios.garden.plants.backup"
    static let currentSchemaVersion = 3
    private static let archivedPlantsKeyPrefix = "rocio.ios.garden.archived"
    private static let quarantinedLegacyPlantsKey = "rocio.ios.garden.quarantine.legacy"
    private static let quarantinedCorruptPlantsKey = "rocio.ios.garden.quarantine.corrupt"
    private static let pendingRouteKey = "rocio.ios.pendingIntentRoute"
    private static let lock = NSRecursiveLock()

    enum LoadStatus: Equatable {
        case empty
        case loaded
        case migratedLegacy
        case recoveredFromBackup
        case unownedSnapshot
        case ownerMismatch
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
        /// Schema versions 1 and 2 did not record an owner. Version 3 requires
        /// this value; an ownerless legacy snapshot stays quarantined until an
        /// authoritative cloud read replaces it.
        let ownerID: UUID?
        let plants: [GardenPlant]
    }

    private struct SnapshotHeader: Decodable {
        let schemaVersion: Int
    }

    private struct SnapshotOwnerHeader: Decodable {
        let ownerID: UUID?
    }

    private enum DecodedSnapshot {
        case current(Snapshot)
        case legacy([GardenPlant])
        case invalidOwner
        case future(ownerID: UUID?)

        var plants: [GardenPlant] {
            switch self {
            case let .current(snapshot): snapshot.plants
            case let .legacy(plants): plants
            case .invalidOwner, .future: []
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

        var hasInvalidOwner: Bool {
            if case .invalidOwner = self { return true }
            return false
        }

        var isUnowned: Bool {
            switch self {
            case let .current(snapshot):
                snapshot.ownerID == nil
            case .legacy:
                true
            case .invalidOwner, .future:
                false
            }
        }
    }

    static func loadPlants(
        ownerID: UUID,
        defaults: UserDefaults = .standard
    ) -> [GardenPlant] {
        loadSnapshot(ownerID: ownerID, defaults: defaults).plants
    }

    static func loadSnapshot(
        ownerID: UUID,
        defaults: UserDefaults = .standard
    ) -> LoadResult {
        lock.lock()
        defer { lock.unlock() }

        restoreArchivedSnapshotIfAvailable(ownerID: ownerID, defaults: defaults)
        let primaryData = defaults.data(forKey: plantsKey)
        let backupData = defaults.data(forKey: backupPlantsKey)
        guard primaryData != nil || backupData != nil else {
            return LoadResult(plants: [], status: .empty)
        }

        let primary = primaryData.flatMap(decodeSnapshot)
        let backup = backupData.flatMap(decodeSnapshot)

        // Never overwrite a snapshot written by a newer schema with data this
        // build cannot understand, even if the other copy is readable.
        guard primary?.isFuture != true,
              backup?.isFuture != true,
              primary?.hasInvalidOwner != true,
              backup?.hasInvalidOwner != true else {
            return LoadResult(plants: [], status: .unrecoverableCorruption)
        }

        // Never use an owner-bound peer or an archived snapshot to overwrite
        // live data whose owner cannot be proven. An older build may have
        // written that data more recently than either versioned copy.
        if primary?.isUnowned == true || backup?.isUnowned == true {
            return LoadResult(plants: [], status: .unownedSnapshot)
        }

        if let selected = newestCurrentSnapshot(
            primaryData: primaryData,
            primary: primary,
            backupData: backupData,
            backup: backup
        ) {
            if let snapshotOwnerID = selected.snapshot.ownerID {
                guard snapshotOwnerID == ownerID else {
                    return LoadResult(plants: [], status: .ownerMismatch)
                }
            } else {
                return LoadResult(plants: [], status: .unownedSnapshot)
            }

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

        return LoadResult(plants: [], status: .unrecoverableCorruption)
    }

    @discardableResult
    static func savePlants(
        _ plants: [GardenPlant],
        ownerID: UUID,
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
        if allowsCorruptionRecovery {
            guard preserveCurrentSnapshotBeforeReplacement(
                by: ownerID,
                defaults: defaults
            ) else {
                return false
            }
        }
        if !allowsCorruptionRecovery {
            for (data, decoded) in [
                (defaults.data(forKey: plantsKey), decodedPrimary),
                (defaults.data(forKey: backupPlantsKey), decodedBackup),
            ] where data != nil {
                guard case let .current(existingSnapshot)? = decoded,
                      existingSnapshot.ownerID == ownerID else {
                    return false
                }
            }
        }
        let previousGeneration = max(
            decodedPrimary?.generation ?? 0,
            decodedBackup?.generation ?? 0
        )
        let snapshot = Snapshot(
            schemaVersion: currentSchemaVersion,
            generation: previousGeneration == UInt64.max ? UInt64.max : previousGeneration + 1,
            savedAt: Date(),
            ownerID: ownerID,
            plants: plants
        )
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot),
              case let .current(decodedSnapshot)? = decodeSnapshot(data),
              decodedSnapshot.ownerID == ownerID,
              decodedSnapshot.plants == plants else {
            return false
        }

        // Write the backup first. If the process stops before the primary
        // write, loadSnapshot selects this higher generation and repairs both.
        defaults.set(data, forKey: backupPlantsKey)
        guard case let .current(savedBackup)? = defaults
            .data(forKey: backupPlantsKey)
            .flatMap(decodeSnapshot),
            savedBackup.ownerID == ownerID,
            savedBackup.plants == plants else {
            return false
        }
        defaults.set(data, forKey: plantsKey)
        guard case let .current(savedPrimary)? = defaults
            .data(forKey: plantsKey)
            .flatMap(decodeSnapshot),
            savedPrimary.ownerID == ownerID,
            savedPrimary.plants == plants else {
            return false
        }
        return true
    }

    @discardableResult
    static func clearPlants(
        ownerID: UUID,
        defaults: UserDefaults = .standard,
        allowingUnreadableData: Bool = false
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let ownerArchivePrefix = archivedPlantsKeyPrefix(ownerID: ownerID)
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(ownerArchivePrefix) {
            defaults.removeObject(forKey: key)
        }

        var mayClearCurrentSnapshot = true
        for key in [plantsKey, backupPlantsKey] {
            guard let data = defaults.data(forKey: key) else { continue }
            guard let decoded = decodeSnapshot(data) else {
                if !allowingUnreadableData {
                    mayClearCurrentSnapshot = false
                }
                continue
            }
            guard case let .current(snapshot) = decoded,
                  snapshot.ownerID == ownerID else {
                mayClearCurrentSnapshot = false
                continue
            }
        }
        if mayClearCurrentSnapshot {
            defaults.removeObject(forKey: plantsKey)
            defaults.removeObject(forKey: backupPlantsKey)
        }
        guard mayClearCurrentSnapshot else { return false }
        return !defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix(ownerArchivePrefix)
        }
            && defaults.data(forKey: plantsKey) == nil
            && defaults.data(forKey: backupPlantsKey) == nil
    }

    /// Explicit privacy action for one signed-in account. It also removes
    /// unowned, corrupt, and unattributed future-schema data while preserving
    /// every snapshot proven to belong to a different UUID.
    @discardableResult
    static func purgeGardenData(
        ownerID: UUID?,
        defaults: UserDefaults = .standard
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        for key in defaults.dictionaryRepresentation().keys {
            let belongsToOwnerArchive = ownerID.map {
                key.hasPrefix(archivedPlantsKeyPrefix(ownerID: $0))
            } ?? false
            if belongsToOwnerArchive
                || key.hasPrefix(quarantinedLegacyPlantsKey)
                || key.hasPrefix(quarantinedCorruptPlantsKey) {
                defaults.removeObject(forKey: key)
            }
        }

        for key in [plantsKey, backupPlantsKey] {
            guard let data = defaults.data(forKey: key) else { continue }
            switch decodeSnapshot(data) {
            case let .current(snapshot)?:
                if snapshot.ownerID == nil || snapshot.ownerID == ownerID {
                    defaults.removeObject(forKey: key)
                }
            case .legacy?, .invalidOwner?, nil:
                defaults.removeObject(forKey: key)
            case let .future(snapshotOwnerID)?:
                if snapshotOwnerID == nil || snapshotOwnerID == ownerID {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let remainingKeys = defaults.dictionaryRepresentation().keys
        let ownerArchiveRemains = ownerID.map { expectedOwnerID in
            remainingKeys.contains {
                $0.hasPrefix(archivedPlantsKeyPrefix(ownerID: expectedOwnerID))
            }
        } ?? false
        let quarantineRemains = remainingKeys.contains {
            $0.hasPrefix(quarantinedLegacyPlantsKey)
                || $0.hasPrefix(quarantinedCorruptPlantsKey)
        }
        guard !ownerArchiveRemains, !quarantineRemains else { return false }
        for key in [plantsKey, backupPlantsKey] {
            guard let data = defaults.data(forKey: key) else { continue }
            switch decodeSnapshot(data) {
            case let .current(snapshot)?
                where snapshot.ownerID != nil && snapshot.ownerID != ownerID:
                continue
            case let .future(snapshotOwnerID)?
                where snapshotOwnerID != nil && snapshotOwnerID != ownerID:
                continue
            default:
                return false
            }
        }
        return true
    }

#if DEBUG
    /// Test-only cleanup. Product code must use the owner-scoped overload.
    static func clearPlants(defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: plantsKey)
        defaults.removeObject(forKey: backupPlantsKey)
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(archivedPlantsKeyPrefix)
            || key.hasPrefix(quarantinedLegacyPlantsKey)
            || key.hasPrefix(quarantinedCorruptPlantsKey) {
            defaults.removeObject(forKey: key)
        }
    }
#endif

    static func updatePlant(
        id: UUID,
        ownerID: UUID,
        defaults: UserDefaults = .standard,
        mutation: (inout GardenPlant) -> Void
    ) -> PlantMutationResult {
        lock.lock()
        defer { lock.unlock() }

        let loaded = loadSnapshot(ownerID: ownerID, defaults: defaults)
        guard loaded.status != .unrecoverableCorruption,
              loaded.status != .ownerMismatch,
              loaded.status != .unownedSnapshot else {
            return .persistenceFailure
        }
        var plants = loaded.plants
        guard let index = plants.firstIndex(where: { $0.id == id }) else {
            return .notFound
        }
        mutation(&plants[index])
        let updated = plants[index]
        guard savePlants(plants, ownerID: ownerID, defaults: defaults) else {
            return .persistenceFailure
        }
        return .updated(updated)
    }

    /// App Intents run outside SessionStore. Read Keychain and the snapshot
    /// while holding the garden lock so a sign-out/clear cannot expose or
    /// mutate a snapshot after its authenticated owner changes.
    static func loadPlantsForAuthenticatedSession(
        defaults: UserDefaults = .standard,
        sessionLoader: () -> AuthSession? = KeychainSessionStore.load
    ) -> [GardenPlant] {
        lock.lock()
        defer { lock.unlock() }
        guard let ownerID = sessionLoader()?.user.id else { return [] }
        return loadSnapshot(ownerID: ownerID, defaults: defaults).plants
    }

    static func updatePlantForAuthenticatedSession(
        id: UUID,
        defaults: UserDefaults = .standard,
        sessionLoader: () -> AuthSession? = KeychainSessionStore.load,
        mutation: (inout GardenPlant) -> Void
    ) -> PlantMutationResult {
        lock.lock()
        defer { lock.unlock() }
        guard let ownerID = sessionLoader()?.user.id else {
            return .persistenceFailure
        }
        return updatePlant(
            id: id,
            ownerID: ownerID,
            defaults: defaults,
            mutation: mutation
        )
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
            let ownerID = (try? decoder.decode(SnapshotOwnerHeader.self, from: data))?.ownerID
            return .future(ownerID: ownerID)
        }
        if let snapshot = try? decoder.decode(Snapshot.self, from: data),
           (1...currentSchemaVersion).contains(snapshot.schemaVersion) {
            guard snapshot.schemaVersion < 3 || snapshot.ownerID != nil else {
                return .invalidOwner
            }
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

    private static func archivedPlantsKeyPrefix(ownerID: UUID) -> String {
        "\(archivedPlantsKeyPrefix).\(ownerID.uuidString.lowercased())."
    }

    private static func restoreArchivedSnapshotIfAvailable(
        ownerID: UUID,
        defaults: UserDefaults
    ) {
        let primaryData = defaults.data(forKey: plantsKey)
        let backupData = defaults.data(forKey: backupPlantsKey)
        let primary = primaryData.flatMap(decodeSnapshot)
        let backup = backupData.flatMap(decodeSnapshot)
        guard primary?.isFuture != true,
              backup?.isFuture != true,
              primary?.hasInvalidOwner != true,
              backup?.hasInvalidOwner != true,
              primary?.isUnowned != true,
              backup?.isUnowned != true else {
            return
        }
        if let current = newestCurrentSnapshot(
            primaryData: primaryData,
            primary: primary,
            backupData: backupData,
            backup: backup
        ), current.snapshot.ownerID == ownerID {
            return
        }

        let ownerArchivePrefix = archivedPlantsKeyPrefix(ownerID: ownerID)
        let archivedCandidates: [(key: String, data: Data, snapshot: Snapshot)] = defaults
            .dictionaryRepresentation()
            .compactMap { key, value in
                guard key.hasPrefix(ownerArchivePrefix),
                      let data = value as? Data,
                      case let .current(snapshot)? = decodeSnapshot(data),
                      snapshot.ownerID == ownerID else {
                    return nil
                }
                return (key, data, snapshot)
            }
        guard let archived = archivedCandidates.max(by: {
            let leftGeneration = $0.snapshot.generation ?? 0
            let rightGeneration = $1.snapshot.generation ?? 0
            if leftGeneration != rightGeneration {
                return leftGeneration < rightGeneration
            }
            return $0.snapshot.savedAt < $1.snapshot.savedAt
        }) else {
            return
        }
        guard preserveCurrentSnapshotBeforeReplacement(
            by: ownerID,
            defaults: defaults
        ) else {
            return
        }

        defaults.set(archived.data, forKey: backupPlantsKey)
        defaults.set(archived.data, forKey: plantsKey)
        guard case let .current(savedPrimary)? = defaults
            .data(forKey: plantsKey)
            .flatMap(decodeSnapshot),
            savedPrimary.ownerID == ownerID,
            case let .current(savedBackup)? = defaults
            .data(forKey: backupPlantsKey)
            .flatMap(decodeSnapshot),
            savedBackup.ownerID == ownerID else {
            return
        }
        defaults.removeObject(forKey: archived.key)
    }

    private static func preserveCurrentSnapshotBeforeReplacement(
        by ownerID: UUID,
        defaults: UserDefaults
    ) -> Bool {
        let primaryData = defaults.data(forKey: plantsKey)
        let backupData = defaults.data(forKey: backupPlantsKey)
        guard primaryData != nil || backupData != nil else { return true }
        let primary = primaryData.flatMap(decodeSnapshot)
        let backup = backupData.flatMap(decodeSnapshot)
        guard primary?.isFuture != true, backup?.isFuture != true else {
            return false
        }

        var hasUnsafeSnapshot = false
        var newestOwnedSnapshot: [UUID: (data: Data, snapshot: Snapshot)] = [:]
        let slots: [(name: String, data: Data?, decoded: DecodedSnapshot?)] = [
            ("primary", primaryData, primary),
            ("backup", backupData, backup),
        ]

        for slot in slots {
            guard let data = slot.data else { continue }
            switch slot.decoded {
            case let .current(snapshot)?:
                guard let snapshotOwnerID = snapshot.ownerID else {
                    hasUnsafeSnapshot = true
                    guard quarantineRawSnapshot(
                        data,
                        slot: slot.name,
                        keyPrefix: quarantinedLegacyPlantsKey,
                        defaults: defaults
                    ) else {
                        return false
                    }
                    continue
                }
                if let existing = newestOwnedSnapshot[snapshotOwnerID] {
                    let existingGeneration = existing.snapshot.generation ?? 0
                    let candidateGeneration = snapshot.generation ?? 0
                    let candidateIsNewer = candidateGeneration > existingGeneration
                        || (candidateGeneration == existingGeneration
                            && snapshot.savedAt > existing.snapshot.savedAt)
                    if candidateIsNewer {
                        newestOwnedSnapshot[snapshotOwnerID] = (data, snapshot)
                    }
                } else {
                    newestOwnedSnapshot[snapshotOwnerID] = (data, snapshot)
                }
            case .legacy?:
                hasUnsafeSnapshot = true
                guard quarantineRawSnapshot(
                    data,
                    slot: slot.name,
                    keyPrefix: quarantinedLegacyPlantsKey,
                    defaults: defaults
                ) else {
                    return false
                }
            case .invalidOwner?, nil:
                hasUnsafeSnapshot = true
                guard quarantineRawSnapshot(
                    data,
                    slot: slot.name,
                    keyPrefix: quarantinedCorruptPlantsKey,
                    defaults: defaults
                ) else {
                    return false
                }
            case .future?:
                return false
            }
        }

        let hasDifferentOwner = newestOwnedSnapshot.keys.contains { $0 != ownerID }
        guard hasUnsafeSnapshot || hasDifferentOwner else { return true }
        for (snapshotOwnerID, candidate) in newestOwnedSnapshot {
            guard archiveOwnedSnapshot(
                candidate.data,
                snapshot: candidate.snapshot,
                ownerID: snapshotOwnerID,
                defaults: defaults
            ) else {
                return false
            }
        }
        return true
    }

    private static func archiveOwnedSnapshot(
        _ data: Data,
        snapshot: Snapshot,
        ownerID: UUID,
        defaults: UserDefaults
    ) -> Bool {
        guard snapshot.ownerID == ownerID else { return false }
        let key = "\(archivedPlantsKeyPrefix(ownerID: ownerID))\(UUID().uuidString.lowercased())"
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    private static func quarantineRawSnapshot(
        _ data: Data,
        slot: String,
        keyPrefix: String,
        defaults: UserDefaults
    ) -> Bool {
        let key = "\(keyPrefix).\(UUID().uuidString.lowercased()).\(slot)"
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
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
