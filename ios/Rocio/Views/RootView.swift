import SwiftUI

struct RootView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            CatalogView()
                .tabItem { Label(AppTab.catalog.title, systemImage: AppTab.catalog.systemImage) }
                .tag(AppTab.catalog)

            GardenView()
                .tabItem { Label(AppTab.garden.title, systemImage: AppTab.garden.systemImage) }
                .tag(AppTab.garden)

            CareCalendarView()
                .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage) }
                .tag(AppTab.calendar)

            ScannerView()
                .tabItem { Label(AppTab.scanner.title, systemImage: AppTab.scanner.systemImage) }
                .tag(AppTab.scanner)

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppRouter())
        .environmentObject(GardenStore(plants: []))
}

