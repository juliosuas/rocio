import SwiftUI

struct CareCalendarView: View {
    @EnvironmentObject private var gardenStore: GardenStore

    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(days, id: \.self) { day in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        let due = duePlants(on: day)
                        if due.isEmpty {
                            Text(L10n.text("calendar.empty", fallback: "No watering scheduled"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(due) { plant in
                                if let flower = gardenStore.flower(for: plant) {
                                    HStack {
                                        FlowerImage(flower: flower, size: 44)
                                        VStack(alignment: .leading) {
                                            Text(plant.nickname)
                                                .font(.headline)
                                            Text(L10n.format("calendar.water.amount", fallback: "%d ml of water", flower.waterMl))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button(L10n.text("action.water", fallback: "Water")) {
                                            gardenStore.water(plant)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.text("calendar.title", fallback: "Calendar"))
        }
    }

    private func duePlants(on day: Date) -> [GardenPlant] {
        gardenStore.plants.filter { plant in
            Calendar.current.isDate(gardenStore.nextWateringDate(for: plant), inSameDayAs: day)
        }
    }
}
