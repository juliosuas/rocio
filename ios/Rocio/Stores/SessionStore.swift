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
    private var hasBootstrapped = false
    private var isEndingSession = false
    private var gardenSyncTask: Task<Void, Never>?
    private var gardenSyncTaskGeneration = GardenSyncTaskGeneration()

    init(configuration: BackendConfiguration? = .bundled) {
        client = configuration.map { RocioBackendClient(configuration: $0) }
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
        guard let saved = KeychainSessionStore.load() else {
            state = .signedOut
            return
        }
        do {
            let active = try await activeSession(from: saved)
            state = .signedIn(active)
            await syncGarden(gardenStore)
        } catch {
            KeychainSessionStore.clear()
            gardenStore.clearLocalCache()
            state = .signedOut
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
        KeychainSessionStore.clear()
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
            gardenStore.clearLocalCache()
            KeychainSessionStore.clear()
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
            try KeychainSessionStore.save(session)
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
        syncMessage = L10n.text("cloud.syncing", fallback: "Syncing")
        do {
            guard await flushPendingChanges(client: client, session: session) else {
                syncMessage = L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
                return
            }
            let remote = try await client.fetchGarden(session: session)
            let merged = merge(local: gardenStore.plants, remote: remote)
            try await client.upsertGarden(merged, session: session)
            gardenStore.replaceFromCloud(merged)
            syncMessage = L10n.text("cloud.synced", fallback: "Synced")
        } catch {
            syncMessage = L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
        }
    }

    private func activeSession(from session: AuthSession) async throws -> AuthSession {
        guard session.needsRefresh else { return session }
        guard let client else { throw BackendError.unavailable }
        let refreshed = try await client.refresh(session)
        try Task.checkCancellation()
        try KeychainSessionStore.save(refreshed)
        state = .signedIn(refreshed)
        return refreshed
    }

    private func merge(local: [GardenPlant], remote: [GardenPlant]) -> [GardenPlant] {
        var merged = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        for plant in local where plant.updatedAt >= (merged[plant.id]?.updatedAt ?? .distantPast) {
            merged[plant.id] = plant
        }
        return merged.values.sorted { $0.addedAt < $1.addedAt }
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
        guard !isEndingSession, gardenSyncTask == nil else { return }
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

    private func flushPendingChanges(client: RocioBackendClient, session: AuthSession) async -> Bool {
        while !Task.isCancelled {
            guard let next = loadPendingChanges(userID: session.user.id).first else { return true }
            do {
                let active = try await activeSession(from: self.session ?? session)
                switch next.kind {
                case .upsert:
                    guard let plant = next.plant else { throw BackendError.invalidResponse }
                    try await client.upsertGarden([plant], session: active)
                case .delete:
                    guard let id = next.plantID else { throw BackendError.invalidResponse }
                    try await client.deletePlant(id: id, session: active)
                case .reset:
                    try await client.deleteGarden(session: active)
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

private struct PendingCloudChange: Codable {
    enum Kind: String, Codable { case upsert, delete, reset }
    let id: UUID
    let kind: Kind
    let plant: GardenPlant?
    let plantID: UUID?

    init(_ change: GardenChange) {
        id = UUID()
        switch change {
        case let .upsert(plant):
            kind = .upsert
            self.plant = plant
            plantID = nil
        case let .delete(id):
            kind = .delete
            plant = nil
            plantID = id
        case .reset:
            kind = .reset
            plant = nil
            plantID = nil
        }
    }
}
