import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var gardenStore: GardenStore
    @State private var searchText = ""
    @State private var selectedFlower: Flower?

    private var filteredFlowers: [Flower] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FlowerCatalog.all
        }
        return FlowerCatalog.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.scientific.localizedCaseInsensitiveContains(searchText) ||
            $0.sunlightLabel.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredFlowers) { flower in
                Button {
                    selectedFlower = flower
                } label: {
                    HStack(spacing: 14) {
                        FlowerImage(flower: flower)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(flower.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(flower.scientific)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                PillLabel(title: flower.sunlightLabel, systemImage: "sun.max")
                                PillLabel(title: "\(flower.waterMl) ml / \(flower.waterDays)d", systemImage: "drop")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Rocio")
            .searchable(text: $searchText, prompt: "Buscar flor")
            .sheet(item: $selectedFlower) { flower in
                FlowerDetailView(flower: flower)
                    .environmentObject(gardenStore)
            }
        }
    }
}

