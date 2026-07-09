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
                Section(L10n.text("garden.edit.plant", fallback: "Plant")) {
                    TextField(L10n.text("garden.edit.name", fallback: "Name"), text: $nickname)
                    Picker(L10n.text("garden.edit.status", fallback: "Status"), selection: $status) {
                        ForEach(PlantStatus.allCases) { status in
                            Label(status.label, systemImage: status.systemImage).tag(status)
                        }
                    }
                }

                Section(L10n.text("garden.edit.notes", fallback: "Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                Section {
                    Button(L10n.text("garden.edit.save", fallback: "Save changes")) {
                        gardenStore.update(plant, nickname: nickname, status: status, notes: notes)
                        dismiss()
                    }
                    Button(L10n.text("garden.edit.water", fallback: "Water now")) {
                        gardenStore.water(plant)
                        dismiss()
                    }
                    Button(L10n.text("garden.edit.remove", fallback: "Remove from garden"), role: .destructive) {
                        gardenStore.delete(plant)
                        dismiss()
                    }
                }
            }
            .navigationTitle(L10n.text("garden.edit.title", fallback: "Edit plant"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("action.close", fallback: "Close")) { dismiss() }
                }
            }
        }
    }
}
