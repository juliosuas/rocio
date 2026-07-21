import SwiftUI

struct CareCalendarView: View {
    @EnvironmentObject private var gardenStore: GardenStore

    var body: some View {
        let schedule = gardenStore.wateringSchedule()

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    CalendarOverview(
                        days: schedule.days.map(\.date),
                        dueCount: schedule.totalDueCount
                    )

                    if !schedule.overduePlants.isEmpty {
                        CalendarDaySection(
                            title: L10n.text("calendar.overdue", fallback: "Overdue"),
                            plants: schedule.overduePlants,
                            gardenStore: gardenStore,
                            badgeTint: .rocioRose
                        )
                    }

                    ForEach(schedule.days) { day in
                        CalendarDaySection(
                            title: day.date.formatted(date: .complete, time: .omitted),
                            plants: day.plants,
                            gardenStore: gardenStore,
                            badgeTint: .rocioTeal
                        )
                    }
                }
                .padding(16)
            }
            .background(Color.rocioCanvas)
            .navigationTitle(L10n.text("calendar.title", fallback: "Calendar"))
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
                        Calendar.current.isDateInToday(day) ? Color.rocioLeafAction : Color.rocioSurface,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
            }
        }
    }
}

private struct CalendarDaySection: View {
    let title: String
    let plants: [GardenPlant]
    let gardenStore: GardenStore
    let badgeTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if !plants.isEmpty {
                    RocioStatusBadge(title: "\(plants.count)", systemImage: "drop.fill", tint: badgeTint)
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
