import SwiftUI

struct GardenEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var gardenStore: GardenStore
    let plant: GardenPlant

    @State private var nickname: String
    @State private var status: PlantStatus
    @State private var notes: String
    @State private var wateringPreference: PlantWateringPreference?
    @State private var showingRemovalConfirmation = false

    init(plant: GardenPlant) {
        self.plant = plant
        _nickname = State(initialValue: plant.nickname)
        _status = State(initialValue: plant.status)
        _notes = State(initialValue: plant.notes)
        _wateringPreference = State(initialValue: plant.careProfile.wateringPreference)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        GardenPlantArtwork(flower: gardenStore.flower(for: plant), size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plant.displayName)
                                .font(.rocioTitle)
                            Text(plant.identity.scientificName ?? plant.identity.commonName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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

                if plant.careProfile.wateringIntervalDays == nil {
                    Section {
                        Picker(
                            L10n.text("garden.edit.watering.preference", fallback: "Watering preference"),
                            selection: $wateringPreference
                        ) {
                            Text(L10n.text("garden.edit.watering.not_set", fallback: "Not set"))
                                .tag(nil as PlantWateringPreference?)
                            ForEach(PlantWateringPreference.allCases, id: \.self) { preference in
                                Text(preference.label).tag(preference as PlantWateringPreference?)
                            }
                        }
                    } header: {
                        Text(L10n.text("garden.edit.care_schedule", fallback: "Care schedule"))
                    } footer: {
                        Text(L10n.text(
                            "garden.edit.watering.help",
                            fallback: "Choose only what you know. Rocio uses this as a reminder starting point, not an exact botanical prescription."
                        ))
                    }
                }

                Section {
                    Button(L10n.text("garden.edit.save", fallback: "Save changes")) {
                        var careProfile = plant.careProfile
                        careProfile.wateringPreference = wateringPreference
                        guard gardenStore.update(
                            plant,
                            nickname: nickname,
                            status: status,
                            notes: notes,
                            careProfile: careProfile
                        ) else { return }
                        dismiss()
                    }
                    Button(L10n.text("garden.edit.water", fallback: "Water now")) {
                        guard gardenStore.water(plant) else { return }
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
                    guard gardenStore.delete(plant) else { return }
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
