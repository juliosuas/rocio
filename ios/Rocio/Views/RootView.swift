import SwiftUI

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @AppStorage("rocio.ios.hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
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

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 22)

            VStack(spacing: 10) {
                Text("Rocio")
                    .font(.largeTitle.bold())
                Text(L10n.text("onboarding.subtitle", fallback: "Care for your flowers, privately and without the fuss."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(spacing: 12) {
                OnboardingStep(
                    systemImage: "camera.macro",
                    title: L10n.text("onboarding.choose.title", fallback: "Choose your flowers"),
                    copy: L10n.text("onboarding.choose.copy", fallback: "Start with familiar flowers and clear guides for your home, balcony, or garden.")
                )
                OnboardingStep(
                    systemImage: "bell.badge",
                    title: L10n.text("onboarding.reminders.title", fallback: "Enable reminders"),
                    copy: L10n.text("onboarding.reminders.copy", fallback: "Rocio uses local notifications only after you enable them in Settings.")
                )
                OnboardingStep(
                    systemImage: "lock.shield",
                    title: L10n.text("onboarding.private.title", fallback: "Your private garden"),
                    copy: L10n.text("onboarding.private.copy", fallback: "Your plants stay on this iPhone. You can export or delete your data.")
                )
            }
            .padding(.horizontal)

            Button(action: onFinish) {
                Label(L10n.text("onboarding.start", fallback: "Explore the catalog"), systemImage: "leaf")
            }
            .buttonStyle(RocioPrimaryButtonStyle())
            .padding(.horizontal)

            Spacer(minLength: 22)
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
                .background(Color.rocioLeafSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(copy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.rocioLine)
        )
    }
}

#Preview {
    RootView()
        .environmentObject(AppRouter())
        .environmentObject(GardenStore(plants: []))
}
