import XCTest
@testable import Rocio

@MainActor
final class GardenStoreTests: XCTestCase {
    func testReturningUserStartsInGarden() {
        XCTAssertEqual(AppRouter().selectedTab, .garden)
    }

    func testAuthenticatedSessionReturnsFromSettingsToGarden() {
        let router = AppRouter()
        let identity = AppAuthenticationIdentity.user(UUID())
        router.selectedTab = .settings

        router.prepareForAuthenticatedSession(identity, hasSeenOnboarding: true)

        XCTAssertEqual(router.selectedTab, .garden)
    }

    func testPreAuthenticationDeepLinkWinsOverDefaultGardenLanding() throws {
        let router = AppRouter()
        let identity = AppAuthenticationIdentity.user(UUID())
        let scannerURL = try XCTUnwrap(URL(string: "rocio://scanner"))

        router.route(scannerURL, authenticatedIdentity: nil)
        router.prepareForAuthenticatedSession(identity, hasSeenOnboarding: true)

        XCTAssertEqual(router.selectedTab, .scanner)
    }

    func testLatestAuthenticatedDeepLinkReplacesAnOlderPendingRoute() throws {
        let router = AppRouter()
        let firstIdentity = AppAuthenticationIdentity.user(UUID())
        let secondIdentity = AppAuthenticationIdentity.user(UUID())
        let scannerURL = try XCTUnwrap(URL(string: "rocio://scanner"))
        let calendarURL = try XCTUnwrap(URL(string: "rocio://calendar"))

        router.prepareForAuthenticatedSession(firstIdentity, hasSeenOnboarding: true)
        router.beginAuthenticatedTransition(from: firstIdentity)
        router.route(scannerURL, authenticatedIdentity: nil)
        router.route(calendarURL, authenticatedIdentity: secondIdentity)
        router.prepareForAuthenticatedSession(secondIdentity, hasSeenOnboarding: true)

        XCTAssertEqual(router.selectedTab, .calendar)
    }

    func testAuthenticatedRouteDoesNotLeakIntoANewerLogin() throws {
        let router = AppRouter()
        let identity = AppAuthenticationIdentity.user(UUID())
        router.prepareForAuthenticatedSession(identity, hasSeenOnboarding: true)
        router.route(
            try XCTUnwrap(URL(string: "rocio://calendar")),
            authenticatedIdentity: identity
        )

        router.endAuthenticatedSession(identity)
        router.prepareForAuthenticatedSession(identity, hasSeenOnboarding: true)

        XCTAssertEqual(router.selectedTab, .garden)
    }

    func testLateSessionEndDoesNotEraseADeepLinkForTheNextLogin() throws {
        let router = AppRouter()
        let identity = AppAuthenticationIdentity.user(UUID())
        router.prepareForAuthenticatedSession(identity, hasSeenOnboarding: true)
        router.endAuthenticatedSession(identity)

        router.route(try XCTUnwrap(URL(string: "rocio://scanner")), authenticatedIdentity: nil)
        router.endAuthenticatedSession(identity)
        router.prepareForAuthenticatedSession(identity, hasSeenOnboarding: true)

        XCTAssertEqual(router.selectedTab, .scanner)
    }

    func testRestoredAuthenticatedSessionPreservesItsTabUnlessANewerRouteIsPending() throws {
        let router = AppRouter()
        let identity = AppAuthenticationIdentity.user(UUID())
        router.selectedTab = .settings

        router.restoreAuthenticatedSession(identity, hasSeenOnboarding: true)
        XCTAssertEqual(router.selectedTab, .settings)

        router.beginAuthenticatedTransition(from: identity)
        router.route(try XCTUnwrap(URL(string: "rocio://scanner")), authenticatedIdentity: nil)
        router.restoreAuthenticatedSession(identity, hasSeenOnboarding: true)
        XCTAssertEqual(router.selectedTab, .scanner)
    }

    func testSharedRouterRestoresOnlyTheSameAuthenticatedIdentityAfterRecovery() {
        let firstUser = AuthSession(
            accessToken: "first-access",
            refreshToken: "first-refresh",
            expiresAt: .distantFuture,
            user: AuthUser(id: UUID(), email: "first@example.com")
        )
        let secondUser = AuthSession(
            accessToken: "second-access",
            refreshToken: "second-refresh",
            expiresAt: .distantFuture,
            user: AuthUser(id: UUID(), email: "second@example.com")
        )
        let sameAccountRouter = AppRouter()
        sameAccountRouter.prepareForAuthenticatedSession(.user(firstUser.user.id), hasSeenOnboarding: true)
        sameAccountRouter.selectedTab = .settings
        sameAccountRouter.handleSessionTransition(
            from: .signedIn(firstUser),
            to: .checking,
            hasSeenOnboarding: true
        )
        sameAccountRouter.handleSessionTransition(
            from: .checking,
            to: .recoveringPassword(firstUser),
            hasSeenOnboarding: true
        )
        sameAccountRouter.handleSessionTransition(
            from: .recoveringPassword(firstUser),
            to: .checking,
            hasSeenOnboarding: true
        )
        sameAccountRouter.handleSessionTransition(
            from: .checking,
            to: .signedIn(firstUser),
            hasSeenOnboarding: true
        )
        // A second scene receives the same transition after the first one.
        sameAccountRouter.handleSessionTransition(
            from: .checking,
            to: .signedIn(firstUser),
            hasSeenOnboarding: true
        )
        XCTAssertEqual(sameAccountRouter.selectedTab, .settings)

        let crossAccountRouter = AppRouter()
        crossAccountRouter.prepareForAuthenticatedSession(.user(firstUser.user.id), hasSeenOnboarding: true)
        crossAccountRouter.selectedTab = .settings
        crossAccountRouter.handleSessionTransition(
            from: .signedIn(firstUser),
            to: .checking,
            hasSeenOnboarding: true
        )
        crossAccountRouter.handleSessionTransition(
            from: .checking,
            to: .signedIn(secondUser),
            hasSeenOnboarding: true
        )
        XCTAssertEqual(crossAccountRouter.selectedTab, .garden)

        // A second scene may replay the complete A -> B transition after the
        // first one already prepared B. It must not leave A suspended.
        crossAccountRouter.handleSessionTransition(
            from: .signedIn(firstUser),
            to: .checking,
            hasSeenOnboarding: true
        )
        crossAccountRouter.handleSessionTransition(
            from: .checking,
            to: .signedIn(secondUser),
            hasSeenOnboarding: true
        )
        crossAccountRouter.handleSessionTransition(
            from: .signedIn(secondUser),
            to: .signedOut,
            hasSeenOnboarding: true
        )
        crossAccountRouter.selectedTab = .settings
        crossAccountRouter.handleSessionTransition(
            from: .signedOut,
            to: .checking,
            hasSeenOnboarding: true
        )
        crossAccountRouter.handleSessionTransition(
            from: .checking,
            to: .signedIn(firstUser),
            hasSeenOnboarding: true
        )
        XCTAssertEqual(crossAccountRouter.selectedTab, .garden)
    }

    func testFirstCareFlowAddsPlantDismissesDetailRoutesToGardenAndAllowsFirstWatering() {
        let store = GardenStore(plants: [])
        let router = AppRouter()
        let flower = FlowerCatalog.all[0]
        let wateredAt = Date(timeIntervalSince1970: 1_800_000_000)
        var didDismiss = false

        FirstCareFlow.addToGarden(
            flower,
            gardenStore: store,
            router: router,
            dismiss: { didDismiss = true }
        )

        XCTAssertTrue(didDismiss)
        XCTAssertEqual(router.selectedTab, .garden)
        XCTAssertEqual(store.plants.map(\.flowerId), [flower.id])

        let firstPlant = store.plants[0]
        store.water(firstPlant, at: wateredAt)

        XCTAssertEqual(store.plants[0].lastWateredAt, wateredAt)
        XCTAssertEqual(store.plants[0].updatedAt, wateredAt)
    }

    func testAddAndWaterPlant() {
        let store = GardenStore(plants: [])
        let flower = FlowerCatalog.all[0]

        store.add(flower)
        XCTAssertEqual(store.plants.count, 1)

        let plant = store.plants[0]
        let newDate = Date(timeIntervalSince1970: 1_800_000_000)
        store.water(plant, at: newDate)

        XCTAssertEqual(store.plants[0].lastWateredAt, newDate)
    }

    func testUpdateNormalizesLocalPlantAndCloudUpsertPayload() {
        let original = GardenPlant(flowerId: "rosa", nickname: "Original")
        let store = GardenStore(plants: [original])
        var upsertedPlants: [GardenPlant] = []
        store.cloudChangeHandler = { change in
            guard case let .upsert(plant) = change else { return }
            upsertedPlants.append(plant)
        }
        let composedEmoji = "👨‍👩‍👧‍👦"
        let expectedNickname = String(repeating: composedEmoji, count: 11)
        let expectedNotes = String(repeating: composedEmoji, count: 285)
        XCTAssertEqual(composedEmoji.unicodeScalars.count, 7)

        store.update(
            original,
            nickname: "  \(String(repeating: composedEmoji, count: 12))\n",
            status: .needsSun,
            notes: String(repeating: composedEmoji, count: 286)
        )

        XCTAssertEqual(store.plants[0].nickname, expectedNickname)
        XCTAssertEqual(store.plants[0].nickname.unicodeScalars.count, 77)
        XCTAssertEqual(store.plants[0].status, .needsSun)
        XCTAssertEqual(store.plants[0].notes, expectedNotes)
        XCTAssertEqual(store.plants[0].notes.unicodeScalars.count, 1_995)
        XCTAssertEqual(upsertedPlants.count, 1)
        XCTAssertEqual(upsertedPlants[0].nickname, expectedNickname)
        XCTAssertEqual(upsertedPlants[0].status, .needsSun)
        XCTAssertEqual(upsertedPlants[0].notes, expectedNotes)

        store.update(
            original,
            nickname: " \n\t ",
            status: .healthy,
            notes: "Short note"
        )

        XCTAssertEqual(store.plants[0].nickname, expectedNickname)
        XCTAssertEqual(upsertedPlants.count, 2)
        XCTAssertEqual(upsertedPlants[1].nickname, expectedNickname)
    }

    func testReplaceFromCloudNormalizesLegacyTextBeforePersisting() {
        let composedEmoji = "👨‍👩‍👧‍👦"
        let nicknamePrefix = String(repeating: "n", count: 79)
        let notesPrefix = String(repeating: "x", count: 1_999)
        let legacyPlant = GardenPlant(
            flowerId: "rosa",
            nickname: nicknamePrefix + composedEmoji,
            notes: notesPrefix + composedEmoji
        )
        let store = GardenStore(plants: [legacyPlant])
        defer { GardenPersistence.clearPlants() }

        store.replaceFromCloud([legacyPlant])

        XCTAssertEqual(store.plants[0].nickname, nicknamePrefix)
        XCTAssertEqual(store.plants[0].notes, notesPrefix)
        XCTAssertEqual(GardenPersistence.loadPlants(), store.plants)
    }

    func testGardenSummaryCountsAttentionAndNextWatering() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 9))!
        let overdueDate = calendar.date(byAdding: .day, value: -5, to: now)!
        let freshDate = calendar.date(byAdding: .day, value: -1, to: now)!
        let plants = [
            GardenPlant(flowerId: "rosa", nickname: "Rosa", lastWateredAt: overdueDate),
            GardenPlant(flowerId: "lavanda", nickname: "Lavanda", lastWateredAt: freshDate)
        ]
        let store = GardenStore(plants: plants)

        let summary = store.summary(now: now)

        XCTAssertEqual(summary.plantCount, 2)
        XCTAssertEqual(summary.overdueCount, 1)
        XCTAssertEqual(summary.statusLabel, L10n.text("garden.summary.overdue", fallback: "Time to water"))
        XCTAssertEqual(summary.nextWateringDate, calendar.date(byAdding: .day, value: 3, to: overdueDate))
    }

    func testWateringScheduleSeparatesPlantOverdueByThreeDaysAndCountsIt() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9))!
        let lastWateredAt = calendar.date(byAdding: .day, value: -6, to: now)!
        let overduePlant = GardenPlant(flowerId: "rosa", nickname: "Rosa", lastWateredAt: lastWateredAt)
        let store = GardenStore(plants: [overduePlant])

        let schedule = store.wateringSchedule(startingAt: now, calendar: calendar)

        XCTAssertEqual(schedule.overduePlants.map(\.id), [overduePlant.id])
        XCTAssertTrue(schedule.days.allSatisfy(\.plants.isEmpty))
        XCTAssertEqual(schedule.totalDueCount, 1)
    }

    func testWateringSchedulePreservesTodayThroughNextSixDays() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9))!
        let dueToday = GardenPlant(
            flowerId: "rosa",
            nickname: "Rosa",
            lastWateredAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
        let dueOnLastVisibleDay = GardenPlant(
            flowerId: "orquidea",
            nickname: "Orquidea",
            lastWateredAt: calendar.date(byAdding: .day, value: -1, to: now)!
        )
        let dueOutsideVisibleRange = GardenPlant(
            flowerId: "orquidea",
            nickname: "Orquidea futura",
            lastWateredAt: now
        )
        let store = GardenStore(plants: [dueToday, dueOnLastVisibleDay, dueOutsideVisibleRange])

        let schedule = store.wateringSchedule(startingAt: now, calendar: calendar)

        XCTAssertEqual(schedule.days.count, 7)
        XCTAssertEqual(schedule.days[0].plants.map(\.id), [dueToday.id])
        XCTAssertEqual(schedule.days[6].plants.map(\.id), [dueOnLastVisibleDay.id])
        XCTAssertFalse(schedule.days.flatMap(\.plants).contains { $0.id == dueOutsideVisibleRange.id })
        XCTAssertEqual(schedule.totalDueCount, 2)
    }

    func testGardenExportPayloadContainsLocalData() {
        let exportedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let plant = GardenPlant(flowerId: "cempasuchil", nickname: "Cempasuchil")

        let payload = GardenExport.payload(plants: [plant], exportedAt: exportedAt)

        XCTAssertTrue(payload.contains("\"bundleIdentifier\" : \"com.juliosuas.rocio\""))
        XCTAssertTrue(payload.contains("\"flowerId\" : \"cempasuchil\""))
        XCTAssertTrue(payload.contains("\"plants\""))
    }

    func testResetClearsPlants() {
        let store = GardenStore(plants: [GardenPlant(flowerId: "rosa", nickname: "Rosa")])

        store.reset()

        XCTAssertTrue(store.plants.isEmpty)
    }

    func testDeleteAndResetEmitDatedCloudTombstones() {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Rosa")
        let deleteDate = Date(timeIntervalSince1970: 1_800_000_100)
        let resetDate = Date(timeIntervalSince1970: 1_800_000_200)
        let store = GardenStore(plants: [plant])
        var changes: [GardenChange] = []
        store.cloudChangeHandler = { changes.append($0) }

        store.delete(plant, at: deleteDate)
        store.reset(at: resetDate)

        XCTAssertEqual(changes.count, 2)
        guard case let .delete(deletedID, at: occurredAt) = changes[0] else {
            return XCTFail("Expected a dated plant tombstone")
        }
        XCTAssertEqual(deletedID, plant.id)
        XCTAssertEqual(occurredAt, deleteDate)

        guard case let .reset(at: occurredAt) = changes[1] else {
            return XCTFail("Expected a dated garden reset")
        }
        XCTAssertEqual(occurredAt, resetDate)
    }

    func testLocalDataResetClearsPlantsCancelsRemindersAndReportsLocalCompletion() async {
        let store = GardenStore(plants: [GardenPlant(flowerId: "rosa", nickname: "Rosa")])
        var didCancelPendingNotifications = false
        let resetter = LocalDataResetter {
            didCancelPendingNotifications = true
        }

        let status = await resetter.reset(gardenStore: store)

        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertTrue(didCancelPendingNotifications)
        XCTAssertEqual(status, .localOnly)
    }

    func testLocalDataResetNeverClaimsCloudDeletionBeforeConfirmation() async {
        let pendingStore = GardenStore(plants: [GardenPlant(flowerId: "rosa", nickname: "Rosa")])
        let confirmedStore = GardenStore(plants: [GardenPlant(flowerId: "lavanda", nickname: "Lavanda")])
        let resetter = LocalDataResetter(cancelPendingNotifications: {})

        let pendingStatus = await resetter.reset(
            gardenStore: pendingStore,
            waitForCloudConfirmation: { false }
        )
        let confirmedStatus = await resetter.reset(
            gardenStore: confirmedStore,
            waitForCloudConfirmation: { true }
        )

        XCTAssertEqual(pendingStatus, .cloudPending)
        XCTAssertEqual(confirmedStatus, .cloudConfirmed)
    }

    func testPendingDataResetBecomesConfirmedOnlyAfterCloudSyncCompletes() {
        XCTAssertEqual(
            GardenDataResetStatus.cloudPending.reconciled(with: .pending),
            .cloudPending
        )
        XCTAssertEqual(
            GardenDataResetStatus.cloudPending.reconciled(with: .syncing),
            .cloudPending
        )
        XCTAssertEqual(
            GardenDataResetStatus.cloudPending.reconciled(with: .synced),
            .cloudConfirmed
        )
    }

#if DEBUG
    func testDemoGardenIsEphemeralAndRestoresExistingPlants() {
        let existing = GardenPlant(flowerId: "girasol", nickname: "My sunflower")
        let store = GardenStore(plants: [existing])
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        store.beginDemo(now: now)

        XCTAssertTrue(store.isDemoMode)
        XCTAssertEqual(store.plants.count, 3)
        XCTAssertFalse(store.plants.contains(existing))

        store.water(store.plants[0], at: now)
        store.endDemo()

        XCTAssertFalse(store.isDemoMode)
        XCTAssertEqual(store.plants, [existing])
    }
#endif
}
