import SwiftUI

struct GardenEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var gardenStore: GardenStore
    let plant: GardenPlant

    @State private var nickname: String
    @State private var status: PlantStatus
    @State private var notes: String
    @State private var showingRemovalConfirmation = false

    init(plant: GardenPlant) {
        self.plant = plant
        _nickname = State(initialValue: plant.nickname)
        _status = State(initialValue: plant.status)
        _notes = State(initialValue: plant.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let flower = gardenStore.flower(for: plant) {
                    Section {
                        HStack(spacing: 14) {
                            FlowerImage(flower: flower, size: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plant.nickname)
                                    .font(.rocioTitle)
                                Text(flower.scientific)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

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
                        showingRemovalConfirmation = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.rocioCanvas)
            .tint(Color.rocioLeafDeep)
            .navigationTitle(L10n.text("garden.edit.title", fallback: "Edit plant"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("action.close", fallback: "Close")) { dismiss() }
                }
            }
            .confirmationDialog(
                L10n.text("garden.remove.title", fallback: "Remove this plant?"),
                isPresented: $showingRemovalConfirmation,
                titleVisibility: .visible
            ) {
                Button(L10n.text("garden.edit.remove", fallback: "Remove from garden"), role: .destructive) {
                    gardenStore.delete(plant)
                    dismiss()
                }
                Button(L10n.text("action.cancel", fallback: "Cancel"), role: .cancel) {}
            } message: {
                Text(gardenStore.isDemoMode
                     ? L10n.text(
                        "garden.remove.message.demo",
                        fallback: "This removes the plant from this Debug demo. The change is not sent to Rocio Cloud."
                     )
                     : L10n.text(
                        "garden.remove.message",
                        fallback: "This removes the plant from this device now and requests removal from Rocio Cloud. If offline, cloud removal will retry."
                     ))
            }
        }
    }
}
