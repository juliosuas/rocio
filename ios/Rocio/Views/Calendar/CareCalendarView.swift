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
                            Text("Sin riegos programados")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(due) { plant in
                                if let flower = gardenStore.flower(for: plant) {
                                    HStack {
                                        FlowerImage(flower: flower, size: 44)
                                        VStack(alignment: .leading) {
                                            Text(plant.nickname)
                                                .font(.headline)
                                            Text("\(flower.waterMl) ml de agua")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Regar") {
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
            .navigationTitle("Calendario")
        }
    }

    private func duePlants(on day: Date) -> [GardenPlant] {
        gardenStore.plants.filter { plant in
            Calendar.current.isDate(gardenStore.nextWateringDate(for: plant), inSameDayAs: day)
        }
    }
}

