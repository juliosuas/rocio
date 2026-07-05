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
                Text("Cuida tus flores en espanol, privado y sin complicarte.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(spacing: 12) {
                OnboardingStep(
                    systemImage: "camera.macro",
                    title: "Elige tus flores",
                    copy: "Empieza con flores comunes y fichas claras para casa, balcon o jardin."
                )
                OnboardingStep(
                    systemImage: "bell.badge",
                    title: "Activa recordatorios",
                    copy: "Rocio usa notificaciones locales solo cuando las pides desde Ajustes."
                )
                OnboardingStep(
                    systemImage: "lock.shield",
                    title: "Tu jardin privado",
                    copy: "Tus plantas viven en este iPhone. Puedes exportar o borrar tus datos."
                )
            }
            .padding(.horizontal)

            Button(action: onFinish) {
                Label("Empezar con el catalogo", systemImage: "leaf")
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
