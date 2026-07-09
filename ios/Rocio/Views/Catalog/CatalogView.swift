import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var gardenStore: GardenStore
    @State private var searchText = ""
    @State private var selectedFilter: FlowerCatalogFilter = .all
    @State private var selectedFlower: Flower?

    private var filteredFlowers: [Flower] {
        FlowerCatalog.filteredFlowers(searchText: searchText, filter: selectedFilter)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    RocioCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(L10n.text("catalog.hero.title", fallback: "Flowers for home, balcony, and garden"), systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(Color.rocioLeafDeep)
                            Text(L10n.text("catalog.hero.copy", fallback: "Filter by easy care, sun, indoor growing, or flowers familiar across Mexico and Latin America."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker(L10n.text("catalog.filter", fallback: "Filter"), selection: $selectedFilter) {
                        ForEach(FlowerCatalogFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 2)

                    ForEach(filteredFlowers) { flower in
                        Button {
                            selectedFlower = flower
                        } label: {
                            CatalogFlowerCard(flower: flower, isInGarden: gardenStore.plants.contains { $0.flowerId == flower.id })
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Rocio")
            .searchable(text: $searchText, prompt: Text(L10n.text("catalog.search", fallback: "Search flowers")))
            .sheet(item: $selectedFlower) { flower in
                FlowerDetailView(flower: flower)
                    .environmentObject(gardenStore)
            }
        }
    }
}

private struct CatalogFlowerCard: View {
    let flower: Flower
    let isInGarden: Bool

    var body: some View {
        HStack(spacing: 14) {
            FlowerImage(flower: flower, size: 76)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(flower.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(flower.scientific)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if isInGarden {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.rocioLeafDeep)
                            .accessibilityLabel(L10n.text("catalog.in.garden", fallback: "In your garden"))
                    }
                }

                HStack(spacing: 6) {
                    PillLabel(title: flower.difficultyLabel, systemImage: "chart.bar")
                    PillLabel(title: flower.sunlightLabel, systemImage: "sun.max")
                }

                Label(
                    L10n.format("watering.interval", fallback: "%d ml every %d days", flower.waterMl, flower.waterDays),
                    systemImage: "drop"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.rocioLine)
        )
    }
}
