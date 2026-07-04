import SwiftUI

struct GardenEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var gardenStore: GardenStore
    let plant: GardenPlant

    @State private var nickname: String
    @State private var status: PlantStatus
    @State private var notes: String

    init(plant: GardenPlant) {
        self.plant = plant
        _nickname = State(initialValue: plant.nickname)
        _status = State(initialValue: plant.status)
        _notes = State(initialValue: plant.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Planta") {
                    TextField("Nombre", text: $nickname)
                    Picker("Estado", selection: $status) {
                        ForEach(PlantStatus.allCases) { status in
                            Label(status.label, systemImage: status.systemImage).tag(status)
                        }
                    }
                }

                Section("Notas") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                Section {
                    Button("Guardar cambios") {
                        gardenStore.update(plant, nickname: nickname, status: status, notes: notes)
                        dismiss()
                    }
                    Button("Regar ahora") {
                        gardenStore.water(plant)
                        dismiss()
                    }
                    Button("Quitar del jardin", role: .destructive) {
                        gardenStore.delete(plant)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Editar planta")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

