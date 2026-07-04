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
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        FlowerImage(flower: flower, size: 112)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(flower.name)
                                .font(.largeTitle.bold())
                            Text(flower.scientific)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(flower.fact)
                                .font(.callout)
                        }
                    }

                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                        DetailMetric(title: "Riego", value: "\(flower.waterMl) ml cada \(flower.waterDays) dias", systemImage: "drop")
                        DetailMetric(title: "Luz", value: flower.sunlightLabel, systemImage: "sun.max")
                        DetailMetric(title: "Dificultad", value: flower.difficultyLabel, systemImage: "chart.bar")
                        DetailMetric(title: "Temperatura", value: "\(flower.tempRange.lowerBound)-\(flower.tempRange.upperBound) C", systemImage: "thermometer")
                    }

                    DetailSection(title: "Suelo", bodyText: flower.soil)
                    DetailSection(title: "Mascotas y toxicidad", bodyText: "\(flower.toxicLevel.label): \(flower.toxic)")
                    DetailSection(title: "Fertilizacion", bodyText: flower.fertilizer)
                    DetailSection(title: "Poda", bodyText: flower.pruning)
                    DetailSection(title: "Propagacion", bodyText: flower.propagation)
                    DetailSection(title: "Companeras", bodyText: flower.companions)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Siembra")
                            .font(.headline)
                        ForEach(Array(flower.plantingSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .frame(width: 24, height: 24)
                                    .background(Color.rocioLeafSoft, in: Circle())
                                Text(step)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color.rocioCanvas.opacity(0.55))
            .navigationTitle(flower.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    gardenStore.add(flower)
                    dismiss()
                } label: {
                    Label(inGarden ? "Ya esta en Mi Jardin" : "Agregar a Mi Jardin", systemImage: inGarden ? "checkmark" : "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rocioSoil)
            Text(value)
                .font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DetailSection: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

