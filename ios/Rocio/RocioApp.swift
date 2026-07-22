import SwiftUI

@main
struct RocioApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var router = AppRouter()
    @StateObject private var gardenStore = GardenStore()
    @StateObject private var sessionStore = SessionStore()
    private let notificationScheduler = WateringNotificationScheduler()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(gardenStore)
                .environmentObject(sessionStore)
                .tint(.rocioLeaf)
                .onAppear {
                    router.applyPendingIntentRoute(authenticatedIdentity: authenticationIdentity)
                }
                .onOpenURL { url in
                    if PasswordRecoveryCallback.matches(url) {
                        if let authenticationIdentity {
                            router.beginAuthenticatedTransition(from: authenticationIdentity)
                        }
                        Task {
                            await sessionStore.handlePasswordRecoveryURL(url, gardenStore: gardenStore)
                        }
                    } else {
                        router.route(url, authenticatedIdentity: authenticationIdentity)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    gardenStore.reloadFromPersistence()
                    router.applyPendingIntentRoute(authenticatedIdentity: authenticationIdentity)
                    Task { [weak gardenStore, weak sessionStore] in
                        guard let gardenStore, let sessionStore else { return }
                        await sessionStore.refreshGarden(gardenStore: gardenStore)
                    }
                }
                .task(id: gardenStore.plants) {
                    guard !gardenStore.isDemoMode else { return }
                    await notificationScheduler.refreshNotifications(for: gardenStore.plants)
                }
                .task {
                    gardenStore.cloudChangeHandler = { [weak gardenStore, weak sessionStore] change in
                        guard let gardenStore, let sessionStore else { return }
                        sessionStore.enqueueGardenChange(change, gardenStore: gardenStore)
                    }
                    await sessionStore.bootstrap(gardenStore: gardenStore)
                }
        }
    }

    private var authenticationIdentity: AppAuthenticationIdentity? {
        if let userID = sessionStore.session?.user.id {
            return .user(userID)
        }
#if DEBUG
        if sessionStore.isDemoMode {
            return .demo
        }
#endif
        return nil
    }
}
