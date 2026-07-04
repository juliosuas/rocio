import SwiftUI

struct GardenView: View {
    @EnvironmentObject private var gardenStore: GardenStore
    @State private var editingPlant: GardenPlant?

    var body: some View {
        NavigationStack {
            Group {
                if gardenStore.plants.isEmpty {
                    ContentUnavailableView(
                        "Tu jardin esta vacio",
                        systemImage: "leaf",
                        description: Text("Agrega flores desde el catalogo para activar riegos y atajos.")
                    )
                } else {
                    List {
                        ForEach(gardenStore.plants) { plant in
                            if let flower = gardenStore.flower(for: plant) {
                                GardenRow(
                                    plant: plant,
                                    flower: flower,
                                    urgency: gardenStore.urgency(for: plant),
                                    nextWatering: gardenStore.nextWateringDate(for: plant),
                                    onWater: { gardenStore.water(plant) },
                                    onEdit: { editingPlant = plant }
                                )
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Mi Jardin")
            .sheet(item: $editingPlant) { plant in
                GardenEditView(plant: plant)
                    .environmentObject(gardenStore)
            }
        }
    }
}

private struct GardenRow: View {
    let plant: GardenPlant
    let flower: Flower
    let urgency: WateringUrgency
    let nextWatering: Date
    let onWater: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FlowerImage(flower: flower, size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plant.nickname)
                        .font(.headline)
                    Text(flower.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(urgency.label, systemImage: urgency == .overdue ? "exclamationmark.circle" : "drop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(urgency == .overdue ? .red : Color.rocioLeaf)
                }
                Spacer()
            }

            HStack {
                Label(nextWatering.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Editar", action: onEdit)
                    .buttonStyle(.borderless)
                Button("Regar", action: onWater)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }
}

