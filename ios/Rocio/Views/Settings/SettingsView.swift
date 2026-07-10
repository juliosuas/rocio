import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var gardenStore: GardenStore
    @EnvironmentObject private var sessionStore: SessionStore
    @AppStorage("rocio.analytics.enabled") private var analyticsEnabled = true
    @State private var notificationStatus = L10n.text("settings.notifications.not.requested", fallback: "Not requested")
    @State private var showingResetConfirmation = false
    @State private var showingAccountDeletion = false

    private let notificationScheduler = WateringNotificationScheduler()
    private let localDataResetter = LocalDataResetter()

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("settings.account", fallback: "Account")) {
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
                    Text(L10n.text("settings.privacy.copy", fallback: "Rocio syncs your garden to your account. Scanner photos are sent only after consent and are not stored by Rocio."))
                    Toggle(L10n.text("settings.analytics", fallback: "Share product analytics"), isOn: $analyticsEnabled)
                    Text(L10n.text("settings.analytics.copy", fallback: "Analytics contain product events tied to your Rocio account, never scanner photos or advertising identifiers."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ShareLink(item: exportPayload) {
                        Label(L10n.text("settings.export", fallback: "Export local data"), systemImage: "square.and.arrow.up")
                    }
                    Button(L10n.text("settings.delete", fallback: "Delete local data"), role: .destructive) {
                        showingResetConfirmation = true
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
            .navigationTitle(L10n.text("settings.title", fallback: "Settings"))
            .confirmationDialog(L10n.text("settings.delete", fallback: "Delete local data"), isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button(L10n.text("settings.delete.confirm", fallback: "Delete garden"), role: .destructive) {
                    localDataResetter.reset(gardenStore: gardenStore)
                    notificationStatus = L10n.text("settings.delete.done", fallback: "Data and reminders deleted")
                }
                Button(L10n.text("action.cancel", fallback: "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.text("settings.delete.message", fallback: "This removes your garden from this device and Rocio Cloud, and cancels pending reminders."))
            }
            .confirmationDialog(L10n.text("settings.account.delete", fallback: "Delete account"), isPresented: $showingAccountDeletion, titleVisibility: .visible) {
                Button(L10n.text("settings.account.delete.confirm", fallback: "Permanently delete account"), role: .destructive) {
                    Task { await sessionStore.deleteAccount(gardenStore: gardenStore) }
                }
                Button(L10n.text("action.cancel", fallback: "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.text("settings.account.delete.message", fallback: "This permanently deletes your account, synced garden, scan history, and analytics events. This cannot be undone."))
            }
        }
    }

    private var exportPayload: String {
        GardenExport.payload(plants: gardenStore.plants)
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
    func reset(gardenStore: GardenStore) {
        gardenStore.reset()
        cancelPendingNotifications()
    }
}
