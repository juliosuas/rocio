import Foundation
import UIKit

private struct GardenPreflightAuthorization {
    let userID: UUID
    let lifecycleID: UUID
    let epoch: UUID
}

private struct PasswordRecoveryValidationOperation {
    let id: UUID
    let callback: PasswordRecoveryCallback
    let generation: UInt
    let activeRecoverySession: AuthSession?
    let task: Task<AuthSession, Error>
}

private struct ValidatedPasswordRecovery {
    let id: UUID
    let callback: PasswordRecoveryCallback
    var session: AuthSession
}

enum GardenCloudSyncStatus: Equatable {
    case local
    case syncing
    case synced
    case pending
    case demo

    var message: String {
        switch self {
        case .local:
            L10n.text("garden.sync.local", fallback: "Saved on this device")
        case .syncing:
            L10n.text("cloud.syncing", fallback: "Syncing")
        case .synced:
            L10n.text("cloud.synced", fallback: "Synced")
        case .pending:
            L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
        case .demo:
            L10n.text("demo.local.only", fallback: "Demo - local only")
        }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case checking
        case unconfigured
        case signedOut
        case recoveringPassword(AuthSession)
        case passwordUpdated(AuthSession)
        case passwordUpdatedRequiresSignIn
        case signedIn(AuthSession)
#if DEBUG
        case demo
#endif
    }

    enum PasswordResetRequestState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var gardenSyncStatus: GardenCloudSyncStatus = .local
    @Published private(set) var passwordResetRequestState: PasswordResetRequestState = .idle
    @Published var errorMessage: String?

    var syncMessage: String { gardenSyncStatus.message }

    private let client: RocioBackendClient?
    private weak var activeGardenStore: GardenStore?
    private let sessionPersistence: SessionPersistence
    private let refreshSession: (AuthSession) async throws -> AuthSession
    private let passwordRecoveryActions: PasswordRecoveryActions
    private var hasBootstrapped = false
    private var passwordResetRequestGeneration: UInt = 0
    private var recoveryReturnState: RecoveryReturnState?
    private var passwordRecoveryValidationOperation: PasswordRecoveryValidationOperation?
    private var validatedPasswordRecovery: ValidatedPasswordRecovery?
    private var isPasswordUpdateInProgress = false
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
    private var corruptedPendingOutboxUsers: Set<UUID> = []

    init(configuration: BackendConfiguration? = .bundled) {
        let client = configuration.map { RocioBackendClient(configuration: $0) }
        self.client = client
        sessionPersistence = .keychain
        refreshSession = { session in
            guard let client else { throw BackendError.unavailable }
            return try await client.refresh(session)
        }
        passwordRecoveryActions = .live(client: client)
    }

    init(
        configuration: BackendConfiguration?,
        backendClient: RocioBackendClient? = nil,
        sessionPersistence: SessionPersistence,
        refreshSession: @escaping (AuthSession) async throws -> AuthSession,
        passwordRecoveryActions: PasswordRecoveryActions? = nil,
        urlSession: URLSession = .shared
    ) {
        let client = backendClient
            ?? configuration.map { RocioBackendClient(configuration: $0, urlSession: urlSession) }
        self.client = client
        self.sessionPersistence = sessionPersistence
        self.refreshSession = refreshSession
        self.passwordRecoveryActions = passwordRecoveryActions ?? .live(client: client)
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

    var hasPendingGardenReset: Bool {
        guard let userID = session?.user.id else { return false }
        return hasPendingGardenReset(for: userID)
    }

    var isDemoMode: Bool {
#if DEBUG
        state == .demo
#else
        false
#endif
    }

    func bootstrap(gardenStore: GardenStore) async {
        activeGardenStore = gardenStore
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        guard client != nil else {
            gardenStore.deactivatePersistence()
            state = .unconfigured
            return
        }
        guard let saved = sessionPersistence.load() else {
            gardenStore.deactivatePersistence()
            state = .signedOut
            return
        }
        // Keychain proves the active account, not who wrote an ownerless
        // legacy UserDefaults snapshot. Keep legacy data quarantined.
        gardenStore.activatePersistence(for: saved.user.id)
        let generation = beginSessionPreparation(saved)
        do {
            let active = try await activeSession(from: saved)
            guard isCurrentSessionLifecycle(generation) else { return }
            if active.user.id != saved.user.id {
                gardenStore.activatePersistence(for: active.user.id)
            }
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
                gardenSyncStatus = .pending
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

    func preparePasswordResetRequest() {
        passwordResetRequestGeneration &+= 1
        passwordResetRequestState = .idle
    }

    func requestPasswordReset(email: String) async {
        passwordResetRequestGeneration &+= 1
        let generation = passwordResetRequestGeneration
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AuthInputValidator.isValidEmail(normalizedEmail) else {
            passwordResetRequestState = .failed(
                L10n.text("error.auth.email_invalid", fallback: "Enter a valid email address.")
            )
            return
        }

        passwordResetRequestState = .sending
        do {
            try await passwordRecoveryActions.requestReset(normalizedEmail)
            guard generation == passwordResetRequestGeneration else { return }
            passwordResetRequestState = .sent
        } catch {
            guard generation == passwordResetRequestGeneration else { return }
            passwordResetRequestState = .failed(passwordRecoveryMessage(for: error, requestingEmail: true))
        }
    }

    func handlePasswordRecoveryURL(_ url: URL, gardenStore: GardenStore) async {
        activeGardenStore = gardenStore
        guard PasswordRecoveryCallback.matches(url) else { return }
        await waitForSessionEnd()
        guard !Task.isCancelled else { return }

        let callback: PasswordRecoveryCallback
        do {
            callback = try PasswordRecoveryCallback.parse(url)
        } catch {
            passwordRecoveryValidationOperation = nil
            guard let transition = await beginPasswordRecoveryTransition() else { return }
            await finishPasswordRecoveryFailure(
                error,
                activeRecoverySession: transition.activeRecoverySession,
                generation: transition.generation,
                gardenStore: gardenStore
            )
            return
        }

        if let operation = passwordRecoveryValidationOperation,
           operation.callback == callback {
            // iOS can deliver the same custom URL more than once while the app
            // is activating. Share the single-use PKCE exchange instead of
            // racing two requests and discarding whichever one consumed it.
            await finishPasswordRecoveryValidation(operation, gardenStore: gardenStore)
            return
        }

        if let validatedRecovery = validatedPasswordRecovery,
           validatedRecovery.callback == callback {
            // Supabase authorization codes are single-use. A later delivery of
            // the same callback should reuse its validated in-memory session,
            // including any refresh-token rotation completed since validation.
            if case .recoveringPassword = state {
                errorMessage = nil
                state = .recoveringPassword(validatedRecovery.session)
                return
            }
            passwordRecoveryValidationOperation = nil
            guard let transition = await beginPasswordRecoveryTransition() else { return }
            guard
                isCurrentSessionLifecycle(transition.generation),
                let currentRecovery = validatedPasswordRecovery,
                currentRecovery.id == validatedRecovery.id
            else { return }
            state = .recoveringPassword(currentRecovery.session)
            return
        }

        // A different callback remains newest-wins. Its lifecycle invalidates
        // the older result even if that network request cannot be cancelled.
        passwordRecoveryValidationOperation = nil
        guard let transition = await beginPasswordRecoveryTransition() else { return }
        let task = Task { try await passwordRecoveryActions.validate(callback) }
        let operation = PasswordRecoveryValidationOperation(
            id: UUID(),
            callback: callback,
            generation: transition.generation,
            activeRecoverySession: transition.activeRecoverySession,
            task: task
        )
        passwordRecoveryValidationOperation = operation
        await finishPasswordRecoveryValidation(operation, gardenStore: gardenStore)
    }

    func updateRecoveredPassword(_ password: String, gardenStore: GardenStore) async {
        activeGardenStore = gardenStore
        guard case let .recoveringPassword(publishedRecoverySession) = state else { return }
        guard !isPasswordUpdateInProgress else { return }
        isPasswordUpdateInProgress = true
        defer { isPasswordUpdateInProgress = false }
        errorMessage = nil
        let generation = sessionLifecycleGeneration
        let recoveryLineageID: UUID?
        let recoverySession: AuthSession
        if let validatedRecovery = validatedPasswordRecovery,
           validatedRecovery.session.user.id == publishedRecoverySession.user.id {
            recoveryLineageID = validatedRecovery.id
            recoverySession = validatedRecovery.session
        } else {
            recoveryLineageID = nil
            recoverySession = publishedRecoverySession
        }

        do {
            let activeRecoverySession: AuthSession
            if recoverySession.needsRefresh {
                let refreshed = try await refreshSession(recoverySession)
                try Task.checkCancellation()
                if isCurrentSessionLifecycle(generation) {
                    activeRecoverySession = try requireMatchingRefreshedIdentity(
                        refreshed,
                        expectedUserID: recoverySession.user.id
                    )
                } else {
                    // A same-user refresh token rotation can finish while an
                    // invalid duplicate callback temporarily owns the
                    // lifecycle. Preserve it only in the exact validated
                    // recovery lineage so a retry never reuses the consumed
                    // token. A distinct callback has a different lineage and
                    // cannot be overwritten here.
                    guard refreshed.user.id == recoverySession.user.id else { return }
                    activeRecoverySession = refreshed
                }
            } else {
                activeRecoverySession = recoverySession
            }
            if let recoveryLineageID {
                updateValidatedPasswordRecoverySession(
                    activeRecoverySession,
                    lineageID: recoveryLineageID
                )
            }
            guard isCurrentSessionLifecycle(generation) else { return }

            // Recovery credentials stay memory-only until the password change
            // succeeds. Keep a rotated refresh token in both the published
            // state and its durable in-memory lineage so a callback race cannot
            // make a retry reuse the already-consumed token.
            state = .recoveringPassword(activeRecoverySession)

            try await passwordRecoveryActions.updatePassword(password, activeRecoverySession)
            guard isCurrentSessionLifecycle(generation) else { return }

            let cancelledSyncTask = cancelGardenSyncTask()
            _ = await cancelledSyncTask?.value
            guard isCurrentSessionLifecycle(generation) else { return }

            if recoveryReturnState?.userID != activeRecoverySession.user.id {
#if DEBUG
                if gardenStore.isDemoMode {
                    gardenStore.endDemo()
                }
#endif
                gardenStore.clearLocalCache()
                UserDefaults.standard.removeObject(forKey: "rocio.cloud.photoConsent")
                gardenSyncStatus = .local
            }

            do {
                try sessionPersistence.save(activeRecoverySession)
                // A later duplicate or invalid callback may restore only this
                // newly persisted account, never the pre-recovery account.
                clearValidatedPasswordRecovery(lineageID: recoveryLineageID)
                recoveryReturnState = .signedIn(activeRecoverySession)
                state = .passwordUpdated(activeRecoverySession)
            } catch {
                // The provider has already changed the password. Without a
                // persisted replacement session, fail closed to avoid exposing
                // a garden cache whose owner cannot be proven after relaunch.
                sessionPersistence.clear()
                gardenStore.clearLocalCache()
                UserDefaults.standard.removeObject(forKey: "rocio.cloud.photoConsent")
                gardenSyncStatus = .local
                clearValidatedPasswordRecovery(lineageID: recoveryLineageID)
                recoveryReturnState = client == nil ? .unconfigured : .signedOut
                state = .passwordUpdatedRequiresSignIn
            }
        } catch {
            guard isCurrentSessionLifecycle(generation) else { return }
            errorMessage = passwordRecoveryMessage(for: error)
        }
    }

    func completePasswordRecovery(gardenStore: GardenStore) async {
        if state == .passwordUpdatedRequiresSignIn {
            clearValidatedPasswordRecovery(lineageID: nil)
            invalidateSessionLifecycle()
            recoveryReturnState = nil
            errorMessage = nil
            gardenSyncStatus = .local
            gardenStore.deactivatePersistence()
            state = client == nil ? .unconfigured : .signedOut
            return
        }

        guard case let .passwordUpdated(recoveredSession) = state else { return }
        clearValidatedPasswordRecovery(lineageID: nil)
        recoveryReturnState = nil
        errorMessage = nil
        let generation = beginSessionPreparation(recoveredSession)
        guard let prepared = completeSessionPreparation(generation: generation) else { return }
        gardenStore.activatePersistence(for: prepared.user.id)
        state = .signedIn(prepared)
        guard isCurrentSessionLifecycle(generation), !isEndingSession else { return }
        await refreshGarden(gardenStore: gardenStore)
        guard
            isCurrentSessionLifecycle(generation),
            !isEndingSession,
            let activeSession = session
        else { return }
        if analyticsEnabled, let client {
            await client.track(name: "password_recovery_completed", properties: [:], session: activeSession)
        }
    }

    func cancelPasswordRecovery(gardenStore: GardenStore) async {
        guard case .recoveringPassword = state else { return }
        clearValidatedPasswordRecovery(lineageID: nil)
        invalidateSessionLifecycle()
        let generation = sessionLifecycleGeneration
        errorMessage = nil
        await restoreStateAfterRecovery(gardenStore: gardenStore, generation: generation)
    }

    func signOut(gardenStore: GardenStore) async {
        guard !isEndingSession else { return }
        isEndingSession = true
        let sessionToSignOut = sessionForOperations
        clearValidatedPasswordRecovery(lineageID: nil)
        invalidateSessionLifecycle()
        let cancelledSyncTask = cancelGardenSyncTask()
        sessionPersistence.clear()
        UserDefaults.standard.removeObject(forKey: "rocio.cloud.photoConsent")
        gardenStore.clearLocalCache()
        gardenSyncStatus = .local
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
            let didPurgeLocalGarden = gardenStore.purgeAllLocalGardenData()
            sessionPersistence.clear()
            UserDefaults.standard.removeObject(forKey: "rocio.cloud.photoConsent")
            gardenSyncStatus = .local
            state = .signedOut
            errorMessage = didPurgeLocalGarden
                ? nil
                : L10n.text(
                    "error.local_data_delete",
                    fallback: "Your account was deleted and its garden is hidden, but Rocio could not remove every local garden file. Restart Rocio before signing in again. If this warning returns, remove and reinstall Rocio to clear the remaining local data."
                )
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
        gardenSyncStatus = .demo
        gardenStore.beginDemo()
        state = .demo
    }

    func exitDemo(gardenStore: GardenStore) {
        gardenStore.endDemo()
        gardenSyncStatus = .local
        state = client == nil ? .unconfigured : .signedOut
    }
#endif

    @discardableResult
    func enqueueGardenChange(_ change: GardenChange, gardenStore: GardenStore) -> Bool {
        // Signed-out/local-only operation has no cloud journal to maintain.
        guard let session else { return true }
        guard gardenStore.isPersistenceActive(for: session.user.id) else {
            gardenSyncStatus = .pending
            return false
        }
        var pending = loadPendingChanges(userID: session.user.id)
        guard !corruptedPendingOutboxUsers.contains(session.user.id) else {
            gardenSyncStatus = .pending
            return false
        }
        var queuedChange = PendingCloudChange(
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
                // Edits made immediately after a new local plant must retain
                // creation provenance when they collapse into one upsert.
                // This is the only preflight mutation safe to authorize after
                // observing a reset epoch because its UUID did not exist before.
                if pending.contains(where: {
                    $0.affectedPlantID == affectedPlantID &&
                        $0.isCreation == true &&
                        $0.lifecycleID == sessionLifecycleID
                }) {
                    queuedChange.isCreation = true
                }
                // Only the newest local intent for one UUID matters. This also
                // lets a deliberate edit replace an older quarantined intent
                // without disturbing conflicts for other plants.
                pending.removeAll { $0.affectedPlantID == affectedPlantID }
            }
            pending.append(queuedChange)
        }
        savePendingChanges(pending, userID: session.user.id)
        guard !corruptedPendingOutboxUsers.contains(session.user.id) else {
            gardenSyncStatus = .pending
            return false
        }
        // A retry is safe even before readiness because syncGarden always
        // performs and validates the current lifecycle's epoch preflight
        // before it can reach any mutation request.
        if gardenSyncTask != nil || isPreparingGardenSync {
            gardenSyncNeedsFollowUp = true
        }
        startGardenSync(gardenStore)
        return true
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
        var latestCompleted = false
        while let task = gardenSyncTask {
            didRun = true
            latestCompleted = await task.value
            guard !Task.isCancelled else { return false }
        }
        return didRun && latestCompleted && gardenSyncStatus == .synced
    }

    func identify(image: UIImage) async throws -> RemoteIdentificationResponse {
        guard let client, let session else { throw BackendError.unavailable }
        // A scan can poll one idempotent provider operation for up to 125
        // seconds. Refresh before starting unless the JWT safely outlives the
        // complete recovery window and normal request skew.
        let active = try await activeSession(from: session, minimumValidity: 180)
        let response = try await client.identify(image: image, session: active)
        if analyticsEnabled {
            await client.track(name: "flower_scan_completed", properties: ["provider": response.provider], session: active)
        }
        return response
    }

    private func currentRecoveryReturnState() -> RecoveryReturnState {
        switch state {
        case .unconfigured:
            return .unconfigured
        case .signedOut:
            return .signedOut
        case let .signedIn(session):
            return .signedIn(session)
        case .checking:
            if let saved = sessionBeingPrepared ?? sessionPersistence.load() {
                return .signedIn(saved)
            }
            return client == nil ? .unconfigured : .signedOut
        case .recoveringPassword, .passwordUpdated, .passwordUpdatedRequiresSignIn:
            return recoveryReturnState ?? (client == nil ? .unconfigured : .signedOut)
#if DEBUG
        case .demo:
            return .demo
#endif
        }
    }

    private func beginPasswordRecoveryTransition() async -> (
        activeRecoverySession: AuthSession?,
        generation: UInt
    )? {
        let activeRecoverySession: AuthSession?
        if let validatedRecovery = validatedPasswordRecovery {
            activeRecoverySession = validatedRecovery.session
        } else if case let .recoveringPassword(session) = state {
            activeRecoverySession = session
        } else {
            activeRecoverySession = nil
        }
        if recoveryReturnState == nil {
            recoveryReturnState = currentRecoveryReturnState()
        }
        invalidateSessionLifecycle()
        let generation = sessionLifecycleGeneration
        hasBootstrapped = true
        errorMessage = nil
        state = .checking

        let cancelledSyncTask = cancelGardenSyncTask()
        _ = await cancelledSyncTask?.value
        guard isCurrentSessionLifecycle(generation) else { return nil }
        return (activeRecoverySession, generation)
    }

    private func finishPasswordRecoveryValidation(
        _ operation: PasswordRecoveryValidationOperation,
        gardenStore: GardenStore
    ) async {
        let result = await operation.task.result
        guard passwordRecoveryValidationOperation?.id == operation.id else { return }
        // Only one waiter applies the shared result. A distinct callback clears
        // this slot before beginning its own newest-wins lifecycle.
        passwordRecoveryValidationOperation = nil
        guard isCurrentSessionLifecycle(operation.generation) else { return }

        switch result {
        case let .success(recoverySession):
            validatedPasswordRecovery = ValidatedPasswordRecovery(
                id: UUID(),
                callback: operation.callback,
                session: recoverySession
            )
            state = .recoveringPassword(recoverySession)
        case let .failure(error):
            await finishPasswordRecoveryFailure(
                error,
                activeRecoverySession: validatedPasswordRecovery?.session
                    ?? operation.activeRecoverySession,
                generation: operation.generation,
                gardenStore: gardenStore
            )
        }
    }

    private func updateValidatedPasswordRecoverySession(
        _ session: AuthSession,
        lineageID: UUID
    ) {
        guard var validatedRecovery = validatedPasswordRecovery,
              validatedRecovery.id == lineageID,
              validatedRecovery.session.user.id == session.user.id else { return }
        validatedRecovery.session = session
        validatedPasswordRecovery = validatedRecovery
    }

    private func clearValidatedPasswordRecovery(lineageID: UUID?) {
        guard let lineageID else {
            validatedPasswordRecovery = nil
            return
        }
        guard validatedPasswordRecovery?.id == lineageID else { return }
        validatedPasswordRecovery = nil
    }

    private func finishPasswordRecoveryFailure(
        _ error: Error,
        activeRecoverySession: AuthSession?,
        generation: UInt,
        gardenStore: GardenStore
    ) async {
        guard isCurrentSessionLifecycle(generation) else { return }
        errorMessage = passwordRecoveryMessage(for: error)
        if let activeRecoverySession {
            // A recovery authorization code is single-use. If a duplicate or
            // newer callback is invalid, keep the already validated memory-only
            // recovery session instead of restoring the pre-recovery account.
            state = .recoveringPassword(activeRecoverySession)
        } else {
            await restoreStateAfterRecovery(gardenStore: gardenStore, generation: generation)
        }
    }

    private func restoreStateAfterRecovery(gardenStore: GardenStore, generation: UInt) async {
        guard isCurrentSessionLifecycle(generation) else { return }
        let destination = recoveryReturnState ?? (client == nil ? .unconfigured : .signedOut)
        recoveryReturnState = nil

        switch destination {
        case .unconfigured:
            gardenStore.deactivatePersistence()
            gardenSyncStatus = .local
            state = .unconfigured
        case .signedOut:
            gardenStore.deactivatePersistence()
            gardenSyncStatus = .local
            state = .signedOut
        case let .signedIn(saved):
            gardenStore.activatePersistence(for: saved.user.id)
            let restoreGeneration = beginSessionPreparation(saved)
            do {
                let active = try await activeSession(from: saved)
                guard isCurrentSessionLifecycle(restoreGeneration) else { return }
                if active.user.id != saved.user.id {
                    gardenStore.activatePersistence(for: active.user.id)
                }
                sessionBeingPrepared = active
                guard let prepared = completeSessionPreparation(generation: restoreGeneration) else { return }
                state = .signedIn(prepared)
                await refreshGarden(gardenStore: gardenStore)
            } catch {
                guard isCurrentSessionLifecycle(restoreGeneration) else { return }
                if error.invalidatesSavedSession {
                    invalidateSessionLifecycle()
                    sessionPersistence.clear()
                    gardenStore.clearLocalCache()
                    gardenSyncStatus = .local
                    state = .signedOut
                } else {
                    sessionBeingPrepared = saved
                    guard let prepared = completeSessionPreparation(generation: restoreGeneration) else { return }
                    state = .signedIn(prepared)
                    gardenSyncStatus = .pending
                }
            }
#if DEBUG
        case .demo:
            gardenSyncStatus = .demo
            state = .demo
#endif
        }
    }

    private func passwordRecoveryMessage(for error: Error, requestingEmail: Bool = false) -> String {
        if let backendError = error as? BackendError {
            if case let .server(code, _) = backendError {
                if [
                    "http_429", "over_email_send_rate_limit", "email_rate_limit_exceeded",
                    "over_request_rate_limit",
                ].contains(code) {
                    return L10n.text(
                        "error.auth.recovery_rate",
                        fallback: "Too many reset emails were requested. Wait a few minutes and try again."
                    )
                }
                if !requestingEmail,
                   [
                       "http_401", "invalid_session", "session_expired", "otp_expired",
                       "invalid_token", "bad_jwt", "token_expired", "bad_code_verifier",
                       "flow_state_expired", "flow_state_not_found",
                   ].contains(code) {
                    return L10n.text(
                        "error.auth.recovery_link",
                        fallback: "This password reset link is invalid or expired. Request a new one."
                    )
                }
            }
            return backendError.errorDescription
                ?? L10n.text("error.cloud.generic", fallback: "Rocio Cloud is temporarily unavailable. Try again.")
        }
        if error is URLError {
            return L10n.text("error.network", fallback: "Check your internet connection and try again.")
        }
        return L10n.text("error.generic", fallback: "Something went wrong. Try again.")
    }

    private func authenticate(
        gardenStore: GardenStore,
        action: (RocioBackendClient) async throws -> AuthSession
    ) async {
        activeGardenStore = gardenStore
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
            // A fresh authentication may resume only a snapshot already bound
            // to the returned UUID. It must never claim legacy ownerless data.
            gardenStore.activatePersistence(for: session.user.id)
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
        guard gardenStore.isPersistenceActive(for: expectedUserID) else {
            gardenSyncStatus = .pending
            return false
        }
        let expectedLifecycleGeneration = sessionLifecycleGeneration
        let expectedLifecycleID = sessionLifecycleID
        // Capture before any network suspension. Reconciliation can then keep
        // only edits made while this specific sync was in flight.
        let localBaseline = gardenStore.plants
        isPreparingGardenSync = true
        defer {
            isPreparingGardenSync = false
        }
        gardenSyncStatus = .syncing
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
                gardenSyncStatus = .pending
                return false
            }

            var pendingBeforeFlush = loadPendingChanges(userID: expectedUserID)
            guard !corruptedPendingOutboxUsers.contains(expectedUserID) else {
                gardenSyncStatus = .pending
                return false
            }
            let startsWithIdempotentReset = pendingBeforeFlush.first?.kind == .reset
            let eligibleChangeIDs = Set(pendingBeforeFlush.compactMap { change -> UUID? in
                if startsWithIdempotentReset { return change.id }
                if change.gardenEpoch == initialMutationEpoch { return change.id }
                // A newly created UUID from this lifecycle is safe to authorize
                // after the guarded preflight. Updates to existing local plants
                // remain quarantined because they may predate a remote reset.
                if change.isCreation == true,
                   change.gardenEpoch == nil,
                   change.lifecycleID == expectedLifecycleID {
                    return change.id
                }
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
                gardenSyncStatus = .pending
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
                    merged.filter { !GardenSyncResolver.isDegradedLegacyArbitrary($0) },
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
            guard !corruptedPendingOutboxUsers.contains(expectedUserID) else {
                gardenSyncStatus = .pending
                return false
            }
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
            guard gardenStore.replaceFromCloud(reconciled) else {
                gardenSyncStatus = .pending
                return false
            }
            saveAuthoritativeGardenEpoch(syncState.gardenEpoch, userID: expectedUserID)
            clearProvisionalGardenEpoch(userID: expectedUserID)
            gardenHandshakeUserID = expectedUserID
            let hasRemainingPending = !loadPendingChanges(userID: expectedUserID).isEmpty
            guard !corruptedPendingOutboxUsers.contains(expectedUserID) else {
                gardenSyncStatus = .pending
                return false
            }
            gardenSyncStatus = hasRemainingPending ? .pending : .synced
            return !hasRemainingPending
        } catch {
            if isCurrentSessionLifecycle(expectedLifecycleGeneration) {
                gardenSyncStatus = .pending
            }
            return false
        }
    }

    private func activeSession(
        from session: AuthSession,
        minimumValidity: TimeInterval = 60
    ) async throws -> AuthSession {
        guard session.needsRefresh(within: minimumValidity) else { return session }
        let refreshedSession = try await refreshSession(session)
        try Task.checkCancellation()
        guard sessionForOperations == session else { throw CancellationError() }
        let refreshed = try requireMatchingRefreshedIdentity(
            refreshedSession,
            expectedUserID: session.user.id
        )
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

    private func requireMatchingRefreshedIdentity(
        _ refreshed: AuthSession,
        expectedUserID: UUID
    ) throws -> AuthSession {
        guard refreshed.user.id == expectedUserID else {
            invalidateSessionLifecycle()
            _ = cancelGardenSyncTask()
            sessionPersistence.clear()
            passwordRecoveryValidationOperation = nil
            validatedPasswordRecovery = nil
            recoveryReturnState = nil
            UserDefaults.standard.removeObject(forKey: "rocio.cloud.photoConsent")
            activeGardenStore?.deactivatePersistence()
            gardenSyncStatus = .local
            state = client == nil ? .unconfigured : .signedOut
            throw BackendError.server(
                code: "session_identity_changed",
                message: "The refreshed session belongs to a different account."
            )
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
        guard sessionForOperations != nil,
              !isEndingSession,
              !isPreparingGardenSync,
              gardenSyncTask == nil else { return }
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
        gardenSyncStatus = completed ? .synced : .pending
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
            let pendingSnapshot = loadPendingChanges(userID: session.user.id)
            guard !corruptedPendingOutboxUsers.contains(session.user.id) else { return false }
            guard let next = pendingSnapshot.first(where: {
                eligibleChangeIDs.contains($0.id)
            }) else { return true }
            do {
                let active = try await activeSession(from: self.sessionForOperations ?? session)
                guard isCurrentSessionLifecycle(lifecycleGeneration) else { return false }
                switch next.kind {
                case .upsert:
                    guard let plant = next.plant else { throw BackendError.invalidResponse }
                    let uploadPlant: GardenPlant?
                    if GardenSyncResolver.isDegradedLegacyArbitrary(plant) {
                        // Rocio 1.0 could queue only the non-null cloud
                        // sentinel, losing the authoritative v2 identity/care
                        // snapshot locally. Fetch before writing so an upgrade
                        // cannot erase Plant.id data. Missing, tombstoned, or
                        // equally degraded remote rows are retired without a
                        // write, preventing resurrection and retry loops.
                        let remote = try await client.fetchGarden(session: active)
                        guard isCurrentSessionLifecycle(lifecycleGeneration) else { return false }
                        uploadPlant = GardenSyncResolver.recoverLegacyPendingUpsert(
                            plant,
                            remote: remote
                        )
                    } else {
                        uploadPlant = plant
                    }
                    if let uploadPlant {
                        try await client.upsertGarden(
                            [uploadPlant],
                            gardenEpoch: activeEpoch,
                            session: active
                        )
                    }
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
                    guard !corruptedPendingOutboxUsers.contains(session.user.id) else { return false }
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
                guard !corruptedPendingOutboxUsers.contains(session.user.id) else { return false }
                latest.removeAll { $0.id == next.id }
                savePendingChanges(latest, userID: session.user.id)
            } catch {
                return false
            }
        }
        return false
    }

    private func loadPendingChanges(userID: UUID) -> [PendingCloudChange] {
        let defaults = UserDefaults.standard
        let primaryKey = pendingKey(userID)
        let backupKey = pendingBackupKey(userID)
        let primaryData = defaults.data(forKey: primaryKey)
        let backupData = defaults.data(forKey: backupKey)
        guard primaryData != nil || backupData != nil else {
            corruptedPendingOutboxUsers.remove(userID)
            return []
        }

        let primary = primaryData.flatMap(decodePendingJournal)
        let backup = backupData.flatMap(decodePendingJournal)
        if primary?.format == .future || backup?.format == .future {
            // Preserve bytes written by a newer app instead of repairing over
            // them with an older journal this build happens to understand.
            markPendingJournalCorrupt(userID)
            return []
        }
        if let primary, primary.format == .legacy {
            // Rocio 1.0 wrote only the live primary raw array. If a newer build
            // left a versioned backup before a downgrade, the legacy primary
            // contains the user's newer offline intent and must win.
            return migrateLegacyPendingJournal(primary, userID: userID)
        }
        if primary == nil, let backup, backup.format == .legacy {
            return migrateLegacyPendingJournal(backup, userID: userID)
        }
        if let selected = newestPendingJournal(primary: primary, backup: backup) {
            // Repair both copies to the newest valid generation. A crash can
            // interrupt either write, but a stale upsert must never win over a
            // newer delete or reset merely because one copy was damaged.
            defaults.set(selected.data, forKey: primaryKey)
            defaults.set(selected.data, forKey: backupKey)
            corruptedPendingOutboxUsers.remove(userID)
            return selected.changes
        }

        // Never reinterpret a corrupt mutation journal as an empty one: doing
        // so can upload an incomplete snapshot and silently lose offline edits
        // or deletions. Keep both byte copies untouched and fail cloud sync
        // closed until a valid app update or explicit recovery can read them.
        corruptedPendingOutboxUsers.insert(userID)
        gardenSyncStatus = .pending
        if errorMessage == nil {
            errorMessage = L10n.text(
                "cloud.pending.corrupt",
                fallback: "Rocio kept your local garden, but its pending cloud-change journal needs recovery."
            )
        }
        return []
    }

    func hasPendingGardenReset(for userID: UUID) -> Bool {
        loadPendingChanges(userID: userID).contains { $0.kind == .reset }
    }

    private func savePendingChanges(_ changes: [PendingCloudChange], userID: UUID) {
        let defaults = UserDefaults.standard
        let key = pendingKey(userID)
        let backupKey = pendingBackupKey(userID)
        guard !changes.isEmpty else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: backupKey)
            corruptedPendingOutboxUsers.remove(userID)
            return
        }
        guard !corruptedPendingOutboxUsers.contains(userID) else {
            gardenSyncStatus = .pending
            return
        }

        let decodedPrimary = defaults.data(forKey: key).flatMap(decodePendingJournal)
        let decodedBackup = defaults.data(forKey: backupKey).flatMap(decodePendingJournal)
        guard decodedPrimary?.format != .future, decodedBackup?.format != .future else {
            markPendingJournalCorrupt(userID)
            return
        }
        let currentGeneration = [
            decodedPrimary?.generation,
            decodedBackup?.generation,
        ].compactMap { $0 }.max() ?? 0
        let journal = PendingCloudChangeJournal(
            schemaVersion: PendingCloudChangeJournal.currentSchemaVersion,
            generation: currentGeneration == UInt64.max ? UInt64.max : currentGeneration + 1,
            changes: changes
        )
        guard let data = try? JSONEncoder().encode(journal),
              let verified = decodePendingJournal(data),
              verified.generation == journal.generation,
              verified.changes.map(\.id) == changes.map(\.id) else {
            markPendingJournalCorrupt(userID)
            return
        }

        // Store the same newest generation in both slots. The generation lets
        // recovery choose correctly if the process stops between these writes.
        defaults.set(data, forKey: backupKey)
        guard defaults.data(forKey: backupKey) == data else {
            markPendingJournalCorrupt(userID)
            return
        }
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else {
            markPendingJournalCorrupt(userID)
            return
        }
        corruptedPendingOutboxUsers.remove(userID)
    }

    private func decodePendingJournal(_ data: Data) -> DecodedPendingJournal? {
        let decoder = JSONDecoder()
        if let journal = try? decoder.decode(PendingCloudChangeJournal.self, from: data),
           journal.schemaVersion == PendingCloudChangeJournal.currentSchemaVersion {
            return DecodedPendingJournal(
                data: data,
                generation: journal.generation,
                changes: journal.changes,
                format: .current
            )
        }
        if let header = try? decoder.decode(PendingCloudChangeJournalHeader.self, from: data),
           header.schemaVersion > PendingCloudChangeJournal.currentSchemaVersion {
            return DecodedPendingJournal(
                data: data,
                generation: 0,
                changes: [],
                format: .future
            )
        }
        // One-time compatibility with journals written by Rocio 1.0.
        if let changes = try? decoder.decode([PendingCloudChange].self, from: data) {
            return DecodedPendingJournal(
                data: data,
                generation: 0,
                changes: changes,
                format: .legacy
            )
        }
        return nil
    }

    private func migrateLegacyPendingJournal(
        _ legacy: DecodedPendingJournal,
        userID: UUID
    ) -> [PendingCloudChange] {
        corruptedPendingOutboxUsers.remove(userID)
        savePendingChanges(legacy.changes, userID: userID)
        guard !corruptedPendingOutboxUsers.contains(userID) else { return [] }
        return legacy.changes
    }

    private func newestPendingJournal(
        primary: DecodedPendingJournal?,
        backup: DecodedPendingJournal?
    ) -> DecodedPendingJournal? {
        switch (primary, backup) {
        case let (primary?, backup?):
            return backup.generation > primary.generation ? backup : primary
        case let (primary?, nil):
            return primary
        case let (nil, backup?):
            return backup
        case (nil, nil):
            return nil
        }
    }

    private func markPendingJournalCorrupt(_ userID: UUID) {
        corruptedPendingOutboxUsers.insert(userID)
        gardenSyncStatus = .pending
        if errorMessage == nil {
            errorMessage = L10n.text(
                "cloud.pending.corrupt",
                fallback: "Rocio kept your local garden, but its pending cloud-change journal needs recovery."
            )
        }
    }

    private func pendingKey(_ userID: UUID) -> String {
        "rocio.cloud.pending.\(userID.uuidString.lowercased())"
    }

    private func pendingBackupKey(_ userID: UUID) -> String {
        "\(pendingKey(userID)).backup"
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

private enum RecoveryReturnState {
    case unconfigured
    case signedOut
    case signedIn(AuthSession)
#if DEBUG
    case demo
#endif

    var userID: UUID? {
        guard case let .signedIn(session) = self else { return nil }
        return session.user.id
    }
}

struct PasswordRecoveryActions {
    let requestReset: (String) async throws -> Void
    let validate: (PasswordRecoveryCallback) async throws -> AuthSession
    let updatePassword: (String, AuthSession) async throws -> Void

    static func live(
        client: RocioBackendClient?,
        codeVerifierPersistence: PasswordRecoveryCodeVerifierPersistence = .keychain
    ) -> PasswordRecoveryActions {
        PasswordRecoveryActions(
            requestReset: { email in
                guard let client else { throw BackendError.unavailable }
                let pkce = try PasswordRecoveryPKCE.generate()
                let previousCodeVerifier = try codeVerifierPersistence.replace(pkce.codeVerifier)
                do {
                    try await client.requestPasswordReset(email: email, codeChallenge: pkce.codeChallenge)
                } catch {
                    // Roll back only when the provider definitively rejected the
                    // request. A 5xx or transport failure may arrive after the
                    // email was accepted, so its new verifier must stay current.
                    if PasswordRecoveryActions.isDefinitiveResetRejection(error) {
                        _ = try? codeVerifierPersistence.restorePreviousIfCurrent(
                            pkce.codeVerifier,
                            previousCodeVerifier
                        )
                    }
                    throw error
                }
            },
            validate: { callback in
                guard let client else { throw BackendError.unavailable }
                guard let codeVerifier = codeVerifierPersistence.load() else {
                    throw BackendError.server(
                        code: "recovery_link_invalid",
                        message: "The password recovery link is invalid or expired."
                    )
                }
                let session = try await client.recoverySession(
                    from: callback,
                    codeVerifier: codeVerifier
                )
                // Consumption is atomic with respect to a newer reset request:
                // it clears only the verifier it validated, and records it so a
                // later rollback cannot resurrect the single-use verifier.
                codeVerifierPersistence.consume(codeVerifier)
                return session
            },
            updatePassword: { password, session in
                guard let client else { throw BackendError.unavailable }
                try await client.updatePassword(password, session: session)
            }
        )
    }

    private static func isDefinitiveResetRejection(_ error: Error) -> Bool {
        guard let backendError = error as? BackendError,
              case let .server(code, _) = backendError else {
            return false
        }
        if code.hasPrefix("http_"),
           let status = Int(code.dropFirst("http_".count)) {
            return (400..<500).contains(status)
        }
        return [
            "bad_json",
            "captcha_failed",
            "email_address_invalid",
            "email_address_not_authorized",
            "email_rate_limit_exceeded",
            "over_email_send_rate_limit",
            "over_request_rate_limit",
            "validation_failed",
        ].contains(code)
    }
}

enum AuthInputValidator {
    static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2
            && !parts[0].isEmpty
            && parts[1].contains(".")
            && !email.contains(where: { $0.isWhitespace })
    }

    static func isValidNewPassword(_ password: String, confirmation: String) -> Bool {
        password.count >= 8 && password == confirmation
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
    var isCreation: Bool?

    init(
        _ change: GardenChange,
        gardenEpoch: UUID? = nil,
        lifecycleID: UUID? = nil
    ) {
        id = UUID()
        self.gardenEpoch = gardenEpoch
        self.lifecycleID = lifecycleID
        switch change {
        case let .create(plant):
            kind = .upsert
            self.plant = plant
            plantID = nil
            occurredAt = nil
            isCreation = true
        case let .upsert(plant):
            kind = .upsert
            self.plant = plant
            plantID = nil
            occurredAt = nil
            isCreation = false
        case let .delete(id, at: date):
            kind = .delete
            plant = nil
            plantID = id
            occurredAt = date
            isCreation = nil
        case let .reset(at: date):
            kind = .reset
            plant = nil
            plantID = nil
            occurredAt = date
            isCreation = nil
        }
    }

    var affectedPlantID: UUID? {
        plant?.id ?? plantID
    }
}

struct PendingCloudChangeJournal: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generation: UInt64
    let changes: [PendingCloudChange]
}

private struct PendingCloudChangeJournalHeader: Decodable {
    let schemaVersion: Int
}

private enum PendingCloudChangeJournalFormat: Equatable {
    case current
    case legacy
    case future
}

private struct DecodedPendingJournal {
    let data: Data
    let generation: UInt64
    let changes: [PendingCloudChange]
    let format: PendingCloudChangeJournalFormat
}

struct GardenSyncResolver {
    static func isDegradedLegacyArbitrary(_ plant: GardenPlant) -> Bool {
        plant.flowerId == GardenPlant.arbitraryCloudFlowerID &&
            plant.identity.source == .bundled &&
            plant.identity.sourceID == GardenPlant.arbitraryCloudFlowerID
    }

    static func recoverLegacyPendingUpsert(
        _ local: GardenPlant,
        remote: [CloudGardenRecord]
    ) -> GardenPlant? {
        guard isDegradedLegacyArbitrary(local) else { return local }
        guard
            let record = remote.first(where: { $0.id == local.id }),
            record.deletedAt == nil
        else { return nil }
        let remotePlant = record.gardenPlant
        guard !isDegradedLegacyArbitrary(remotePlant) else { return nil }
        return preservingRicherProfile(local: local, remote: remotePlant)
    }

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
                    activeByID[plant.id] = preservingRicherProfile(
                        local: plant,
                        remote: remoteRecord.gardenPlant
                    )
                }
            } else if !isDegradedLegacyArbitrary(plant) {
                // A sentinel-only v1 row has no stable identity to create from
                // after upgrade. Without an authoritative remote match, treat
                // it as rejected rather than resurrecting a deleted/missing
                // cloud row.
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
            if activeByID[plant.id] == nil, isDegradedLegacyArbitrary(plant) {
                continue
            }

            if let remotePlant = activeByID[plant.id], remotePlant.updatedAt > plant.updatedAt {
                continue
            }
            activeByID[plant.id] = preservingRicherProfile(
                local: plant,
                remote: activeByID[plant.id]
            )
        }

        return sorted(activeByID.values)
    }

    private static func sorted<S: Sequence>(_ plants: S) -> [GardenPlant] where S.Element == GardenPlant {
        plants.sorted {
            if $0.addedAt != $1.addedAt { return $0.addedAt < $1.addedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func preservingRicherProfile(
        local: GardenPlant,
        remote: GardenPlant?
    ) -> GardenPlant {
        guard
            isDegradedLegacyArbitrary(local),
            let remote,
            !isDegradedLegacyArbitrary(remote)
        else {
            return local
        }

        // A v1 client can round-trip only the non-null sentinel and editable
        // fields. Preserve those edits while restoring the authoritative v2
        // provider/manual identity and care snapshot.
        var merged = local
        merged.flowerId = remote.flowerId
        merged.identity = remote.identity
        merged.careProfile = remote.careProfile
        return merged
    }
}
