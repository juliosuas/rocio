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
                VStack(alignment: .leading, spacing: 18) {
                    CatalogHero()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FlowerCatalogFilter.allCases) { filter in
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        selectedFilter = filter
                                    }
                                } label: {
                                    RocioFilterChip(
                                        title: filter.title,
                                        systemImage: filter.systemImage,
                                        isSelected: selectedFilter == filter
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
                            }
                        }
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredFlowers) { flower in
                            Button {
                                selectedFlower = flower
                            } label: {
                                CatalogFlowerCard(
                                    flower: flower,
                                    isInGarden: gardenStore.plants.contains { $0.flowerId == flower.id }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }
            .background(Color.rocioCanvas)
            .navigationTitle(L10n.text("tab.catalog", fallback: "Catalog"))
            .searchable(text: $searchText, prompt: Text(L10n.text("catalog.search", fallback: "Search flowers")))
            .sheet(item: $selectedFlower) { flower in
                FlowerDetailView(flower: flower)
                    .environmentObject(gardenStore)
            }
        }
    }
}

private struct CatalogHero: View {
    private var flower: Flower? { FlowerCatalog.flower(id: "cempasuchil") }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let flower {
                FlowerArtwork(flower: flower, height: 190)
            } else {
                Color.rocioLeafAction.frame(height: 190)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Rocio")
                    .font(.rocioDisplay)
                Text(L10n.text("catalog.hero.title", fallback: "Flowers for home, balcony, and garden"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.46))
        }
    }
}

private struct CatalogFlowerCard: View {
    let flower: Flower
    let isInGarden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                FlowerArtwork(flower: flower, height: 132)
                if isInGarden {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.rocioLeafAction)
                        .padding(9)
                        .accessibilityLabel(L10n.text("catalog.in.garden", fallback: "In your garden"))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(flower.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(flower.scientific)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                CareLine(
                    title: L10n.format("watering.interval", fallback: "%d ml every %d days", flower.waterMl, flower.waterDays),
                    systemImage: "drop.fill",
                    tint: .rocioTeal
                )
                CareLine(
                    title: flower.sunlightLabel,
                    systemImage: flower.sunlight == .fullSun ? "sun.max.fill" : "sun.min.fill",
                    tint: .rocioRose
                )
            }
            .padding(11)
        }
        .background(Color.rocioSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.rocioLine))
    }
}

private struct CareLine: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
