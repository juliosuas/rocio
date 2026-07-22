import Foundation
import UIKit

private struct GardenPreflightAuthorization {
    let userID: UUID
    let lifecycleID: UUID
    let epoch: UUID
}

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
    private var sessionBeingPrepared: AuthSession?
    private var sessionLifecycleGeneration: UInt = 0
    private var sessionLifecycleID = UUID()
    private var sessionEndWaiters: [CheckedContinuation<Void, Never>] = []
    private var gardenHandshakeUserID: UUID?
    private var gardenPreflightAuthorization: GardenPreflightAuthorization?
    private var isPreparingGardenSync = false
    private var gardenSyncNeedsFollowUp = false
    private var gardenSyncTask: Task<Bool, Never>?
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
        refreshSession: @escaping (AuthSession) async throws -> AuthSession,
        urlSession: URLSession = .shared
    ) {
        client = configuration.map { RocioBackendClient(configuration: $0, urlSession: urlSession) }
        self.sessionPersistence = sessionPersistence
        self.refreshSession = refreshSession
    }

    var session: AuthSession? {
        guard case let .signedIn(session) = state else { return nil }
        return session
    }

    private var sessionForOperations: AuthSession? {
        sessionBeingPrepared ?? session
    }

    var isGardenCloudReady: Bool {
        guard let userID = session?.user.id else { return false }
        return gardenHandshakeUserID == userID
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
        let generation = beginSessionPreparation(saved)
        do {
            let active = try await activeSession(from: saved)
            guard isCurrentSessionLifecycle(generation) else { return }
            sessionBeingPrepared = active
            guard let prepared = completeSessionPreparation(generation: generation) else { return }
            state = .signedIn(prepared)
            // Authentication and the local garden are usable immediately.
            // Cloud readiness is established independently so a missing epoch
            // migration or an offline backend cannot trap RootView in a loader.
            await refreshGarden(gardenStore: gardenStore)
        } catch {
            guard isCurrentSessionLifecycle(generation) else { return }
            sessionBeingPrepared = nil
            if error.invalidatesSavedSession {
                invalidateSessionLifecycle()
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
        let sessionToSignOut = sessionForOperations
        invalidateSessionLifecycle()
        let cancelledSyncTask = cancelGardenSyncTask()
        sessionPersistence.clear()
        UserDefaults.standard.removeObject(forKey: "rocio.cloud.photoConsent")
        gardenStore.clearLocalCache()
        state = client == nil ? .unconfigured : .signedOut
        _ = await cancelledSyncTask?.value
        if let client, let sessionToSignOut { await client.signOut(session: sessionToSignOut) }
        finishEndingSession()
    }

    func deleteAccount(gardenStore: GardenStore) async {
        guard !isEndingSession, let client, let session else { return }
        isEndingSession = true
        invalidateSessionLifecycle()
        let cancelledSyncTask = cancelGardenSyncTask()
        _ = await cancelledSyncTask?.value
        do {
            try await client.deleteAccount(session: try await activeSession(from: session))
            savePendingChanges([], userID: session.user.id)
            clearGardenEpochs(userID: session.user.id)
            gardenStore.clearLocalCache()
            sessionPersistence.clear()
            UserDefaults.standard.removeObject(forKey: "rocio.cloud.photoConsent")
            state = .signedOut
            finishEndingSession()
        } catch {
            errorMessage = userMessage(for: error)
            finishEndingSession()
            startGardenSync(gardenStore)
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

    func enqueueGardenChange(_ change: GardenChange, gardenStore: GardenStore) {
        guard let session else { return }
        var pending = loadPendingChanges(userID: session.user.id)
        let queuedChange = PendingCloudChange(
            change,
            gardenEpoch: authorizedGardenEpoch(userID: session.user.id),
            lifecycleID: sessionLifecycleID
        )
        if case .reset = change {
            // A user-initiated reset supersedes every older local mutation.
            // Keeping pre-reset upserts ahead of it would prevent the
            // idempotent reset RPC from recovering after an interrupted reply.
            pending = [queuedChange]
        } else {
            if let affectedPlantID = queuedChange.affectedPlantID {
                // Only the newest local intent for one UUID matters. This also
                // lets a deliberate edit replace an older quarantined intent
                // without disturbing conflicts for other plants.
                pending.removeAll { $0.affectedPlantID == affectedPlantID }
            }
            pending.append(queuedChange)
        }
        savePendingChanges(pending, userID: session.user.id)
        // A retry is safe even before readiness because syncGarden always
        // performs and validates the current lifecycle's epoch preflight
        // before it can reach any mutation request.
        if gardenSyncTask != nil || isPreparingGardenSync {
            gardenSyncNeedsFollowUp = true
        }
        startGardenSync(gardenStore)
    }

    func refreshGarden(gardenStore: GardenStore) async {
        guard session != nil, !isEndingSession else { return }
        _ = await startAndWaitForGardenSync(gardenStore: gardenStore)
    }

    private func startAndWaitForGardenSync(gardenStore: GardenStore) async -> Bool {
        if gardenSyncTask == nil {
            startGardenSync(gardenStore)
        }
        return await waitForGardenSync()
    }

    @discardableResult
    func waitForGardenSync() async -> Bool {
        var didRun = false
        var allCompleted = true
        while let task = gardenSyncTask {
            didRun = true
            allCompleted = await task.value && allCompleted
            guard !Task.isCancelled else { return false }
        }
        return didRun && allCompleted
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
        await waitForSessionEnd()
        guard !Task.isCancelled else { return }
        guard let client else {
            state = .unconfigured
            return
        }
        errorMessage = nil
        let generation = beginAuthenticationAttempt()
        do {
            let session = try await action(client)
            guard isCurrentSessionLifecycle(generation), !isEndingSession else {
                await client.signOut(session: session)
                return
            }
            try sessionPersistence.save(session)
            sessionBeingPrepared = session
            guard isCurrentSessionLifecycle(generation), !isEndingSession else {
                await client.signOut(session: session)
                return
            }
            guard let prepared = completeSessionPreparation(generation: generation) else { return }
            state = .signedIn(prepared)
            if analyticsEnabled {
                await client.track(name: "account_session_started", properties: [:], session: prepared)
            }
            guard isCurrentSessionLifecycle(generation), !isEndingSession else { return }
            // Garden sync failure is recoverable and must not invalidate a
            // successfully authenticated Supabase session.
            await refreshGarden(gardenStore: gardenStore)
        } catch {
            guard isCurrentSessionLifecycle(generation) else { return }
            sessionBeingPrepared = nil
            state = .signedOut
            errorMessage = userMessage(for: error)
        }
    }

    @discardableResult
    private func syncGarden(_ gardenStore: GardenStore) async -> Bool {
        guard let client, let startingSession = sessionForOperations else { return false }
        let expectedUserID = startingSession.user.id
        let expectedLifecycleGeneration = sessionLifecycleGeneration
        let expectedLifecycleID = sessionLifecycleID
        // Capture before any network suspension. Reconciliation can then keep
        // only edits made while this specific sync was in flight.
        let localBaseline = gardenStore.plants
        isPreparingGardenSync = true
        defer {
            isPreparingGardenSync = false
        }
        syncMessage = L10n.text("cloud.syncing", fallback: "Syncing")
        do {
            guard isCurrentSessionLifecycle(expectedLifecycleGeneration) else { throw CancellationError() }
            let session = try await activeSession(from: startingSession)
            guard
                isCurrentSessionLifecycle(expectedLifecycleGeneration),
                session.user.id == expectedUserID
            else { throw CancellationError() }
            let authoritativeEpochBeforeSync = loadAuthoritativeGardenEpoch(userID: expectedUserID)
            let provisionalEpochBeforeSync = loadProvisionalGardenEpoch(userID: expectedUserID)
            var initialMutationEpoch = gardenHandshakeUserID == expectedUserID
                ? loadMutationGardenEpoch(userID: expectedUserID)
                : nil
            var canAdoptUnscopedPending = false
            if gardenHandshakeUserID != expectedUserID {
                let initialState = try await client.fetchGardenSyncState(session: session)
                guard isCurrentSessionLifecycle(expectedLifecycleGeneration) else {
                    throw CancellationError()
                }
                canAdoptUnscopedPending =
                    authoritativeEpochBeforeSync == initialState.gardenEpoch ||
                    provisionalEpochBeforeSync == initialState.gardenEpoch ||
                    (
                        authoritativeEpochBeforeSync == nil &&
                        provisionalEpochBeforeSync == nil &&
                        initialState.gardenResetAt == nil
                    )
                initialMutationEpoch = initialState.gardenEpoch
                gardenPreflightAuthorization = GardenPreflightAuthorization(
                    userID: expectedUserID,
                    lifecycleID: expectedLifecycleID,
                    epoch: initialState.gardenEpoch
                )
            }

            guard let initialMutationEpoch else {
                syncMessage = L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
                return false
            }

            var pendingBeforeFlush = loadPendingChanges(userID: expectedUserID)
            let startsWithIdempotentReset = pendingBeforeFlush.first?.kind == .reset
            let eligibleChangeIDs = Set(pendingBeforeFlush.compactMap { change -> UUID? in
                if startsWithIdempotentReset { return change.id }
                if change.gardenEpoch == initialMutationEpoch { return change.id }
                if change.gardenEpoch == nil, canAdoptUnscopedPending { return change.id }
                return nil
            })
            let quarantinedPending = pendingBeforeFlush.filter {
                !eligibleChangeIDs.contains($0.id)
            }
            var didStampPendingEpoch = false
            for index in pendingBeforeFlush.indices
            where eligibleChangeIDs.contains(pendingBeforeFlush[index].id) &&
                pendingBeforeFlush[index].gardenEpoch != initialMutationEpoch {
                pendingBeforeFlush[index].gardenEpoch = initialMutationEpoch
                didStampPendingEpoch = true
            }
            if didStampPendingEpoch {
                savePendingChanges(pendingBeforeFlush, userID: expectedUserID)
            }

            guard await flushPendingChanges(
                client: client,
                session: session,
                initialEpoch: initialMutationEpoch,
                lifecycleGeneration: expectedLifecycleGeneration,
                eligibleChangeIDs: eligibleChangeIDs
            ) else {
                syncMessage = L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
                return false
            }
            guard isCurrentSessionLifecycle(expectedLifecycleGeneration) else { throw CancellationError() }
            let readSession = try await activeSession(from: self.sessionForOperations ?? session)
            guard
                isCurrentSessionLifecycle(expectedLifecycleGeneration),
                readSession.user.id == expectedUserID
            else { throw CancellationError() }
            let provisionalEpochAfterFlush = loadProvisionalGardenEpoch(userID: expectedUserID)
            let syncState = try await client.fetchGardenSyncState(session: readSession)
            let remote = try await client.fetchGarden(session: readSession)
            let mayUploadLocalBaseline =
                quarantinedPending.isEmpty &&
                (
                    authoritativeEpochBeforeSync == syncState.gardenEpoch ||
                    provisionalEpochAfterFlush == syncState.gardenEpoch ||
                    (
                        authoritativeEpochBeforeSync == nil &&
                        provisionalEpochAfterFlush == nil &&
                        syncState.gardenResetAt == nil
                    )
                )

            let authoritativeRemote: [CloudGardenRecord]
            if mayUploadLocalBaseline {
                let merged = GardenSyncResolver.resolve(local: localBaseline, remote: remote)
                try await client.upsertGarden(
                    merged,
                    gardenEpoch: syncState.gardenEpoch,
                    session: readSession
                )
                // Successful no-ops and server-created tombstones must be read
                // back before the epoch is considered authoritative locally.
                authoritativeRemote = try await client.fetchGarden(session: readSession)
            } else {
                // The server reset in a different epoch. Do not relabel stale
                // local rows with the new epoch; the cloud snapshot wins.
                authoritativeRemote = remote
            }
            let finalSyncState = try await client.fetchGardenSyncState(session: readSession)
            guard finalSyncState.gardenEpoch == syncState.gardenEpoch else {
                // A reset raced this multi-request snapshot. Keep the older
                // local cursor so all writes fail closed until the next sync.
                throw BackendError.invalidResponse
            }
            try Task.checkCancellation()
            guard
                isCurrentSessionLifecycle(expectedLifecycleGeneration),
                self.sessionForOperations?.user.id == expectedUserID
            else { throw CancellationError() }
            var reconciled = GardenSyncResolver.reconcileAuthoritative(
                baseline: localBaseline,
                current: gardenStore.plants,
                remote: authoritativeRemote
            )
            let remainingPendingIDs = Set(loadPendingChanges(userID: expectedUserID).map(\.id))
            let protectedPlantIDs = Set(quarantinedPending.compactMap { change -> UUID? in
                guard remainingPendingIDs.contains(change.id) else { return nil }
                return change.plant?.id
            })
            if !protectedPlantIDs.isEmpty {
                var reconciledByID = Dictionary(uniqueKeysWithValues: reconciled.map { ($0.id, $0) })
                for plant in gardenStore.plants where protectedPlantIDs.contains(plant.id) {
                    reconciledByID[plant.id] = plant
                }
                reconciled = reconciledByID.values.sorted {
                    if $0.addedAt != $1.addedAt { return $0.addedAt < $1.addedAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
            }
            gardenStore.replaceFromCloud(reconciled)
            saveAuthoritativeGardenEpoch(syncState.gardenEpoch, userID: expectedUserID)
            clearProvisionalGardenEpoch(userID: expectedUserID)
            gardenHandshakeUserID = expectedUserID
            let hasRemainingPending = !loadPendingChanges(userID: expectedUserID).isEmpty
            syncMessage = hasRemainingPending
                ? L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
                : L10n.text("cloud.synced", fallback: "Synced")
            return !hasRemainingPending
        } catch {
            if isCurrentSessionLifecycle(expectedLifecycleGeneration) {
                syncMessage = L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
            }
            return false
        }
    }

    private func activeSession(from session: AuthSession) async throws -> AuthSession {
        guard session.needsRefresh else { return session }
        let refreshed = try await refreshSession(session)
        try Task.checkCancellation()
        guard sessionForOperations == session else { throw CancellationError() }
        try sessionPersistence.save(refreshed)
        if sessionBeingPrepared == session {
            sessionBeingPrepared = refreshed
        } else if case let .signedIn(current) = state, current == session {
            state = .signedIn(refreshed)
        } else {
            throw CancellationError()
        }
        return refreshed
    }

    private func beginSessionPreparation(_ session: AuthSession) -> UInt {
        sessionLifecycleGeneration &+= 1
        sessionLifecycleID = UUID()
        gardenHandshakeUserID = nil
        gardenPreflightAuthorization = nil
        sessionBeingPrepared = session
        state = .checking
        return sessionLifecycleGeneration
    }

    private func beginAuthenticationAttempt() -> UInt {
        sessionLifecycleGeneration &+= 1
        sessionLifecycleID = UUID()
        gardenHandshakeUserID = nil
        gardenPreflightAuthorization = nil
        sessionBeingPrepared = nil
        state = .checking
        return sessionLifecycleGeneration
    }

    private func completeSessionPreparation(generation: UInt) -> AuthSession? {
        guard
            isCurrentSessionLifecycle(generation),
            !isEndingSession,
            let prepared = sessionBeingPrepared
        else { return nil }
        sessionBeingPrepared = nil
        return prepared
    }

    private func invalidateSessionLifecycle() {
        sessionLifecycleGeneration &+= 1
        sessionLifecycleID = UUID()
        gardenHandshakeUserID = nil
        gardenPreflightAuthorization = nil
        sessionBeingPrepared = nil
    }

    private func isCurrentSessionLifecycle(_ generation: UInt) -> Bool {
        sessionLifecycleGeneration == generation
    }

    private func authorizedGardenEpoch(userID: UUID) -> UUID? {
        if gardenHandshakeUserID == userID {
            return loadMutationGardenEpoch(userID: userID)
        }
        guard
            let authorization = gardenPreflightAuthorization,
            authorization.userID == userID,
            authorization.lifecycleID == sessionLifecycleID
        else { return nil }
        return authorization.epoch
    }

    private func waitForSessionEnd() async {
        guard isEndingSession else { return }
        await withCheckedContinuation { continuation in
            sessionEndWaiters.append(continuation)
        }
    }

    private func finishEndingSession() {
        isEndingSession = false
        let waiters = sessionEndWaiters
        sessionEndWaiters.removeAll()
        waiters.forEach { $0.resume() }
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

    private func startGardenSync(_ gardenStore: GardenStore) {
        guard !isEndingSession, !isPreparingGardenSync, gardenSyncTask == nil else { return }
        let generation = gardenSyncTaskGeneration.begin()
        gardenSyncTask = Task { [weak self, weak gardenStore] in
            guard let self else { return false }
            var completed = false
            defer {
                self.finishGardenSync(
                    generation: generation,
                    completed: completed,
                    gardenStore: gardenStore
                )
            }
            guard let gardenStore else { return false }
            completed = await self.syncGarden(gardenStore)
            return completed
        }
    }

    @discardableResult
    private func cancelGardenSyncTask() -> Task<Bool, Never>? {
        let task = gardenSyncTask
        gardenSyncTaskGeneration.cancel()
        gardenSyncNeedsFollowUp = false
        task?.cancel()
        gardenSyncTask = nil
        return task
    }

    private func finishGardenSync(
        generation: UUID,
        completed: Bool,
        gardenStore: GardenStore?
    ) {
        guard gardenSyncTaskGeneration.finish(generation) else { return }
        gardenSyncTask = nil
        let needsFollowUp = gardenSyncNeedsFollowUp
        gardenSyncNeedsFollowUp = false
        syncMessage = completed
            ? L10n.text("cloud.synced", fallback: "Synced")
            : L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
        guard
            needsFollowUp,
            let gardenStore,
            let userID = sessionForOperations?.user.id,
            !loadPendingChanges(userID: userID).isEmpty
        else { return }
        startGardenSync(gardenStore)
    }

    private func flushPendingChanges(
        client: RocioBackendClient,
        session: AuthSession,
        initialEpoch: UUID,
        lifecycleGeneration: UInt,
        eligibleChangeIDs: Set<UUID>
    ) async -> Bool {
        var activeEpoch = initialEpoch
        while !Task.isCancelled {
            guard isCurrentSessionLifecycle(lifecycleGeneration) else { return false }
            guard let next = loadPendingChanges(userID: session.user.id).first(where: {
                eligibleChangeIDs.contains($0.id)
            }) else { return true }
            do {
                let active = try await activeSession(from: self.sessionForOperations ?? session)
                guard isCurrentSessionLifecycle(lifecycleGeneration) else { return false }
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
                    let resetEpoch = try await client.resetGarden(requestID: next.id, session: active)
                    guard
                        !Task.isCancelled,
                        isCurrentSessionLifecycle(lifecycleGeneration)
                    else { return false }
                    activeEpoch = resetEpoch
                    // This provisional epoch is safe for later mutations
                    // because a locally initiated reset already cleared the
                    // local garden. It is not used to bless a stale baseline.
                    saveProvisionalGardenEpoch(activeEpoch, userID: session.user.id)
                    var postResetPending = loadPendingChanges(userID: session.user.id)
                    if let resetIndex = postResetPending.firstIndex(where: { $0.id == next.id }) {
                        for index in postResetPending.indices where index > resetIndex {
                            // Reset is an explicit local ordering boundary:
                            // every mutation queued behind it is causally
                            // post-reset, including changes added while the
                            // idempotent RPC was in flight.
                            postResetPending[index].gardenEpoch = activeEpoch
                        }
                    }
                    savePendingChanges(postResetPending, userID: session.user.id)
                    gardenPreflightAuthorization = GardenPreflightAuthorization(
                        userID: session.user.id,
                        lifecycleID: sessionLifecycleID,
                        epoch: activeEpoch
                    )
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
    var gardenEpoch: UUID?
    let lifecycleID: UUID?

    init(
        _ change: GardenChange,
        gardenEpoch: UUID? = nil,
        lifecycleID: UUID? = nil
    ) {
        id = UUID()
        self.gardenEpoch = gardenEpoch
        self.lifecycleID = lifecycleID
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

    var affectedPlantID: UUID? {
        plant?.id ?? plantID
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
