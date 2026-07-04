import SwiftUI

@main
struct RocioApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var router = AppRouter()
    @StateObject private var gardenStore = GardenStore()
    private let notificationScheduler = WateringNotificationScheduler()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(gardenStore)
                .tint(.rocioLeaf)
                .onAppear {
                    router.applyPendingIntentRoute()
                }
                .onOpenURL { url in
                    router.route(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    gardenStore.reloadFromPersistence()
                    router.applyPendingIntentRoute()
                }
                .task(id: gardenStore.plants) {
                    await notificationScheduler.refreshNotifications(for: gardenStore.plants)
                }
        }
    }
}
