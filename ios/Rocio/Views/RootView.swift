import SwiftUI

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var gardenStore: GardenStore
    @AppStorage("rocio.ios.hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        switch sessionStore.state {
        case .checking:
            ProgressView(L10n.text("cloud.loading", fallback: "Opening Rocio"))
        case .unconfigured:
            CloudConfigurationRequiredView()
        case .signedOut:
            AuthView()
        case .signedIn:
            authenticatedContent
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if hasSeenOnboarding {
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
        } else {
            OnboardingView {
                hasSeenOnboarding = true
                router.selectedTab = .catalog
            }
        }
    }
}

private struct OnboardingView: View {
    let onFinish: () -> Void

    private var heroFlower: Flower? { FlowerCatalog.flower(id: "orquidea") }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let heroFlower {
                    FlowerArtwork(flower: heroFlower, height: 230)
                }

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rocio")
                            .font(.rocioDisplay)
                        Text(L10n.text("onboarding.subtitle", fallback: "Care for your flowers with simple guidance and secure cloud sync."))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        OnboardingStep(
                            systemImage: "camera.macro",
                            title: L10n.text("onboarding.choose.title", fallback: "Choose your flowers"),
                            copy: L10n.text("onboarding.choose.copy", fallback: "Start with familiar flowers and clear guides for your home, balcony, or garden.")
                        )
                        Divider()
                        OnboardingStep(
                            systemImage: "bell.badge",
                            title: L10n.text("onboarding.reminders.title", fallback: "Enable reminders"),
                            copy: L10n.text("onboarding.reminders.copy", fallback: "Rocio uses local notifications only after you enable them in Settings.")
                        )
                        Divider()
                        OnboardingStep(
                            systemImage: "icloud",
                            title: L10n.text("onboarding.private.title", fallback: "Your garden, synced"),
                            copy: L10n.text("onboarding.private.copy", fallback: "Your account keeps your garden available across devices. You can export or delete it anytime.")
                        )
                    }

                    Button(action: onFinish) {
                        HStack {
                            Label(L10n.text("onboarding.start", fallback: "Explore the catalog"), systemImage: "leaf")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(RocioPrimaryButtonStyle())
                }
                .padding(20)
            }
        }
        .background(Color.rocioCanvas.ignoresSafeArea())
    }
}

private struct OnboardingStep: View {
    let systemImage: String
    let title: String
    let copy: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.rocioLeafDeep)
                .frame(width: 42, height: 42)
                .background(Color.rocioLeafSoft, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(copy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    RootView()
        .environmentObject(AppRouter())
        .environmentObject(GardenStore(plants: []))
        .environmentObject(SessionStore(configuration: nil))
}
