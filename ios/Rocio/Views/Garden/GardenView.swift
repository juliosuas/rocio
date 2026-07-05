import SwiftUI

struct GardenView: View {
    @EnvironmentObject private var gardenStore: GardenStore
    @EnvironmentObject private var router: AppRouter
    @State private var editingPlant: GardenPlant?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if gardenStore.plants.isEmpty {
                        EmptyGardenCard {
                            router.selectedTab = .catalog
                        }
                    } else {
                        GardenSummaryCard(summary: gardenStore.summary())

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
                }
                .padding()
            }
            .navigationTitle("Mi Jardin")
            .sheet(item: $editingPlant) { plant in
                GardenEditView(plant: plant)
                    .environmentObject(gardenStore)
            }
        }
    }
}

private struct EmptyGardenCard: View {
    let onOpenCatalog: () -> Void

    var body: some View {
        RocioCard {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.rocioLeafDeep)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tu jardin esta listo para empezar")
                        .font(.title2.bold())
                    Text("Agrega tu primera flor para activar riegos, calendario y atajos de Siri.")
                        .foregroundStyle(.secondary)
                }

                Button(action: onOpenCatalog) {
                    Label("Abrir catalogo", systemImage: "plus")
                }
                .buttonStyle(RocioPrimaryButtonStyle())
            }
        }
    }
}

private struct GardenSummaryCard: View {
    let summary: GardenSummary

    var body: some View {
        RocioCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estado de tu jardin")
                            .font(.headline)
                        Text(summary.statusLabel)
                            .font(.title2.bold())
                            .foregroundStyle(summary.overdueCount > 0 ? .red : Color.rocioLeafDeep)
                    }
                    Spacer()
                    Image(systemName: summary.overdueCount > 0 ? "drop.fill" : "checkmark.seal.fill")
                        .font(.title)
                        .foregroundStyle(summary.overdueCount > 0 ? .red : Color.rocioLeafDeep)
                }

                HStack(spacing: 10) {
                    MetricPill(title: "Plantas", value: "\(summary.plantCount)", systemImage: "leaf")
                    MetricPill(title: "Atencion", value: "\(summary.needsAttentionCount)", systemImage: "bell")
                }

                if let nextWateringDate = summary.nextWateringDate {
                    Label("Proximo riego: \(nextWateringDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.rocioLine)
        )
    }
}
