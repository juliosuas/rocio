import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var gardenStore: GardenStore
    @State private var notificationStatus = "Sin solicitar"
    @State private var showingResetConfirmation = false

    private let notificationScheduler = WateringNotificationScheduler()

    var body: some View {
        NavigationStack {
            Form {
                Section("Permisos") {
                    Text("Rocio puede enviarte recordatorios locales para regar tus plantas guardadas. Se activan solo si tocas este boton y aceptas el permiso de iOS.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            let granted = await notificationScheduler.requestAuthorization()
                            notificationStatus = granted ? "Recordatorios activos" : "Permiso denegado"
                            await notificationScheduler.refreshNotifications(for: gardenStore.plants)
                        }
                    } label: {
                        Label("Activar recordatorios de riego", systemImage: "bell.badge")
                    }
                    Text(notificationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Privacidad") {
                    Text("Rocio guarda tu jardin localmente en este iPhone. Las fotos se analizan en el dispositivo y no se guardan en esta version nativa.")
                    ShareLink(item: exportPayload) {
                        Label("Exportar datos locales", systemImage: "square.and.arrow.up")
                    }
                    Button("Borrar datos locales", role: .destructive) {
                        showingResetConfirmation = true
                    }
                }

                Section("App Store") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Bundle", value: "com.juliosuas.rocio")
                    Text("Pendiente antes de publicar: Apple Developer Team, capturas finales, revision visual, politica de privacidad y TestFlight.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .confirmationDialog("Borrar datos locales", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Borrar jardin", role: .destructive) {
                    gardenStore.reset()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta accion elimina tu jardin guardado en este iPhone.")
            }
        }
    }

    private var exportPayload: String {
        GardenExport.payload(plants: gardenStore.plants)
    }
}
