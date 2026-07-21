import Foundation
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case checking
        case unconfigured
        case signedOut
        case signedIn(AuthSession)
#if DEBUG
        case demo
#endif
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var syncMessage = ""
    @Published var errorMessage: String?

    private let client: RocioBackendClient?
    private let sessionPersistence: SessionPersistence
    private let refreshSession: (AuthSession) async throws -> AuthSession
    private var hasBootstrapped = false
    private var isEndingSession = false
    private var isPreparingGardenSync = false
    private var gardenSyncTask: Task<Void, Never>?
    private var gardenSyncTaskGeneration = GardenSyncTaskGeneration()

    init(configuration: BackendConfiguration? = .bundled) {
        let client = configuration.map { RocioBackendClient(configuration: $0) }
        self.client = client
        sessionPersistence = .keychain
        refreshSession = { session in
            guard let client else { throw BackendError.unavailable }
            return try await client.refresh(session)
        }
    }

    init(
        configuration: BackendConfiguration?,
        sessionPersistence: SessionPersistence,
        refreshSession: @escaping (AuthSession) async throws -> AuthSession
    ) {
        client = configuration.map { RocioBackendClient(configuration: $0) }
        self.sessionPersistence = sessionPersistence
        self.refreshSession = refreshSession
    }

    var session: AuthSession? {
        guard case let .signedIn(session) = state else { return nil }
        return session
    }

    var isDemoMode: Bool {
#if DEBUG
        state == .demo
#else
        false
#endif
    }

    func bootstrap(gardenStore: GardenStore) async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        guard client != nil else {
            state = .unconfigured
            return
        }
        guard let saved = sessionPersistence.load() else {
            state = .signedOut
            return
        }
        do {
            let active = try await activeSession(from: saved)
            state = .signedIn(active)
            await syncGarden(gardenStore)
        } catch {
            if error.invalidatesSavedSession {
                sessionPersistence.clear()
                gardenStore.clearLocalCache()
                state = .signedOut
            } else {
                state = .signedIn(saved)
                syncMessage = L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
            }
        }
    }

    func signIn(email: String, password: String, gardenStore: GardenStore) async {
        await authenticate(gardenStore: gardenStore) { client in
            try await client.signIn(email: email, password: password)
        }
    }

    func signUp(email: String, password: String, gardenStore: GardenStore) async {
        let locale = Locale.current.language.languageCode?.identifier == "es" ? "es" : "en"
        await authenticate(gardenStore: gardenStore) { client in
            try await client.signUp(email: email, password: password, locale: locale)
        }
    }

    func signOut(gardenStore: GardenStore) async {
        guard !isEndingSession else { return }
        isEndingSession = true
        let sessionToSignOut = session
        let cancelledSyncTask = cancelGardenSyncTask()
        sessionPersistence.clear()
        UserDefaults.standard.removeObject(forKey: "rocio.cloud.photoConsent")
        gardenStore.clearLocalCache()
        state = client == nil ? .unconfigured : .signedOut
        await cancelledSyncTask?.value
        if let client, let sessionToSignOut { await client.signOut(session: sessionToSignOut) }
        isEndingSession = false
    }

    func deleteAccount(gardenStore: GardenStore) async {
        guard !isEndingSession, let client, let session else { return }
        isEndingSession = true
        let cancelledSyncTask = cancelGardenSyncTask()
        await cancelledSyncTask?.value
        do {
            try await client.deleteAccount(session: try await activeSession(from: session))
            savePendingChanges([], userID: session.user.id)
            clearGardenEpochs(userID: session.user.id)
            gardenStore.clearLocalCache()
            sessionPersistence.clear()
            UserDefaults.standard.removeObject(forKey: "rocio.cloud.photoConsent")
            state = .signedOut
            isEndingSession = false
        } catch {
            isEndingSession = false
            errorMessage = userMessage(for: error)
            startPendingFlush()
        }
    }

    func setAnalyticsEnabled(_ enabled: Bool) async {
        guard let client, let session else { return }
        do {
            try await client.setAnalyticsEnabled(enabled, session: try await activeSession(from: session))
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

#if DEBUG
    func enterDemo(gardenStore: GardenStore) {
        cancelGardenSyncTask()
        errorMessage = nil
        syncMessage = L10n.text("demo.local.only", fallback: "Demo - local only")
        gardenStore.beginDemo()
        state = .demo
    }

    func exitDemo(gardenStore: GardenStore) {
        gardenStore.endDemo()
        syncMessage = ""
        state = client == nil ? .unconfigured : .signedOut
    }
#endif

    func enqueueGardenChange(_ change: GardenChange) {
        guard let session else { return }
        var pending = loadPendingChanges(userID: session.user.id)
        pending.append(PendingCloudChange(change))
        savePendingChanges(pending, userID: session.user.id)
        startPendingFlush()
    }

    func identify(image: UIImage) async throws -> RemoteIdentificationResponse {
        guard let client, let session else { throw BackendError.unavailable }
        let active = try await activeSession(from: session)
        let response = try await client.identify(image: image, session: active)
        if analyticsEnabled {
            await client.track(name: "flower_scan_completed", properties: ["provider": response.provider], session: active)
        }
        return response
    }

    private func authenticate(
        gardenStore: GardenStore,
        action: (RocioBackendClient) async throws -> AuthSession
    ) async {
        guard let client else {
            state = .unconfigured
            return
        }
        errorMessage = nil
        do {
            let session = try await action(client)
            try sessionPersistence.save(session)
            state = .signedIn(session)
            if analyticsEnabled {
                await client.track(name: "account_session_started", properties: [:], session: session)
            }
            await syncGarden(gardenStore)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func syncGarden(_ gardenStore: GardenStore) async {
        guard let client, let session else { return }
        isPreparingGardenSync = true
        defer {
            isPreparingGardenSync = false
            if !loadPendingChanges(userID: session.user.id).isEmpty {
                startPendingFlush()
            }
        }
        syncMessage = L10n.text("cloud.syncing", fallback: "Syncing")
        do {
            let authoritativeEpochBeforeSync = loadAuthoritativeGardenEpoch(userID: session.user.id)
            let provisionalEpochBeforeSync = loadProvisionalGardenEpoch(userID: session.user.id)
            var initialMutationEpoch: UUID?
            if authoritativeEpochBeforeSync == nil,
               provisionalEpochBeforeSync == nil,
               !loadPendingChanges(userID: session.user.id).isEmpty {
                let initialState = try await client.fetchGardenSyncState(session: session)
                // Legacy pending changes are safe to adopt only when this
                // account has never been reset. Otherwise an unmatched epoch
                // deliberately makes the server tombstone them.
                if initialState.gardenResetAt == nil {
                    initialMutationEpoch = initialState.gardenEpoch
                }
            }

            guard await flushPendingChanges(
                client: client,
                session: session,
                initialEpoch: initialMutationEpoch
            ) else {
                syncMessage = L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
                return
            }
            let provisionalEpochAfterFlush = loadProvisionalGardenEpoch(userID: session.user.id)
            let syncState = try await client.fetchGardenSyncState(session: session)
            let localBaseline = gardenStore.plants
            let remote = try await client.fetchGarden(session: session)
            let mayUploadLocalBaseline =
                authoritativeEpochBeforeSync == syncState.gardenEpoch ||
                provisionalEpochAfterFlush == syncState.gardenEpoch ||
                (
                    authoritativeEpochBeforeSync == nil &&
                    provisionalEpochAfterFlush == nil &&
                    syncState.gardenResetAt == nil
                )

            let authoritativeRemote: [CloudGardenRecord]
            if mayUploadLocalBaseline {
                let merged = GardenSyncResolver.resolve(local: localBaseline, remote: remote)
                try await client.upsertGarden(
                    merged,
                    gardenEpoch: syncState.gardenEpoch,
                    session: session
                )
                // Successful no-ops and server-created tombstones must be read
                // back before the epoch is considered authoritative locally.
                authoritativeRemote = try await client.fetchGarden(session: session)
            } else {
                // The server reset in a different epoch. Do not relabel stale
                // local rows with the new epoch; the cloud snapshot wins.
                authoritativeRemote = remote
            }
            let finalSyncState = try await client.fetchGardenSyncState(session: session)
            guard finalSyncState.gardenEpoch == syncState.gardenEpoch else {
                // A reset raced this multi-request snapshot. Keep the older
                // local cursor so all writes fail closed until the next sync.
                throw BackendError.invalidResponse
            }
            let reconciled = GardenSyncResolver.reconcileAuthoritative(
                baseline: localBaseline,
                current: gardenStore.plants,
                remote: authoritativeRemote
            )
            gardenStore.replaceFromCloud(reconciled)
            saveAuthoritativeGardenEpoch(syncState.gardenEpoch, userID: session.user.id)
            clearProvisionalGardenEpoch(userID: session.user.id)
            syncMessage = L10n.text("cloud.synced", fallback: "Synced")
        } catch {
            syncMessage = L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
        }
    }

    private func activeSession(from session: AuthSession) async throws -> AuthSession {
        guard session.needsRefresh else { return session }
        let refreshed = try await refreshSession(session)
        try Task.checkCancellation()
        try sessionPersistence.save(refreshed)
        state = .signedIn(refreshed)
        return refreshed
    }

    private var analyticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "rocio.analytics.enabled") as? Bool ?? true
    }

    private func userMessage(for error: Error) -> String {
        if let backendError = error as? BackendError {
            return backendError.errorDescription ?? L10n.text("error.cloud.generic", fallback: "Rocio Cloud is temporarily unavailable. Try again.")
        }
        if error is URLError {
            return L10n.text("error.network", fallback: "Check your internet connection and try again.")
        }
        return L10n.text("error.generic", fallback: "Something went wrong. Try again.")
    }

    private func startPendingFlush() {
        guard !isEndingSession, !isPreparingGardenSync, gardenSyncTask == nil else { return }
        let generation = gardenSyncTaskGeneration.begin()
        gardenSyncTask = Task { [weak self] in
            guard let self else { return }
            var completed = false
            defer { self.finishPendingFlush(generation: generation, completed: completed) }
            guard let client = self.client, let session = self.session else { return }
            completed = await self.flushPendingChanges(client: client, session: session)
        }
    }

    @discardableResult
    private func cancelGardenSyncTask() -> Task<Void, Never>? {
        let task = gardenSyncTask
        gardenSyncTaskGeneration.cancel()
        task?.cancel()
        gardenSyncTask = nil
        return task
    }

    private func finishPendingFlush(generation: UUID, completed: Bool) {
        guard gardenSyncTaskGeneration.finish(generation) else { return }
        gardenSyncTask = nil
        syncMessage = completed
            ? L10n.text("cloud.synced", fallback: "Synced")
            : L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
        guard
            completed,
            let userID = session?.user.id,
            !loadPendingChanges(userID: userID).isEmpty
        else { return }
        startPendingFlush()
    }

    private func flushPendingChanges(
        client: RocioBackendClient,
        session: AuthSession,
        initialEpoch: UUID? = nil
    ) async -> Bool {
        var activeEpoch = initialEpoch ?? loadMutationGardenEpoch(userID: session.user.id) ?? UUID()
        while !Task.isCancelled {
            guard let next = loadPendingChanges(userID: session.user.id).first else { return true }
            do {
                let active = try await activeSession(from: self.session ?? session)
                switch next.kind {
                case .upsert:
                    guard let plant = next.plant else { throw BackendError.invalidResponse }
                    try await client.upsertGarden(
                        [plant],
                        gardenEpoch: activeEpoch,
                        session: active
                    )
                case .delete:
                    guard let id = next.plantID else { throw BackendError.invalidResponse }
                    try await client.deletePlant(
                        id: id,
                        deletedAt: next.occurredAt ?? Date(),
                        session: active
                    )
                case .reset:
                    activeEpoch = try await client.resetGarden(requestID: next.id, session: active)
                    // This provisional epoch is safe for later mutations
                    // because a locally initiated reset already cleared the
                    // local garden. It is not used to bless a stale baseline.
                    saveProvisionalGardenEpoch(activeEpoch, userID: session.user.id)
                }
                guard !Task.isCancelled else { return false }
                var latest = loadPendingChanges(userID: session.user.id)
                latest.removeAll { $0.id == next.id }
                savePendingChanges(latest, userID: session.user.id)
            } catch {
                return false
            }
        }
        return false
    }

    private func loadPendingChanges(userID: UUID) -> [PendingCloudChange] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey(userID)) else { return [] }
        return (try? JSONDecoder().decode([PendingCloudChange].self, from: data)) ?? []
    }

    private func savePendingChanges(_ changes: [PendingCloudChange], userID: UUID) {
        let key = pendingKey(userID)
        guard !changes.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(changes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func pendingKey(_ userID: UUID) -> String {
        "rocio.cloud.pending.\(userID.uuidString.lowercased())"
    }

    private func loadMutationGardenEpoch(userID: UUID) -> UUID? {
        loadProvisionalGardenEpoch(userID: userID) ?? loadAuthoritativeGardenEpoch(userID: userID)
    }

    private func loadAuthoritativeGardenEpoch(userID: UUID) -> UUID? {
        loadGardenEpoch(forKey: authoritativeGardenEpochKey(userID))
    }

    private func loadProvisionalGardenEpoch(userID: UUID) -> UUID? {
        loadGardenEpoch(forKey: provisionalGardenEpochKey(userID))
    }

    private func loadGardenEpoch(forKey key: String) -> UUID? {
        UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    private func saveAuthoritativeGardenEpoch(_ epoch: UUID, userID: UUID) {
        UserDefaults.standard.set(epoch.uuidString.lowercased(), forKey: authoritativeGardenEpochKey(userID))
    }

    private func saveProvisionalGardenEpoch(_ epoch: UUID, userID: UUID) {
        UserDefaults.standard.set(epoch.uuidString.lowercased(), forKey: provisionalGardenEpochKey(userID))
    }

    private func clearProvisionalGardenEpoch(userID: UUID) {
        UserDefaults.standard.removeObject(forKey: provisionalGardenEpochKey(userID))
    }

    private func clearGardenEpochs(userID: UUID) {
        UserDefaults.standard.removeObject(forKey: authoritativeGardenEpochKey(userID))
        clearProvisionalGardenEpoch(userID: userID)
    }

    private func authoritativeGardenEpochKey(_ userID: UUID) -> String {
        "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
    }

    private func provisionalGardenEpochKey(_ userID: UUID) -> String {
        "rocio.cloud.garden-epoch.provisional.\(userID.uuidString.lowercased())"
    }
}

@MainActor
struct SessionPersistence {
    let load: () -> AuthSession?
    let save: (AuthSession) throws -> Void
    let clear: () -> Void

    static let keychain = SessionPersistence(
        load: KeychainSessionStore.load,
        save: KeychainSessionStore.save,
        clear: KeychainSessionStore.clear
    )
}

private extension Error {
    var invalidatesSavedSession: Bool {
        guard let backendError = self as? BackendError,
              case let .server(code, _) = backendError else { return false }
        // Only explicit refresh/session revocation codes may erase local account data.
        return [
            "invalid_grant",
            "invalid_refresh_token",
            "invalid_session",
            "refresh_token_already_used",
            "refresh_token_not_found",
            "session_expired",
            "session_not_found",
            "user_banned",
        ].contains(code)
    }
}

struct GardenSyncTaskGeneration {
    private(set) var current: UUID?

    mutating func begin() -> UUID {
        let generation = UUID()
        current = generation
        return generation
    }

    mutating func cancel() {
        current = nil
    }

    mutating func finish(_ generation: UUID) -> Bool {
        guard current == generation else { return false }
        current = nil
        return true
    }
}

struct PendingCloudChange: Codable {
    enum Kind: String, Codable { case upsert, delete, reset }
    let id: UUID
    let kind: Kind
    let plant: GardenPlant?
    let plantID: UUID?
    let occurredAt: Date?

    init(_ change: GardenChange) {
        id = UUID()
        switch change {
        case let .upsert(plant):
            kind = .upsert
            self.plant = plant
            plantID = nil
            occurredAt = nil
        case let .delete(id, at: date):
            kind = .delete
            plant = nil
            plantID = id
            occurredAt = date
        case let .reset(at: date):
            kind = .reset
            plant = nil
            plantID = nil
            occurredAt = date
        }
    }
}

struct GardenSyncResolver {
    static func resolve(local: [GardenPlant], remote: [CloudGardenRecord]) -> [GardenPlant] {
        let remoteByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        var activeByID = Dictionary(
            uniqueKeysWithValues: remote.compactMap { record in
                record.deletedAt == nil ? (record.id, record.gardenPlant) : nil
            }
        )

        for plant in local {
            if let remoteRecord = remoteByID[plant.id] {
                // A tombstone is irreversible for this UUID. A user who wants
                // the plant again creates a new garden entry with a new UUID.
                guard remoteRecord.deletedAt == nil else {
                    activeByID.removeValue(forKey: plant.id)
                    continue
                }

                if plant.updatedAt >= remoteRecord.updatedAt {
                    activeByID[plant.id] = plant
                }
            } else {
                activeByID[plant.id] = plant
            }
        }

        return sorted(activeByID.values)
    }

    static func reconcileAuthoritative(
        baseline: [GardenPlant],
        current: [GardenPlant],
        remote: [CloudGardenRecord]
    ) -> [GardenPlant] {
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let tombstonedIDs = Set(remote.compactMap { $0.deletedAt == nil ? nil : $0.id })
        var activeByID = Dictionary(
            uniqueKeysWithValues: remote.compactMap { record in
                record.deletedAt == nil ? (record.id, record.gardenPlant) : nil
            }
        )

        // Preserve only mutations that happened while the network sync was in
        // flight. Unchanged baseline rows absent from the authoritative fetch
        // were rejected by the server and must disappear locally.
        let deletedDuringSync = Set(baselineByID.keys).subtracting(currentByID.keys)
        for id in deletedDuringSync {
            activeByID.removeValue(forKey: id)
        }

        for plant in current {
            let changedDuringSync = baselineByID[plant.id].map { $0 != plant } ?? true
            guard changedDuringSync, !tombstonedIDs.contains(plant.id) else { continue }

            if let remotePlant = activeByID[plant.id], remotePlant.updatedAt > plant.updatedAt {
                continue
            }
            activeByID[plant.id] = plant
        }

        return sorted(activeByID.values)
    }

    private static func sorted<S: Sequence>(_ plants: S) -> [GardenPlant] where S.Element == GardenPlant {
        plants.sorted {
            if $0.addedAt != $1.addedAt { return $0.addedAt < $1.addedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
