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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    CalendarOverview(days: days, dueCount: totalDueCount)

                    ForEach(days, id: \.self) { day in
                        CalendarDaySection(
                            day: day,
                            plants: duePlants(on: day),
                            gardenStore: gardenStore
                        )
                    }
                }
                .padding(16)
            }
            .background(Color.rocioCanvas)
            .navigationTitle(L10n.text("calendar.title", fallback: "Calendar"))
        }
    }

    private var totalDueCount: Int {
        days.reduce(0) { $0 + duePlants(on: $1).count }
    }

    private func duePlants(on day: Date) -> [GardenPlant] {
        gardenStore.plants.filter { plant in
            Calendar.current.isDate(gardenStore.nextWateringDate(for: plant), inSameDayAs: day)
        }
    }
}

private struct CalendarOverview: View {
    let days: [Date]
    let dueCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date().formatted(.dateTime.month(.wide).year()))
                        .font(.rocioTitle)
                    Label("\(dueCount)", systemImage: "drop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rocioTeal)
                }
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(Color.rocioRose)
            }

            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 5) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                        Text(day.formatted(.dateTime.day()))
                            .font(.headline)
                    }
                    .foregroundStyle(Calendar.current.isDateInToday(day) ? .white : Color.rocioSoil)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Calendar.current.isDateInToday(day) ? Color.rocioLeafDeep : Color.rocioSurface,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
            }
        }
    }
}

private struct CalendarDaySection: View {
    let day: Date
    let plants: [GardenPlant]
    let gardenStore: GardenStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.formatted(date: .complete, time: .omitted))
                    .font(.headline)
                Spacer()
                if !plants.isEmpty {
                    RocioStatusBadge(title: "\(plants.count)", systemImage: "drop.fill", tint: .rocioTeal)
                }
            }

            if plants.isEmpty {
                Label(L10n.text("calendar.empty", fallback: "No watering scheduled"), systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 7)
            } else {
                ForEach(plants) { plant in
                    if let flower = gardenStore.flower(for: plant) {
                        HStack(spacing: 12) {
                            FlowerImage(flower: flower, size: 52)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plant.nickname)
                                    .font(.headline)
                                Text(L10n.format("calendar.water.amount", fallback: "%d ml of water", flower.waterMl))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                gardenStore.water(plant)
                            } label: {
                                Image(systemName: "drop.fill")
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.rocioTeal)
                            .accessibilityLabel(L10n.text("action.water", fallback: "Water"))
                        }
                        .padding(12)
                        .background(Color.rocioSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.rocioLine))
                    }
                }
            }
        }
    }
}
