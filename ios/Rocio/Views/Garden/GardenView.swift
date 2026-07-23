import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct GardenView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var gardenStore: GardenStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var reminderController: FirstCareReminderController
    @State private var editingPlant: GardenPlant?
    @State private var recentlyWateredPlantID: UUID?
    @State private var isAddingPlantManually = false

    init() {
        _reminderController = StateObject(wrappedValue: .live())
    }

    init(reminderController: FirstCareReminderController) {
        _reminderController = StateObject(wrappedValue: reminderController)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    GardenSyncStatusView(status: sessionStore.gardenSyncStatus)
                    GardenPersistenceStatusView(status: gardenStore.persistenceStatus)

                    if gardenStore.plants.isEmpty {
                        EmptyGardenView(
                            onOpenCatalog: { router.selectedTab = .catalog },
                            onAddManually: {
                                guard gardenStore.canAcceptLocalChanges else { return }
                                isAddingPlantManually = true
                            }
                        )
                    } else {
                        GardenSummaryView(summary: gardenStore.summary())

                        if gardenStore.plants.count == 1,
                           gardenStore.plants[0].resolvedWateringIntervalDays != nil,
                           !gardenStore.isDemoMode {
                            FirstCareReminderCard(
                                state: reminderController.state,
                                onEnable: {
                                    Task {
                                        await reminderController.enable(
                                            currentPlants: { gardenStore.plants }
                                        )
                                    }
                                },
                                onOpenSettings: openNotificationSettings
                            )
                        }

                        ForEach(gardenStore.plants) { plant in
                            GardenRow(
                                plant: plant,
                                flower: gardenStore.flower(for: plant),
                                urgency: gardenStore.urgency(for: plant),
                                nextWatering: gardenStore.nextWateringDate(for: plant),
                                isWateredConfirmationVisible: recentlyWateredPlantID == plant.id,
                                onWater: { water(plant) },
                                onEdit: { editingPlant = plant }
                            )
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
            .sheet(isPresented: $isAddingPlantManually) {
                ManualPlantEntryView { identity, careProfile in
                    gardenStore.add(
                        identity: identity,
                        careProfile: careProfile,
                        nickname: identity.commonName
                    ) != nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingPlantManually = true
                    } label: {
                        Label(L10n.text("garden.add", fallback: "Add plant"), systemImage: "plus")
                    }
                    .disabled(!gardenStore.canAcceptLocalChanges)
                }
            }
            .task {
                await refreshReminderAuthorization()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await refreshReminderAuthorization()
                }
            }
        }
    }

    private func openNotificationSettings() {
        guard let settingsURL = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(settingsURL)
    }

    private func refreshReminderAuthorization() async {
        guard !gardenStore.isDemoMode else { return }
        await reminderController.refreshAuthorization(
            currentPlants: { gardenStore.plants }
        )
    }

    private func water(_ plant: GardenPlant) {
        guard gardenStore.water(plant) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            recentlyWateredPlantID = plant.id
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard recentlyWateredPlantID == plant.id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                recentlyWateredPlantID = nil
            }
        }
    }
}

@MainActor
final class FirstCareReminderController: ObservableObject {
    enum State: Equatable {
        case checking
        case available
        case requesting
        case enabled
        case denied
    }

    @Published private(set) var state: State = .checking

    private let authorizationStatus: () async -> UNAuthorizationStatus
    private let requestAuthorization: () async -> Bool
    private let refreshNotifications: ([GardenPlant]) async -> Void

    init(
        authorizationStatus: @escaping () async -> UNAuthorizationStatus,
        requestAuthorization: @escaping () async -> Bool,
        refreshNotifications: @escaping ([GardenPlant]) async -> Void
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAuthorization = requestAuthorization
        self.refreshNotifications = refreshNotifications
    }

    static func live() -> FirstCareReminderController {
        let scheduler = WateringNotificationScheduler()
        return FirstCareReminderController(
            authorizationStatus: {
                await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            },
            requestAuthorization: {
                await scheduler.requestAuthorization()
            },
            refreshNotifications: { plants in
                await scheduler.refreshNotifications(for: plants)
            }
        )
    }

    func refreshAuthorization(
        currentPlants: @MainActor () -> [GardenPlant]
    ) async {
        guard state != .requesting else { return }
        let previousState = state
        let nextState = Self.state(for: await authorizationStatus())
        guard state != .requesting else { return }

        if nextState == .enabled, previousState != .enabled {
            await refreshNotifications(currentPlants())
            guard state != .requesting else { return }
        }
        state = nextState
    }

    func enable(
        currentPlants: @MainActor () -> [GardenPlant]
    ) async {
        guard state == .available else { return }
        state = .requesting

        guard await requestAuthorization() else {
            state = .denied
            return
        }

        await refreshNotifications(currentPlants())
        state = .enabled
    }

    private static func state(for authorizationStatus: UNAuthorizationStatus) -> State {
        switch authorizationStatus {
        case .notDetermined:
            .available
        case .authorized, .provisional, .ephemeral:
            .enabled
        case .denied:
            .denied
        @unknown default:
            .denied
        }
    }
}

private struct EmptyGardenView: View {
    let onOpenCatalog: () -> Void
    let onAddManually: () -> Void
    private var flower: Flower? { FlowerCatalog.flower(id: "lavanda") }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let flower {
                FlowerArtwork(flower: flower, height: 220, cornerRadius: 8)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("garden.empty.title", fallback: "Your garden is ready to grow"))
                    .font(.rocioTitle)
                Text(L10n.text(
                    "garden.empty.copy",
                    fallback: "Add your first plant to unlock care tracking, calendar, and Siri shortcuts."
                ))
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

            Button(action: onAddManually) {
                HStack {
                    Label(
                        L10n.text("garden.empty.manual", fallback: "Add a plant manually"),
                        systemImage: "square.and.pencil"
                    )
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(RocioSecondaryButtonStyle())
        }
    }
}

private struct GardenSummaryView: View {
    let summary: GardenSummary

    private var statusTint: Color {
        if summary.overdueCount > 0 { return .rocioRose }
        if summary.unscheduledCount > 0 { return .rocioAmber }
        return .rocioTeal
    }

    private var statusSystemImage: String {
        if summary.overdueCount > 0 { return "drop.fill" }
        if summary.unscheduledCount > 0 { return "calendar.badge.exclamationmark" }
        return "checkmark.seal.fill"
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
                Image(systemName: statusSystemImage)
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

private struct GardenSyncStatusView: View {
    let status: GardenCloudSyncStatus

    private var tint: Color {
        switch status {
        case .synced, .demo, .local: .rocioTeal
        case .syncing: .rocioLeafDeep
        case .pending: .rocioAmber
        }
    }

    private var systemImage: String {
        switch status {
        case .local, .demo: "iphone"
        case .syncing: "icloud.and.arrow.up"
        case .synced: "checkmark.icloud.fill"
        case .pending: "icloud.slash"
        }
    }

    var body: some View {
        Label(status.message, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

private struct GardenPersistenceStatusView: View {
    let status: GardenPersistence.LoadStatus

    var body: some View {
        switch status {
        case .recoveredFromBackup:
            Label(
                L10n.text(
                    "garden.persistence.recovered",
                    fallback: "Rocio recovered your local garden from its last known-good backup."
                ),
                systemImage: "externaldrive.badge.checkmark"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.rocioTeal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.rocioTeal.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
        case .unrecoverableCorruption:
            Label(
                L10n.text(
                    "garden.persistence.corrupt",
                    fallback: "Rocio could not read the local garden file. It has not been overwritten; cloud sync can still restore a valid copy."
                ),
                systemImage: "externaldrive.badge.exclamationmark"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.rocioRose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.rocioRose.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
        case .empty, .loaded, .migratedLegacy:
            EmptyView()
        }
    }
}

private struct FirstCareReminderCard: View {
    let state: FirstCareReminderController.State
    let onEnable: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: state == .enabled ? "bell.badge.fill" : "bell.badge")
                    .font(.title2)
                    .foregroundStyle(state == .enabled ? Color.rocioTeal : Color.rocioLeafDeep)
                    .frame(width: 42, height: 42)
                    .background(Color.rocioLeafSoft, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("garden.reminders.title", fallback: "Keep care on schedule"))
                        .font(.headline)
                    Text(reminderCopy)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            reminderAction
        }
        .padding(14)
        .background(Color.rocioSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.rocioLine))
    }

    private var reminderCopy: String {
        switch state {
        case .checking, .available, .requesting:
            L10n.text(
                "garden.reminders.copy",
                fallback: "Enable local reminders for this plant. Rocio asks iOS only after you tap."
            )
        case .enabled:
            L10n.text("garden.reminders.enabled", fallback: "Watering reminders are on for your garden.")
        case .denied:
            L10n.text(
                "garden.reminders.denied",
                fallback: "Notifications are off. You can enable them in iOS Settings."
            )
        }
    }

    @ViewBuilder
    private var reminderAction: some View {
        switch state {
        case .checking:
            ProgressView(L10n.text("garden.reminders.checking", fallback: "Checking reminder access"))
                .font(.footnote)
        case .available:
            Button(action: onEnable) {
                Label(
                    L10n.text("garden.reminders.enable", fallback: "Enable watering reminders"),
                    systemImage: "bell.badge"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(RocioPrimaryButtonStyle())
        case .requesting:
            HStack(spacing: 8) {
                ProgressView()
                Text(L10n.text("garden.reminders.requesting", fallback: "Waiting for your choice"))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
        case .enabled:
            Label(
                L10n.text("garden.reminders.enabled.short", fallback: "Reminders active"),
                systemImage: "checkmark.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.rocioTeal)
        case .denied:
            Button(action: onOpenSettings) {
                Label(
                    L10n.text("garden.reminders.open.settings", fallback: "Open notification settings"),
                    systemImage: "gear"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(RocioSecondaryButtonStyle())
        }
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
    let flower: Flower?
    let urgency: WateringUrgency?
    let nextWatering: Date?
    let isWateredConfirmationVisible: Bool
    let onWater: () -> Void
    let onEdit: () -> Void

    private var urgencyTint: Color {
        switch urgency {
        case .overdue?: .rocioRose
        case .soon?: .rocioAmber
        case .good?: .rocioTeal
        case nil: .rocioAmber
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                GardenPlantArtwork(flower: flower, size: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plant.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(plant.identity.commonName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    RocioStatusBadge(
                        title: urgency?.label ?? L10n.text(
                            "calendar.unscheduled",
                            fallback: "Care schedule not set"
                        ),
                        systemImage: urgency == .overdue ? "exclamationmark.circle.fill" : urgency == nil ? "calendar.badge.exclamationmark" : "drop.fill",
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    nextWateringLabel
                    Spacer()
                    waterButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    nextWateringLabel
                    waterButton
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color.rocioSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.rocioLine))
    }

    private var nextWateringLabel: some View {
        Label(
            nextWatering?.formatted(date: .abbreviated, time: .omitted)
                ?? L10n.text("garden.watering.no_date", fallback: "No watering date"),
            systemImage: "calendar"
        )
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var waterButton: some View {
        Button(action: onWater) {
            Label(
                isWateredConfirmationVisible
                    ? L10n.text("garden.watered.confirmation", fallback: "Watered")
                    : L10n.text("action.water", fallback: "Water"),
                systemImage: isWateredConfirmationVisible ? "checkmark.circle.fill" : "drop.fill"
            )
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(isWateredConfirmationVisible ? Color.rocioLeafAction : Color.rocioTeal)
        .disabled(isWateredConfirmationVisible)
        .sensoryFeedback(.success, trigger: isWateredConfirmationVisible) { _, isVisible in
            isVisible
        }
    }
}

struct GardenPlantArtwork: View {
    let flower: Flower?
    let size: CGFloat

    var body: some View {
        Group {
            if let flower {
                FlowerImage(flower: flower, size: size)
            } else {
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(Color.rocioLeafDeep)
                    .frame(width: size, height: size)
                    .background(Color.rocioLeafSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct ManualPlantEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (PlantIdentity, PlantCareProfile) -> Bool

    @State private var commonName = ""
    @State private var scientificName = ""
    @State private var wateringSelection = ManualWateringSelection.notSet

    private var normalizedCommonName: String {
        commonName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedScientificName: String? {
        let value = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("garden.manual.identity", fallback: "Plant identity")) {
                    TextField(L10n.text("garden.manual.common_name", fallback: "Common name"), text: $commonName)
                        .textInputAutocapitalization(.words)
                    TextField(
                        L10n.text("garden.manual.scientific_name", fallback: "Scientific name (optional)"),
                        text: $scientificName
                    )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Picker(
                        L10n.text("garden.edit.watering.preference", fallback: "Watering preference"),
                        selection: $wateringSelection
                    ) {
                        ForEach(ManualWateringSelection.allCases) { selection in
                            Text(selection.label).tag(selection)
                        }
                    }
                } header: {
                    Text(L10n.text("garden.manual.care", fallback: "Care (optional)"))
                } footer: {
                    Text(L10n.text(
                        "garden.manual.care.help",
                        fallback: "Choose only what you know. Leave this as Not sure to avoid creating a watering schedule."
                    ))
                }
            }
            .navigationTitle(L10n.text("garden.add", fallback: "Add plant"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("action.cancel", fallback: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("action.save", fallback: "Save")) {
                        let identity = PlantIdentity(
                            source: .manual,
                            commonName: normalizedCommonName,
                            scientificName: normalizedScientificName,
                            nameLocale: Locale.current.identifier
                        )
                        let careProfile = PlantCareProfile(
                            wateringPreference: wateringSelection.preference,
                            source: .manual,
                            fetchedAt: Date()
                        )
                        if onSave(identity, careProfile) {
                            dismiss()
                        }
                    }
                    .disabled(normalizedCommonName.isEmpty)
                }
            }
        }
    }
}

private enum ManualWateringSelection: String, CaseIterable, Identifiable {
    case notSet
    case dry
    case medium
    case wet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notSet: L10n.text("watering.preference.not_set", fallback: "Not sure")
        case .dry: L10n.text("watering.preference.dry.short", fallback: "Let soil dry")
        case .medium: L10n.text("watering.preference.medium.short", fallback: "Keep moderately moist")
        case .wet: L10n.text("watering.preference.wet.short", fallback: "Keep moist")
        }
    }

    var preference: PlantWateringPreference? {
        switch self {
        case .notSet: nil
        case .dry: .dry
        case .medium: .medium
        case .wet: .wet
        }
    }
}
