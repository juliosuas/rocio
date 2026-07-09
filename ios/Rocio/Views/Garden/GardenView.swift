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
            .navigationTitle(L10n.text("garden.title", fallback: "My Garden"))
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
                    Text(L10n.text("garden.empty.title", fallback: "Your garden is ready to grow"))
                        .font(.title2.bold())
                    Text(L10n.text("garden.empty.copy", fallback: "Add your first flower to unlock watering, calendar, and Siri shortcuts."))
                        .foregroundStyle(.secondary)
                }

                Button(action: onOpenCatalog) {
                    Label(L10n.text("garden.empty.action", fallback: "Open catalog"), systemImage: "plus")
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
                        Text(L10n.text("garden.summary.title", fallback: "Garden status"))
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
                    MetricPill(title: L10n.text("garden.summary.plants", fallback: "Plants"), value: "\(summary.plantCount)", systemImage: "leaf")
                    MetricPill(title: L10n.text("garden.summary.attention", fallback: "Attention"), value: "\(summary.needsAttentionCount)", systemImage: "bell")
                }

                if let nextWateringDate = summary.nextWateringDate {
                    Label(
                        L10n.format(
                            "garden.summary.next",
                            fallback: "Next watering: %@",
                            nextWateringDate.formatted(date: .abbreviated, time: .omitted)
                        ),
                        systemImage: "calendar"
                    )
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
                Button(L10n.text("action.edit", fallback: "Edit"), action: onEdit)
                    .buttonStyle(.borderless)
                Button(L10n.text("action.water", fallback: "Water"), action: onWater)
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
