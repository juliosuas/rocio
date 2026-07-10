import SwiftUI

struct FlowerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var gardenStore: GardenStore
    let flower: Flower

    private var inGarden: Bool {
        gardenStore.plants.contains { $0.flowerId == flower.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack(alignment: .bottomLeading) {
                        FlowerArtwork(flower: flower, height: 280)
                        Color.black.opacity(0.42).frame(height: 106)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(flower.name)
                                .font(.rocioDisplay)
                            Text(flower.scientific)
                                .font(.subheadline)
                                .italic()
                        }
                        .foregroundStyle(.white)
                        .padding(18)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        Text(flower.fact)
                            .font(.title3)
                            .foregroundStyle(Color.rocioSoil)

                        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                            DetailMetric(
                                title: L10n.text("detail.watering", fallback: "Watering"),
                                value: L10n.format("watering.interval", fallback: "%d ml every %d days", flower.waterMl, flower.waterDays),
                                systemImage: "drop.fill",
                                tint: .rocioTeal
                            )
                            DetailMetric(title: L10n.text("detail.light", fallback: "Light"), value: flower.sunlightLabel, systemImage: "sun.max.fill", tint: .rocioRose)
                            DetailMetric(title: L10n.text("detail.difficulty", fallback: "Difficulty"), value: flower.difficultyLabel, systemImage: "chart.bar.fill", tint: .rocioLeaf)
                            DetailMetric(
                                title: L10n.text("detail.temperature", fallback: "Temperature"),
                                value: L10n.format("detail.temperature.value", fallback: "%d-%d C", flower.tempRange.lowerBound, flower.tempRange.upperBound),
                                systemImage: "thermometer.medium",
                                tint: .rocioAmber
                            )
                        }

                        DetailSection(title: L10n.text("detail.soil", fallback: "Soil"), bodyText: flower.soil, systemImage: "mountain.2")
                        DetailSection(title: L10n.text("detail.toxicity", fallback: "Pets and toxicity"), bodyText: "\(flower.toxicLevel.label): \(flower.toxic)", systemImage: "pawprint")
                        DetailSection(title: L10n.text("detail.fertilizer", fallback: "Fertilizing"), bodyText: flower.fertilizer, systemImage: "leaf")
                        DetailSection(title: L10n.text("detail.pruning", fallback: "Pruning"), bodyText: flower.pruning, systemImage: "scissors")
                        DetailSection(title: L10n.text("detail.propagation", fallback: "Propagation"), bodyText: flower.propagation, systemImage: "arrow.triangle.branch")
                        DetailSection(title: L10n.text("detail.companions", fallback: "Companion plants"), bodyText: flower.companions, systemImage: "person.2")

                        VStack(alignment: .leading, spacing: 12) {
                            RocioSectionHeader(title: L10n.text("detail.planting", fallback: "Planting"))
                            ForEach(Array(flower.plantingSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(Color.rocioLeafAction, in: Circle())
                                    Text(step)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }
            .background(Color.rocioCanvas)
            .navigationTitle(flower.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.text("action.close", fallback: "Close"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    gardenStore.add(flower)
                    dismiss()
                } label: {
                    Label(
                        inGarden
                            ? L10n.text("detail.in.garden", fallback: "Already in My Garden")
                            : L10n.text("detail.add.garden", fallback: "Add to My Garden"),
                        systemImage: inGarden ? "checkmark" : "plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(RocioPrimaryButtonStyle())
                .disabled(inGarden)
                .padding()
                .background(.bar)
            }
        }
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.rocioSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.rocioLine))
    }
}

private struct DetailSection: View {
    let title: String
    let bodyText: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.rocioLeafDeep)
            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
