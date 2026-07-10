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
                        EmptyGardenView {
                            router.selectedTab = .catalog
                        }
                    } else {
                        GardenSummaryView(summary: gardenStore.summary())

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
                .padding(16)
            }
            .background(Color.rocioCanvas)
            .navigationTitle(L10n.text("garden.title", fallback: "My Garden"))
            .sheet(item: $editingPlant) { plant in
                GardenEditView(plant: plant)
                    .environmentObject(gardenStore)
            }
        }
    }
}

private struct EmptyGardenView: View {
    let onOpenCatalog: () -> Void
    private var flower: Flower? { FlowerCatalog.flower(id: "lavanda") }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let flower {
                FlowerArtwork(flower: flower, height: 220, cornerRadius: 8)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("garden.empty.title", fallback: "Your garden is ready to grow"))
                    .font(.rocioTitle)
                Text(L10n.text("garden.empty.copy", fallback: "Add your first flower to unlock watering, calendar, and Siri shortcuts."))
                    .foregroundStyle(.secondary)
            }

            Button(action: onOpenCatalog) {
                HStack {
                    Label(L10n.text("garden.empty.action", fallback: "Open catalog"), systemImage: "plus")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(RocioPrimaryButtonStyle())
        }
    }
}

private struct GardenSummaryView: View {
    let summary: GardenSummary

    private var statusTint: Color {
        summary.overdueCount > 0 ? .rocioRose : .rocioTeal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("garden.summary.title", fallback: "Garden status"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text(summary.statusLabel)
                        .font(.rocioTitle)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: summary.overdueCount > 0 ? "drop.fill" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(statusTint)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.94), in: Circle())
            }

            HStack(spacing: 0) {
                SummaryMetric(title: L10n.text("garden.summary.plants", fallback: "Plants"), value: "\(summary.plantCount)")
                Divider().overlay(.white.opacity(0.24))
                SummaryMetric(title: L10n.text("garden.summary.attention", fallback: "Attention"), value: "\(summary.needsAttentionCount)")
            }
            .frame(height: 50)

            if let nextWateringDate = summary.nextWateringDate {
                Label(
                    L10n.format("garden.summary.next", fallback: "Next watering: %@", nextWateringDate.formatted(date: .abbreviated, time: .omitted)),
                    systemImage: "calendar"
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.84))
            }
        }
        .padding(18)
        .background(Color.rocioLeafAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

private struct GardenRow: View {
    let plant: GardenPlant
    let flower: Flower
    let urgency: WateringUrgency
    let nextWatering: Date
    let onWater: () -> Void
    let onEdit: () -> Void

    private var urgencyTint: Color {
        switch urgency {
        case .overdue: .rocioRose
        case .soon: .rocioAmber
        case .good: .rocioTeal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                FlowerImage(flower: flower, size: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plant.nickname)
                        .font(.headline)
                        .lineLimit(1)
                    Text(flower.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    RocioStatusBadge(
                        title: urgency.label,
                        systemImage: urgency == .overdue ? "exclamationmark.circle.fill" : "drop.fill",
                        tint: urgencyTint
                    )
                }
                Spacer(minLength: 4)
                Button(action: onEdit) {
                    Image(systemName: "ellipsis")
                        .frame(width: 38, height: 38)
                        .background(Color.rocioCanvas, in: Circle())
                }
                .accessibilityLabel(L10n.text("action.edit", fallback: "Edit"))
            }

            Divider()

            HStack(spacing: 12) {
                Label(nextWatering.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onWater) {
                    Label(L10n.text("action.water", fallback: "Water"), systemImage: "drop.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.rocioTeal)
            }
        }
        .padding(14)
        .background(Color.rocioSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.rocioLine))
    }
}
