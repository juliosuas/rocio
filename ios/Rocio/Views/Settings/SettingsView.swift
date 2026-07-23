import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var gardenStore: GardenStore
    @EnvironmentObject private var sessionStore: SessionStore
    @AppStorage("rocio.analytics.enabled") private var analyticsEnabled = true
    @State private var notificationStatus = L10n.text("settings.notifications.not.requested", fallback: "Not requested")
    @State private var showingResetConfirmation = false
    @State private var showingAccountDeletion = false
    @State private var dataResetStatus: GardenDataResetStatus?
    @State private var isResettingData = false

    private let notificationScheduler = WateringNotificationScheduler()
    private let localDataResetter = LocalDataResetter()

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("settings.account", fallback: "Account")) {
#if DEBUG
                    if sessionStore.isDemoMode {
                        LabeledContent(
                            L10n.text("settings.mode", fallback: "Mode"),
                            value: L10n.text("demo.title", fallback: "Debug demo")
                        )
                        LabeledContent(
                            L10n.text("settings.sync", fallback: "Cloud sync"),
                            value: L10n.text("demo.local.only", fallback: "Demo - local only")
                        )
                        Text(L10n.text("demo.data.notice", fallback: "Demo changes stay in memory and never reach Rocio Cloud."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            sessionStore.exitDemo(gardenStore: gardenStore)
                        } label: {
                            Label(L10n.text("demo.exit", fallback: "Exit demo"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        signedInAccountRows
                    }
#else
                    signedInAccountRows
#endif
                }
                Section(L10n.text("settings.permissions", fallback: "Permissions")) {
                    Text(L10n.text("settings.notifications.copy", fallback: "Rocio can send local reminders for your saved plants. They are enabled only after you tap this button and allow them in iOS."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            let granted = await notificationScheduler.requestAuthorization()
                            notificationStatus = granted
                                ? L10n.text("settings.notifications.active", fallback: "Reminders active")
                                : L10n.text("settings.notifications.denied", fallback: "Permission denied")
                            await notificationScheduler.refreshNotifications(for: gardenStore.plants)
                        }
                    } label: {
                        Label(L10n.text("settings.notifications.enable", fallback: "Enable watering reminders"), systemImage: "bell.badge")
                    }
                    Text(notificationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.text("settings.privacy", fallback: "Privacy")) {
                    if sessionStore.isDemoMode {
                        Text(L10n.text("demo.privacy.copy", fallback: "Demo garden changes stay on this device. Scanner photos are analyzed on-device and are not uploaded."))
                    } else {
                        Text(L10n.text("settings.privacy.copy", fallback: "Rocio syncs your garden to your account. Scanner photos are sent only after consent and are not stored by Rocio."))
                        Toggle(L10n.text("settings.analytics", fallback: "Share product analytics"), isOn: $analyticsEnabled)
                        Text(L10n.text("settings.analytics.copy", fallback: "Analytics contain product events tied to your Rocio account, never scanner photos or advertising identifiers."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ShareLink(item: exportPayload) {
                        Label(L10n.text("settings.export", fallback: "Export local data"), systemImage: "square.and.arrow.up")
                    }
                    Button(L10n.text("settings.delete", fallback: "Delete local data"), role: .destructive) {
                        showingResetConfirmation = true
                    }
                    .disabled(isResettingData)
                    if let dataResetStatus {
                        Label(dataResetStatus.message, systemImage: dataResetStatus.systemImage)
                            .font(.footnote)
                            .foregroundStyle(dataResetStatus.tint)
                        if dataResetStatus == .cloudPending {
                            Button {
                                Task { await retryPendingGardenDeletion() }
                            } label: {
                                Label(
                                    L10n.text("settings.delete.retry", fallback: "Retry cloud deletion"),
                                    systemImage: "arrow.clockwise"
                                )
                            }
                            .disabled(isResettingData)
                        }
                    }
                }

                Section(L10n.text("settings.about", fallback: "About")) {
                    LabeledContent(L10n.text("settings.version", fallback: "Version"), value: "1.0")
                    Link(destination: URL(string: "https://juliosuas.github.io/rocio/privacy.html")!) {
                        Label(L10n.text("settings.privacy.policy", fallback: "Privacy policy"), systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://juliosuas.github.io/rocio/support.html")!) {
                        Label(L10n.text("settings.support", fallback: "Support"), systemImage: "questionmark.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.rocioCanvas)
            .tint(Color.rocioLeafDeep)
            .navigationTitle(L10n.text("settings.title", fallback: "Settings"))
            .onAppear {
                if dataResetStatus == nil, sessionStore.hasPendingGardenReset {
                    dataResetStatus = .cloudPending
                }
            }
            .onChange(of: analyticsEnabled) { _, enabled in
                Task { await sessionStore.setAnalyticsEnabled(enabled) }
            }
            .onChange(of: sessionStore.gardenSyncStatus) { _, status in
                dataResetStatus = dataResetStatus?.reconciled(with: status)
            }
            .confirmationDialog(L10n.text("settings.delete", fallback: "Delete local data"), isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button(L10n.text("settings.delete.confirm", fallback: "Delete garden"), role: .destructive) {
                    Task { await resetGardenData() }
                }
                Button(L10n.text("action.cancel", fallback: "Cancel"), role: .cancel) {}
            } message: {
                Text(sessionStore.isDemoMode
                     ? L10n.text("demo.delete.message", fallback: "This clears the in-memory demo garden and cancels pending reminders.")
                     : L10n.text(
                        "settings.delete.message",
                        fallback: "This immediately clears your garden and reminders from this device. Rocio will then request deletion from the cloud."
                     ))
            }
            .confirmationDialog(L10n.text("settings.account.delete", fallback: "Delete account"), isPresented: $showingAccountDeletion, titleVisibility: .visible) {
                Button(L10n.text("settings.account.delete.confirm", fallback: "Permanently delete account"), role: .destructive) {
                    Task { await sessionStore.deleteAccount(gardenStore: gardenStore) }
                }
                Button(L10n.text("action.cancel", fallback: "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.text("settings.account.delete.message", fallback: "This permanently deletes your account, synced garden, scan history, and analytics events. This cannot be undone."))
            }
            .alert(
                L10n.text("settings.error.title", fallback: "Could not complete the request"),
                isPresented: Binding(
                    get: { sessionStore.errorMessage != nil },
                    set: { if !$0 { sessionStore.clearError() } }
                )
            ) {
                Button(L10n.text("action.ok", fallback: "OK")) { sessionStore.clearError() }
            } message: {
                Text(sessionStore.errorMessage ?? "")
            }
        }
    }

    private var exportPayload: String {
        GardenExport.payload(plants: gardenStore.plants)
    }

    @MainActor
    private func resetGardenData() async {
        guard !isResettingData else { return }
        isResettingData = true
        defer { isResettingData = false }

        dataResetStatus = nil
        if sessionStore.isDemoMode {
            dataResetStatus = await localDataResetter.reset(gardenStore: gardenStore)
            return
        }

        dataResetStatus = await localDataResetter.reset(
            gardenStore: gardenStore,
            waitForCloudConfirmation: { await sessionStore.waitForGardenSync() }
        )
    }

    @MainActor
    private func retryPendingGardenDeletion() async {
        guard !isResettingData, dataResetStatus == .cloudPending else { return }
        isResettingData = true
        defer { isResettingData = false }

        await sessionStore.refreshGarden(gardenStore: gardenStore)
        dataResetStatus = dataResetStatus?.reconciled(with: sessionStore.gardenSyncStatus)
    }

    @ViewBuilder
    private var signedInAccountRows: some View {
        if let email = sessionStore.session?.user.email {
            LabeledContent(L10n.text("settings.email", fallback: "Email"), value: email)
        }
        LabeledContent(L10n.text("settings.sync", fallback: "Cloud sync"), value: sessionStore.syncMessage)
        Button {
            Task { await sessionStore.signOut(gardenStore: gardenStore) }
        } label: {
            Label(L10n.text("settings.signout", fallback: "Sign out"), systemImage: "rectangle.portrait.and.arrow.right")
        }
        Button(role: .destructive) {
            showingAccountDeletion = true
        } label: {
            Label(L10n.text("settings.account.delete", fallback: "Delete account"), systemImage: "person.crop.circle.badge.minus")
        }
    }
}

enum GardenDataResetStatus: Equatable {
    case localOnly
    case cloudConfirmed
    case cloudPending
    case rejected

    var message: String {
        switch self {
        case .localOnly:
            L10n.text("settings.delete.done.local", fallback: "Garden and reminders deleted from this device.")
        case .cloudConfirmed:
            L10n.text(
                "settings.delete.done.cloud",
                fallback: "Garden deleted from this device and Rocio Cloud; local reminders canceled."
            )
        case .cloudPending:
            L10n.text(
                "settings.delete.done.pending",
                fallback: "Deleted from this device; cloud deletion is pending. Reconnect, then retry."
            )
        case .rejected:
            L10n.text(
                "settings.delete.rejected",
                fallback: "Nothing was deleted. Rocio could not safely save the deletion request; retry after cloud sync recovers."
            )
        }
    }

    var systemImage: String {
        switch self {
        case .localOnly, .cloudConfirmed: "checkmark.circle.fill"
        case .cloudPending: "icloud.slash"
        case .rejected: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .localOnly, .cloudConfirmed: .rocioTeal
        case .cloudPending, .rejected: .rocioAmber
        }
    }

    func reconciled(with cloudStatus: GardenCloudSyncStatus) -> GardenDataResetStatus {
        if self == .cloudPending, cloudStatus == .synced {
            return .cloudConfirmed
        }
        return self
    }
}

struct LocalDataResetter {
    private let cancelPendingNotifications: () -> Void

    init(notificationScheduler: WateringNotificationScheduler = WateringNotificationScheduler()) {
        self.cancelPendingNotifications = notificationScheduler.cancelPendingNotifications
    }

    init(cancelPendingNotifications: @escaping () -> Void) {
        self.cancelPendingNotifications = cancelPendingNotifications
    }

    @MainActor
    func reset(
        gardenStore: GardenStore,
        waitForCloudConfirmation: (() async -> Bool)? = nil
    ) async -> GardenDataResetStatus {
        guard gardenStore.reset() else { return .rejected }
        cancelPendingNotifications()
        guard let waitForCloudConfirmation else { return .localOnly }
        return await waitForCloudConfirmation() ? .cloudConfirmed : .cloudPending
    }
}
