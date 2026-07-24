import XCTest
@testable import Rocio

private let gardenPersistenceOwnerID = UUID(
    uuidString: "A552206A-E21D-48E3-A88E-183483B7CA12"
)!

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

    func testAddManualPlantPreservesGenericIdentityWithoutCatalogID() {
        let store = GardenStore(plants: [])
        let identity = PlantIdentity(
            source: .manual,
            commonName: "Prayer plant",
            scientificName: "Maranta leuconeura",
            nameLocale: "en"
        )
        let careProfile = PlantCareProfile(
            wateringPreference: .medium,
            source: .manual
        )

        store.add(
            identity: identity,
            careProfile: careProfile,
            nickname: "Prayer plant"
        )

        XCTAssertEqual(store.plants.count, 1)
        XCTAssertNil(store.plants[0].flowerId)
        XCTAssertEqual(store.plants[0].identity, identity)
        XCTAssertEqual(store.plants[0].careProfile, careProfile)
    }

    func testLegacyRoseDecodesWithBundledIdentityCareAndOriginalSpecimenID() throws {
        let specimenID = UUID(uuidString: "4C96BD49-28D0-4BA7-BFE2-00178B30373F")!
        let addedAt = Date(timeIntervalSinceReferenceDate: 1_234)
        let legacyPlant = LegacyGardenPlantFixture(
            id: specimenID,
            flowerId: "rosa",
            nickname: "Patio rose",
            addedAt: addedAt,
            lastWateredAt: addedAt,
            status: .healthy,
            notes: "Inherited from version 1"
        )

        let decoded = try JSONDecoder().decode(
            GardenPlant.self,
            from: JSONEncoder().encode(legacyPlant)
        )

        XCTAssertEqual(decoded.id, specimenID)
        XCTAssertEqual(decoded.flowerId, "rosa")
        XCTAssertEqual(decoded.identity.source, .bundled)
        XCTAssertEqual(decoded.identity.sourceID, "rosa")
        XCTAssertEqual(decoded.identity.scientificName, "Rosa spp.")
        XCTAssertEqual(decoded.careProfile.source, .bundled)
        XCTAssertEqual(decoded.careProfile.wateringIntervalDays, 3)
        XCTAssertEqual(decoded.careProfile.waterAmountMl, 300)
        XCTAssertEqual(decoded.updatedAt, addedAt)
    }

    func testExternalMonsteraRoundTripKeepsProviderIdentityWithoutInventingExactCare() throws {
        let specimenID = UUID(uuidString: "31ED8C74-81FA-4DB8-A42C-4D168738CD33")!
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let plant = GardenPlant(
            id: specimenID,
            identity: PlantIdentity(
                source: .plantID,
                sourceID: "plant-id-monstera-deliciosa",
                commonName: "Swiss cheese plant",
                scientificName: "Monstera deliciosa",
                rank: "species",
                nameLocale: "en"
            ),
            careProfile: PlantCareProfile(
                wateringPreference: .medium,
                source: .plantID,
                fetchedAt: fetchedAt
            ),
            nickname: "Living room Monstera",
            addedAt: fetchedAt,
            lastWateredAt: fetchedAt,
            updatedAt: fetchedAt
        )

        let decoded = try JSONDecoder().decode(
            GardenPlant.self,
            from: JSONEncoder().encode(plant)
        )
        let store = GardenStore(plants: [decoded])

        XCTAssertEqual(decoded, plant)
        XCTAssertEqual(decoded.id, specimenID)
        XCTAssertNil(decoded.flowerId)
        XCTAssertEqual(decoded.identity.sourceID, "plant-id-monstera-deliciosa")
        XCTAssertEqual(decoded.identity.scientificName, "Monstera deliciosa")
        XCTAssertNil(decoded.careProfile.wateringIntervalDays)
        XCTAssertNil(decoded.careProfile.waterAmountMl)
        XCTAssertEqual(store.wateringIntervalDays(for: decoded), 7)
    }

    func testManualPlantRoundTripPreservesUserIdentityAndOptionalCare() throws {
        let specimenID = UUID(uuidString: "455FF867-86EA-4B9A-8BE8-46D27ED05CA7")!
        let createdAt = Date(timeIntervalSince1970: 1_800_000_100)
        let plant = GardenPlant(
            id: specimenID,
            identity: PlantIdentity(
                source: .manual,
                commonName: "Grandma's cutting",
                nameLocale: "en"
            ),
            careProfile: PlantCareProfile(
                source: .manual,
                fetchedAt: createdAt
            ),
            addedAt: createdAt,
            lastWateredAt: createdAt,
            updatedAt: createdAt
        )

        let decoded = try JSONDecoder().decode(
            GardenPlant.self,
            from: JSONEncoder().encode(plant)
        )

        XCTAssertEqual(decoded, plant)
        XCTAssertEqual(decoded.id, specimenID)
        XCTAssertEqual(decoded.nickname, "Grandma's cutting")
        XCTAssertEqual(decoded.identity.source, .manual)
        XCTAssertNil(decoded.identity.sourceID)
        XCTAssertNil(decoded.identity.scientificName)
        XCTAssertNil(decoded.careProfile.wateringIntervalDays)
        XCTAssertNil(decoded.careProfile.reminderIntervalDays)

        let store = GardenStore(plants: [decoded])
        XCTAssertNil(store.wateringIntervalDays(for: decoded))
        XCTAssertNil(store.urgency(for: decoded))
        XCTAssertNil(store.nextWateringDate(for: decoded))
        XCTAssertEqual(store.wateringSchedule().totalDueCount, 0)
        XCTAssertNil(store.summary().nextWateringDate)
        XCTAssertEqual(store.summary().unscheduledCount, 1)
        XCTAssertEqual(
            store.summary().statusLabel,
            L10n.text("garden.summary.unscheduled", fallback: "Set care schedule")
        )
    }

    func testArbitraryPlantFieldsNormalizeToCloudContractBeforeSave() throws {
        let longName = "  " + String(repeating: "n", count: 220) + "  "
        let store = GardenStore(plants: [])

        let saved = try XCTUnwrap(store.add(
            identity: PlantIdentity(
                source: .manual,
                sourceID: "   ",
                commonName: longName,
                scientificName: String(repeating: "s", count: 220),
                rank: String(repeating: "r", count: 90),
                nameLocale: String(repeating: "l", count: 40)
            ),
            careProfile: PlantCareProfile(
                wateringIntervalDays: 0,
                waterAmountMl: 20_000,
                source: .manual
            )
        ))

        XCTAssertNil(saved.identity.sourceID)
        XCTAssertEqual(saved.identity.commonName.unicodeScalars.count, 200)
        XCTAssertEqual(saved.identity.scientificName?.unicodeScalars.count, 200)
        XCTAssertEqual(saved.identity.rank?.unicodeScalars.count, 80)
        XCTAssertEqual(saved.identity.nameLocale?.unicodeScalars.count, 32)
        XCTAssertNil(saved.careProfile.wateringIntervalDays)
        XCTAssertNil(saved.careProfile.waterAmountMl)
        XCTAssertEqual(store.plants, [saved])
        XCTAssertNil(
            PlantIdentity(source: .manual, commonName: "Aloe", nameLocale: "x")
                .normalized()
                .nameLocale
        )
    }

    func testAddingTheSameSpeciesCreatesIndependentSpecimens() throws {
        let store = GardenStore(plants: [])
        let rose = try XCTUnwrap(FlowerCatalog.flower(id: "rosa"))

        store.add(rose)
        store.add(rose)

        XCTAssertEqual(store.plants.count, 2)
        XCTAssertEqual(Set(store.plants.map(\.id)).count, 2)
        XCTAssertEqual(store.plants.map(\.flowerId), ["rosa", "rosa"])
        XCTAssertTrue(store.plants.allSatisfy { $0.identity.sourceID == "rosa" })
    }

    func testVersionedPersistenceRecoversCorruptPrimaryFromLastKnownGoodBackup() throws {
        let suiteName = "GardenStoreTests.primary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(CoordinatedUserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let plant = GardenPlant(flowerId: "rosa", nickname: "Backup rose")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [plant],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
        )
        defaults.set(Data("corrupt-primary".utf8), forKey: GardenPersistence.plantsKey)

        let result = GardenPersistence.loadSnapshot(
            ownerID: gardenPersistenceOwnerID,
            defaults: defaults
        )

        XCTAssertEqual(result.status, .recoveredFromBackup)
        XCTAssertEqual(result.plants, [plant])
        XCTAssertEqual(
            defaults.data(forKey: GardenPersistence.plantsKey),
            defaults.data(forKey: GardenPersistence.backupPlantsKey)
        )

        let selectedOldData = try XCTUnwrap(
            defaults.data(forKey: GardenPersistence.backupPlantsKey)
        )
        let newerPlant = GardenPlant(flowerId: "lavanda", nickname: "Concurrent save")
        defaults.set(
            Data("corrupt-primary-again".utf8),
            forKey: GardenPersistence.plantsKey
        )
        defaults.blockNextSet(
            data: selectedOldData,
            forKey: GardenPersistence.plantsKey
        )
        let loaderFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = GardenPersistence.loadSnapshot(
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
            loaderFinished.signal()
        }
        XCTAssertEqual(
            defaults.didReachBlockedSet.wait(timeout: .now() + 2),
            .success
        )

        let saverFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = GardenPersistence.savePlants(
                [newerPlant],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
            saverFinished.signal()
        }
        XCTAssertEqual(
            saverFinished.wait(timeout: .now() + 0.1),
            .timedOut,
            "A save must wait while recovery holds the persistence transaction."
        )

        defaults.allowBlockedSet.signal()
        XCTAssertEqual(loaderFinished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(saverFinished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(
            GardenPersistence.loadSnapshot(
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            ).plants,
            [newerPlant]
        )
    }

    func testVersionedPersistenceKeepsValidPrimaryWhenBackupIsCorrupt() throws {
        let suiteName = "GardenStoreTests.backup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let plant = GardenPlant(flowerId: "lavanda", nickname: "Primary lavender")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [plant],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
        )
        defaults.set(Data("corrupt-backup".utf8), forKey: GardenPersistence.backupPlantsKey)

        let result = GardenPersistence.loadSnapshot(
            ownerID: gardenPersistenceOwnerID,
            defaults: defaults
        )

        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.plants, [plant])
        XCTAssertEqual(
            defaults.data(forKey: GardenPersistence.plantsKey),
            defaults.data(forKey: GardenPersistence.backupPlantsKey)
        )
    }

    func testVersionedPersistenceChoosesNewerBackupGenerationAfterInterruptedWrite() throws {
        let suiteName = "GardenStoreTests.newer-backup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldPlant = GardenPlant(flowerId: "rosa", nickname: "Old rose")
        let newestPlant = GardenPlant(flowerId: "rosa", nickname: "Newest rose")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [oldPlant],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
        )
        let oldSnapshot = try XCTUnwrap(defaults.data(forKey: GardenPersistence.plantsKey))
        XCTAssertTrue(
            GardenPersistence.savePlants(
                [newestPlant],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
        )
        let newestSnapshot = try XCTUnwrap(defaults.data(forKey: GardenPersistence.backupPlantsKey))
        defaults.set(oldSnapshot, forKey: GardenPersistence.plantsKey)

        let result = GardenPersistence.loadSnapshot(
            ownerID: gardenPersistenceOwnerID,
            defaults: defaults
        )

        XCTAssertEqual(result.status, .recoveredFromBackup)
        XCTAssertEqual(result.plants, [newestPlant])
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.plantsKey), newestSnapshot)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.backupPlantsKey), newestSnapshot)
    }

    func testLegacyPrimaryFromOlderBuildStaysQuarantinedWithoutOverwritingBackup() throws {
        let suiteName = "GardenStoreTests.mixed-version.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let stalePlant = GardenPlant(flowerId: "rosa", nickname: "Before downgrade")
        let newerLegacyPlant = GardenPlant(flowerId: "rosa", nickname: "Edited by older build")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [stalePlant],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
        )
        let staleBackup = try XCTUnwrap(
            defaults.data(forKey: GardenPersistence.backupPlantsKey)
        )
        let legacyPrimary = try JSONEncoder().encode([newerLegacyPlant])
        defaults.set(
            legacyPrimary,
            forKey: GardenPersistence.plantsKey
        )

        let result = GardenPersistence.loadSnapshot(
            ownerID: gardenPersistenceOwnerID,
            defaults: defaults
        )

        XCTAssertEqual(result.status, .unownedSnapshot)
        XCTAssertTrue(result.plants.isEmpty)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.plantsKey), legacyPrimary)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.backupPlantsKey), staleBackup)
    }

    func testArchivedOwnerSnapshotDoesNotOverwriteNewerUnownedLegacyData() throws {
        let suiteName = "GardenStoreTests.archive-legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstPlant = GardenPlant(flowerId: "rosa", nickname: "Archived account A rose")
        let secondPlant = GardenPlant(flowerId: "lavanda", nickname: "Account B lavender")
        let newerLegacyPlant = GardenPlant(
            flowerId: "orquidea",
            nickname: "Edited by an older build"
        )

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [firstPlant],
                ownerID: firstOwner,
                defaults: defaults
            )
        )
        XCTAssertTrue(
            GardenPersistence.savePlants(
                [secondPlant],
                ownerID: secondOwner,
                defaults: defaults,
                allowsCorruptionRecovery: true
            )
        )
        let secondOwnerBackup = try XCTUnwrap(
            defaults.data(forKey: GardenPersistence.backupPlantsKey)
        )
        let firstOwnerArchivePrefix =
            "rocio.ios.garden.archived.\(firstOwner.uuidString.lowercased())."
        let firstOwnerArchiveKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(firstOwnerArchivePrefix)
        }
        XCTAssertEqual(firstOwnerArchiveKeys.count, 1)

        let legacyPrimary = try JSONEncoder().encode([newerLegacyPlant])
        defaults.set(legacyPrimary, forKey: GardenPersistence.plantsKey)

        let result = GardenPersistence.loadSnapshot(
            ownerID: firstOwner,
            defaults: defaults
        )

        XCTAssertEqual(result.status, .unownedSnapshot)
        XCTAssertTrue(result.plants.isEmpty)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.plantsKey), legacyPrimary)
        XCTAssertEqual(
            defaults.data(forKey: GardenPersistence.backupPlantsKey),
            secondOwnerBackup
        )
        XCTAssertEqual(
            defaults.dictionaryRepresentation().keys.filter {
                $0.hasPrefix(firstOwnerArchivePrefix)
            }.count,
            1
        )
    }

    func testFuturePrimarySchemaFailsClosedWithoutOverwritingEitherCopy() throws {
        let suiteName = "GardenStoreTests.future-schema.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let currentPlant = GardenPlant(flowerId: "lavanda", nickname: "Current backup")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [currentPlant],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
        )
        let backup = try XCTUnwrap(defaults.data(forKey: GardenPersistence.backupPlantsKey))
        let futurePrimary = Data(#"{"schemaVersion":999,"futureData":"preserve"}"#.utf8)
        defaults.set(futurePrimary, forKey: GardenPersistence.plantsKey)

        let result = GardenPersistence.loadSnapshot(
            ownerID: gardenPersistenceOwnerID,
            defaults: defaults
        )

        XCTAssertEqual(result.status, .unrecoverableCorruption)
        XCTAssertTrue(result.plants.isEmpty)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.plantsKey), futurePrimary)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.backupPlantsKey), backup)
        XCTAssertFalse(
            GardenPersistence.savePlants(
                [GardenPlant(flowerId: "rosa", nickname: "Must not overwrite")],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
        )
        XCTAssertEqual(
            GardenPersistence.updatePlant(
                id: currentPlant.id,
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            ) {
                $0.nickname = "Must not mutate"
            },
            .persistenceFailure
        )
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.plantsKey), futurePrimary)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.backupPlantsKey), backup)
    }

    func testCloudReplacementRollsBackWhenAuthoritativePersistenceFails() {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let ownerID = UUID()
        let futurePrimary = Data(#"{"schemaVersion":999,"futureData":"preserve"}"#.utf8)
        UserDefaults.standard.set(futurePrimary, forKey: GardenPersistence.plantsKey)
        let store = GardenStore()
        store.activatePersistence(for: ownerID)
        let statusBeforeReplacement = store.persistenceStatus
        let remotePlant = GardenPlant(flowerId: "rosa", nickname: "Cloud rose")

        XCTAssertFalse(store.replaceFromCloud([remotePlant]))

        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertEqual(store.persistenceStatus, statusBeforeReplacement)
        XCTAssertEqual(
            UserDefaults.standard.data(forKey: GardenPersistence.plantsKey),
            futurePrimary
        )
    }

    func testVersionedPersistenceReportsWhenBothSnapshotsAreCorrupt() throws {
        let suiteName = "GardenStoreTests.both.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("corrupt-primary".utf8), forKey: GardenPersistence.plantsKey)
        defaults.set(Data("corrupt-backup".utf8), forKey: GardenPersistence.backupPlantsKey)

        let result = GardenPersistence.loadSnapshot(
            ownerID: gardenPersistenceOwnerID,
            defaults: defaults
        )

        XCTAssertEqual(result.status, .unrecoverableCorruption)
        XCTAssertTrue(result.plants.isEmpty)
    }

    func testNormalSaveDoesNotOverwriteTwoUnreadableSnapshots() throws {
        let suiteName = "GardenStoreTests.preserve-corruption.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let primary = Data("future-primary".utf8)
        let backup = Data("future-backup".utf8)
        defaults.set(primary, forKey: GardenPersistence.plantsKey)
        defaults.set(backup, forKey: GardenPersistence.backupPlantsKey)

        XCTAssertFalse(
            GardenPersistence.savePlants(
                [GardenPlant(flowerId: "rosa", nickname: "Must not overwrite")],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
        )
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.plantsKey), primary)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.backupPlantsKey), backup)
    }

    func testExplicitCloudRecoveryCanReplaceTwoUnreadableSnapshots() throws {
        let suiteName = "GardenStoreTests.cloud-recovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let plant = GardenPlant(flowerId: "rosa", nickname: "Recovered from cloud")
        defaults.set(Data("corrupt-primary".utf8), forKey: GardenPersistence.plantsKey)
        defaults.set(Data("corrupt-backup".utf8), forKey: GardenPersistence.backupPlantsKey)

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [plant],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults,
                allowsCorruptionRecovery: true
            )
        )
        XCTAssertEqual(
            GardenPersistence.loadSnapshot(
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            ).plants,
            [plant]
        )
    }

    func testPersistenceWritesCurrentSchemaVersion() throws {
        let suiteName = "GardenStoreTests.version.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [GardenPlant(flowerId: "rosa", nickname: "Versioned rose")],
                ownerID: gardenPersistenceOwnerID,
                defaults: defaults
            )
        )
        let data = try XCTUnwrap(defaults.data(forKey: GardenPersistence.plantsKey))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["schemaVersion"] as? Int, GardenPersistence.currentSchemaVersion)
        XCTAssertEqual(json["ownerID"] as? String, gardenPersistenceOwnerID.uuidString)
    }

    func testOwnerBoundSnapshotRejectsAnotherAccountWithoutChangingSavedData() throws {
        let suiteName = "GardenStoreTests.owner-mismatch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstOwner = UUID()
        let secondOwner = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Private rose")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [plant],
                ownerID: firstOwner,
                defaults: defaults
            )
        )
        let primaryBeforeMismatch = defaults.data(forKey: GardenPersistence.plantsKey)
        let mismatch = GardenPersistence.loadSnapshot(
            ownerID: secondOwner,
            defaults: defaults
        )

        XCTAssertEqual(mismatch.status, .ownerMismatch)
        XCTAssertTrue(mismatch.plants.isEmpty)
        XCTAssertEqual(
            GardenPersistence.updatePlant(
                id: plant.id,
                ownerID: secondOwner,
                defaults: defaults
            ) {
                $0.nickname = "Leaked"
            },
            .persistenceFailure
        )
        XCTAssertEqual(
            defaults.data(forKey: GardenPersistence.plantsKey),
            primaryBeforeMismatch
        )
        XCTAssertEqual(
            GardenPersistence.loadPlants(ownerID: firstOwner, defaults: defaults),
            [plant]
        )
    }

    func testOwnerlessVersionTwoSnapshotStaysQuarantinedForEveryAccount() throws {
        let suiteName = "GardenStoreTests.ownerless.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previousOwner = UUID()
        let otherOwner = UUID()
        let plant = GardenPlant(flowerId: "lavanda", nickname: "Legacy lavender")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [plant],
                ownerID: previousOwner,
                defaults: defaults
            )
        )
        let currentData = try XCTUnwrap(defaults.data(forKey: GardenPersistence.plantsKey))
        var ownerlessJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        ownerlessJSON["schemaVersion"] = 2
        ownerlessJSON.removeValue(forKey: "ownerID")
        let ownerlessData = try JSONSerialization.data(withJSONObject: ownerlessJSON)
        defaults.set(ownerlessData, forKey: GardenPersistence.plantsKey)
        defaults.set(ownerlessData, forKey: GardenPersistence.backupPlantsKey)

        let firstRead = GardenPersistence.loadSnapshot(
            ownerID: previousOwner,
            defaults: defaults
        )
        let secondRead = GardenPersistence.loadSnapshot(
            ownerID: otherOwner,
            defaults: defaults
        )

        XCTAssertEqual(firstRead.status, .unownedSnapshot)
        XCTAssertTrue(firstRead.plants.isEmpty)
        XCTAssertEqual(secondRead.status, .unownedSnapshot)
        XCTAssertTrue(secondRead.plants.isEmpty)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.plantsKey), ownerlessData)
        XCTAssertEqual(
            defaults.data(forKey: GardenPersistence.backupPlantsKey),
            ownerlessData
        )
    }

    func testOwnerlessVersionThreeSnapshotIsUnrecoverableAndPreserved() throws {
        let suiteName = "GardenStoreTests.ownerless-v3.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ownerID = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Invalid v3 rose")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [plant],
                ownerID: ownerID,
                defaults: defaults
            )
        )
        let currentData = try XCTUnwrap(defaults.data(forKey: GardenPersistence.plantsKey))
        var ownerlessJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        ownerlessJSON.removeValue(forKey: "ownerID")
        let ownerlessData = try JSONSerialization.data(withJSONObject: ownerlessJSON)
        defaults.set(ownerlessData, forKey: GardenPersistence.plantsKey)
        defaults.set(ownerlessData, forKey: GardenPersistence.backupPlantsKey)

        let result = GardenPersistence.loadSnapshot(ownerID: ownerID, defaults: defaults)

        XCTAssertEqual(result.status, .unrecoverableCorruption)
        XCTAssertTrue(result.plants.isEmpty)
        XCTAssertFalse(GardenPersistence.clearPlants(ownerID: ownerID, defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.plantsKey), ownerlessData)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.backupPlantsKey), ownerlessData)
    }

    func testCloudRecoveryQuarantinesInvalidSiblingWithoutLosingValidOwnerSnapshot() throws {
        let suiteName = "GardenStoreTests.mixed-invalid-owner.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstPlant = GardenPlant(flowerId: "rosa", nickname: "Account A rose")
        let secondPlant = GardenPlant(flowerId: "lavanda", nickname: "Account B lavender")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [firstPlant],
                ownerID: firstOwner,
                defaults: defaults
            )
        )
        let validFirstOwnerData = try XCTUnwrap(
            defaults.data(forKey: GardenPersistence.plantsKey)
        )
        var invalidJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validFirstOwnerData) as? [String: Any]
        )
        invalidJSON.removeValue(forKey: "ownerID")
        let invalidData = try JSONSerialization.data(withJSONObject: invalidJSON)
        defaults.set(invalidData, forKey: GardenPersistence.backupPlantsKey)

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [secondPlant],
                ownerID: secondOwner,
                defaults: defaults,
                allowsCorruptionRecovery: true
            )
        )
        XCTAssertEqual(
            GardenPersistence.loadPlants(ownerID: secondOwner, defaults: defaults),
            [secondPlant]
        )
        XCTAssertTrue(
            defaults.dictionaryRepresentation().contains {
                $0.key.hasPrefix("rocio.ios.garden.quarantine.corrupt.")
                    && ($0.value as? Data) == invalidData
            }
        )

        XCTAssertEqual(
            GardenPersistence.loadPlants(ownerID: firstOwner, defaults: defaults),
            [firstPlant]
        )
        XCTAssertEqual(
            GardenPersistence.loadPlants(ownerID: secondOwner, defaults: defaults),
            [secondPlant]
        )
    }

    func testCloudRecoveryQuarantinesLegacySiblingWithoutLosingValidOwnerSnapshot() throws {
        let suiteName = "GardenStoreTests.mixed-legacy-owner.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstPlant = GardenPlant(flowerId: "rosa", nickname: "Account A rose")
        let secondPlant = GardenPlant(flowerId: "lavanda", nickname: "Account B lavender")
        let legacyPlant = GardenPlant(flowerId: "orquidea", nickname: "Legacy orchid")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [firstPlant],
                ownerID: firstOwner,
                defaults: defaults
            )
        )
        let legacyData = try JSONEncoder().encode([legacyPlant])
        defaults.set(legacyData, forKey: GardenPersistence.backupPlantsKey)

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [secondPlant],
                ownerID: secondOwner,
                defaults: defaults,
                allowsCorruptionRecovery: true
            )
        )
        XCTAssertEqual(
            GardenPersistence.loadPlants(ownerID: secondOwner, defaults: defaults),
            [secondPlant]
        )
        XCTAssertTrue(
            defaults.dictionaryRepresentation().contains {
                $0.key.hasPrefix("rocio.ios.garden.quarantine.legacy.")
                    && ($0.value as? Data) == legacyData
            }
        )

        XCTAssertEqual(
            GardenPersistence.loadPlants(ownerID: firstOwner, defaults: defaults),
            [firstPlant]
        )
        XCTAssertEqual(
            GardenPersistence.loadPlants(ownerID: secondOwner, defaults: defaults),
            [secondPlant]
        )
    }

    func testOwnerScopedPrivacyPurgeRemovesUnsafeAndCurrentOwnerDataButPreservesAnotherOwner() throws {
        let suiteName = "GardenStoreTests.owner-scoped-purge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstOwner = UUID()
        let deletedOwner = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Private rose")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [plant],
                ownerID: deletedOwner,
                defaults: defaults
            )
        )
        let deletedOwnerData = try XCTUnwrap(
            defaults.data(forKey: GardenPersistence.plantsKey)
        )
        var firstOwnerJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: deletedOwnerData) as? [String: Any]
        )
        firstOwnerJSON["ownerID"] = firstOwner.uuidString
        let firstOwnerData = try JSONSerialization.data(withJSONObject: firstOwnerJSON)
        let firstOwnerArchiveKey =
            "rocio.ios.garden.archived.\(firstOwner.uuidString.lowercased()).keep"
        let deletedOwnerArchiveKey =
            "rocio.ios.garden.archived.\(deletedOwner.uuidString.lowercased()).delete"
        defaults.set(firstOwnerData, forKey: firstOwnerArchiveKey)
        defaults.set(deletedOwnerData, forKey: deletedOwnerArchiveKey)

        var invalidV3JSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: deletedOwnerData) as? [String: Any]
        )
        invalidV3JSON.removeValue(forKey: "ownerID")
        let invalidV3Data = try JSONSerialization.data(withJSONObject: invalidV3JSON)
        var ownerlessV2JSON = invalidV3JSON
        ownerlessV2JSON["schemaVersion"] = 2
        let ownerlessV2Data = try JSONSerialization.data(withJSONObject: ownerlessV2JSON)
        defaults.set(invalidV3Data, forKey: GardenPersistence.plantsKey)
        defaults.set(ownerlessV2Data, forKey: GardenPersistence.backupPlantsKey)
        defaults.set(
            Data("legacy quarantine".utf8),
            forKey: "rocio.ios.garden.quarantine.legacy.test"
        )
        defaults.set(
            Data("corrupt quarantine".utf8),
            forKey: "rocio.ios.garden.quarantine.corrupt.test"
        )

        XCTAssertTrue(
            GardenPersistence.purgeGardenData(
                ownerID: deletedOwner,
                defaults: defaults
            )
        )

        XCTAssertNil(defaults.data(forKey: GardenPersistence.plantsKey))
        XCTAssertNil(defaults.data(forKey: GardenPersistence.backupPlantsKey))
        XCTAssertNil(defaults.data(forKey: deletedOwnerArchiveKey))
        XCTAssertEqual(defaults.data(forKey: firstOwnerArchiveKey), firstOwnerData)
        XCTAssertFalse(
            defaults.dictionaryRepresentation().keys.contains {
                $0.hasPrefix("rocio.ios.garden.quarantine.")
            }
        )
    }

    func testOwnerScopedPrivacyPurgeRemovesFutureSchemaDataAndPreservesAnotherOwner() throws {
        let suiteName = "GardenStoreTests.future-schema-purge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preservedOwner = UUID()
        let deletedOwner = UUID()
        let preservedPlant = GardenPlant(flowerId: "rosa", nickname: "Preserved rose")

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [preservedPlant],
                ownerID: preservedOwner,
                defaults: defaults
            )
        )
        let preservedData = try XCTUnwrap(
            defaults.data(forKey: GardenPersistence.plantsKey)
        )
        let preservedArchiveKey =
            "rocio.ios.garden.archived.\(preservedOwner.uuidString.lowercased()).keep"
        defaults.set(preservedData, forKey: preservedArchiveKey)
        defaults.set(
            Data(#"{"schemaVersion":999,"futureData":"primary"}"#.utf8),
            forKey: GardenPersistence.plantsKey
        )
        defaults.set(
            Data(#"{"schemaVersion":999,"futureData":"backup"}"#.utf8),
            forKey: GardenPersistence.backupPlantsKey
        )

        XCTAssertTrue(
            GardenPersistence.purgeGardenData(
                ownerID: deletedOwner,
                defaults: defaults
            )
        )

        XCTAssertNil(defaults.data(forKey: GardenPersistence.plantsKey))
        XCTAssertNil(defaults.data(forKey: GardenPersistence.backupPlantsKey))
        XCTAssertEqual(defaults.data(forKey: preservedArchiveKey), preservedData)
    }

    func testOwnerScopedPrivacyPurgePreservesFutureSchemaDataOwnedByAnotherAccount() throws {
        let suiteName = "GardenStoreTests.other-owner-future-schema.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preservedOwner = UUID()
        let deletedOwner = UUID()
        let futureData = Data(
            """
            {"schemaVersion":999,"ownerID":"\(preservedOwner.uuidString)","futureData":"keep"}
            """.utf8
        )
        defaults.set(futureData, forKey: GardenPersistence.plantsKey)
        defaults.set(futureData, forKey: GardenPersistence.backupPlantsKey)

        XCTAssertTrue(
            GardenPersistence.purgeGardenData(
                ownerID: deletedOwner,
                defaults: defaults
            )
        )

        XCTAssertEqual(defaults.data(forKey: GardenPersistence.plantsKey), futureData)
        XCTAssertEqual(defaults.data(forKey: GardenPersistence.backupPlantsKey), futureData)
    }

    func testAuthenticatedIntentPersistenceRequiresMatchingSessionOwner() throws {
        let suiteName = "GardenStoreTests.intent-owner.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ownerID = UUID()
        let otherOwnerID = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Siri rose")
        let session: (UUID) -> AuthSession = { userID in
            AuthSession(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: .distantFuture,
                user: AuthUser(id: userID, email: "gardener@example.com")
            )
        }

        XCTAssertTrue(
            GardenPersistence.savePlants(
                [plant],
                ownerID: ownerID,
                defaults: defaults
            )
        )
        XCTAssertTrue(
            GardenPersistence.loadPlantsForAuthenticatedSession(
                defaults: defaults,
                sessionLoader: { nil }
            ).isEmpty
        )
        XCTAssertTrue(
            GardenPersistence.loadPlantsForAuthenticatedSession(
                defaults: defaults,
                sessionLoader: { session(otherOwnerID) }
            ).isEmpty
        )
        XCTAssertEqual(
            GardenPersistence.updatePlantForAuthenticatedSession(
                id: plant.id,
                defaults: defaults,
                sessionLoader: { session(otherOwnerID) }
            ) {
                $0.nickname = "Wrong owner"
            },
            .persistenceFailure
        )

        let updated = GardenPersistence.updatePlantForAuthenticatedSession(
            id: plant.id,
            defaults: defaults,
            sessionLoader: { session(ownerID) }
        ) {
            $0.nickname = "Watered by owner"
        }
        guard case let .updated(updatedPlant) = updated else {
            return XCTFail("The matching authenticated owner should be able to update.")
        }
        XCTAssertEqual(updatedPlant.nickname, "Watered by owner")
        XCTAssertEqual(
            GardenPersistence.loadPlants(ownerID: ownerID, defaults: defaults),
            [updatedPlant]
        )
    }

    @MainActor
    func testBootstrapWithoutSavedSessionHidesButPreservesOwnedSnapshot() async {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let ownerID = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Hidden rose")
        XCTAssertTrue(GardenPersistence.savePlants([plant], ownerID: ownerID))
        let gardenStore = GardenStore()
        let sessionStore = SessionStore(
            configuration: BackendConfiguration(
                baseURL: URL(string: "https://example.supabase.co")!,
                anonymousKey: "public-key"
            ),
            sessionPersistence: SessionPersistence(
                load: { nil },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 }
        )

        await sessionStore.bootstrap(gardenStore: gardenStore)

        XCTAssertEqual(sessionStore.state, .signedOut)
        XCTAssertNil(gardenStore.persistenceOwnerID)
        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertEqual(GardenPersistence.loadPlants(ownerID: ownerID), [plant])
    }

    @MainActor
    func testPersistedSessionKeepsOwnerlessVersionTwoSnapshotQuarantinedAcrossOfflineRelaunch() async throws {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let legacyOwnerID = UUID()
        let sessionOwnerID = UUID()
        let plant = GardenPlant(flowerId: "lavanda", nickname: "Quarantined lavender")
        XCTAssertTrue(GardenPersistence.savePlants([plant], ownerID: legacyOwnerID))
        let currentData = try XCTUnwrap(
            UserDefaults.standard.data(forKey: GardenPersistence.plantsKey)
        )
        var ownerlessJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        ownerlessJSON["schemaVersion"] = 2
        ownerlessJSON.removeValue(forKey: "ownerID")
        let ownerlessData = try JSONSerialization.data(withJSONObject: ownerlessJSON)
        UserDefaults.standard.set(ownerlessData, forKey: GardenPersistence.plantsKey)
        UserDefaults.standard.set(ownerlessData, forKey: GardenPersistence.backupPlantsKey)
        let savedSession = AuthSession(
            accessToken: "expired",
            refreshToken: "refresh",
            expiresAt: .distantPast,
            user: AuthUser(id: sessionOwnerID, email: "account-b@example.com")
        )

        for _ in 0..<2 {
            let gardenStore = GardenStore()
            let sessionStore = SessionStore(
                configuration: BackendConfiguration(
                    baseURL: URL(string: "https://example.supabase.co")!,
                    anonymousKey: "public-key"
                ),
                sessionPersistence: SessionPersistence(
                    load: { savedSession },
                    save: { _ in },
                    clear: {}
                ),
                refreshSession: { _ in throw URLError(.notConnectedToInternet) }
            )

            await sessionStore.bootstrap(gardenStore: gardenStore)

            XCTAssertEqual(sessionStore.state, .signedIn(savedSession))
            XCTAssertEqual(gardenStore.persistenceOwnerID, sessionOwnerID)
            XCTAssertEqual(gardenStore.persistenceStatus, .unownedSnapshot)
            XCTAssertTrue(gardenStore.plants.isEmpty)
            XCTAssertFalse(gardenStore.canAcceptLocalChanges)
            XCTAssertFalse(
                gardenStore.add(
                    GardenPlant(flowerId: "rosa", nickname: "Must stay blocked")
                )
            )
            XCTAssertEqual(
                UserDefaults.standard.data(forKey: GardenPersistence.plantsKey),
                ownerlessData
            )
            XCTAssertEqual(
                UserDefaults.standard.data(forKey: GardenPersistence.backupPlantsKey),
                ownerlessData
            )
        }
    }

    func testDifferentAccountActivationAndLocalClearPreserveExistingOwnersSnapshot() {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let firstOwner = UUID()
        let secondOwner = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Account A rose")
        XCTAssertTrue(GardenPersistence.savePlants([plant], ownerID: firstOwner))
        let primaryBefore = UserDefaults.standard.data(forKey: GardenPersistence.plantsKey)
        let backupBefore = UserDefaults.standard.data(forKey: GardenPersistence.backupPlantsKey)
        let gardenStore = GardenStore()

        gardenStore.activatePersistence(for: secondOwner)

        XCTAssertEqual(gardenStore.persistenceOwnerID, secondOwner)
        XCTAssertEqual(gardenStore.persistenceStatus, .ownerMismatch)
        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertFalse(gardenStore.canAcceptLocalChanges)
        XCTAssertFalse(
            gardenStore.add(
                GardenPlant(flowerId: "lavanda", nickname: "Account B lavender")
            )
        )

        gardenStore.clearLocalCache()

        XCTAssertNil(gardenStore.persistenceOwnerID)
        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertEqual(UserDefaults.standard.data(forKey: GardenPersistence.plantsKey), primaryBefore)
        XCTAssertEqual(UserDefaults.standard.data(forKey: GardenPersistence.backupPlantsKey), backupBefore)
        XCTAssertEqual(GardenPersistence.loadPlants(ownerID: firstOwner), [plant])
    }

    func testRefreshReturningAnotherUserSignsOutAndPreservesOriginalOwnersSnapshot() async {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let firstOwner = UUID()
        let secondOwner = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Original account rose")
        XCTAssertTrue(GardenPersistence.savePlants([plant], ownerID: firstOwner))
        let primaryBefore = UserDefaults.standard.data(forKey: GardenPersistence.plantsKey)
        let backupBefore = UserDefaults.standard.data(forKey: GardenPersistence.backupPlantsKey)
        let savedSession = AuthSession(
            accessToken: "expired-a",
            refreshToken: "refresh-a",
            expiresAt: .distantPast,
            user: AuthUser(id: firstOwner, email: "account-a@example.com")
        )
        let wrongSession = AuthSession(
            accessToken: "access-b",
            refreshToken: "refresh-b",
            expiresAt: .distantFuture,
            user: AuthUser(id: secondOwner, email: "account-b@example.com")
        )
        var didClearSession = false
        let gardenStore = GardenStore()
        let sessionStore = SessionStore(
            configuration: BackendConfiguration(
                baseURL: URL(string: "https://example.supabase.co")!,
                anonymousKey: "public-key"
            ),
            sessionPersistence: SessionPersistence(
                load: { savedSession },
                save: { _ in XCTFail("A mismatched refresh must never be persisted.") },
                clear: { didClearSession = true }
            ),
            refreshSession: { _ in wrongSession }
        )

        await sessionStore.bootstrap(gardenStore: gardenStore)

        XCTAssertEqual(sessionStore.state, .signedOut)
        XCTAssertTrue(didClearSession)
        XCTAssertNil(gardenStore.persistenceOwnerID)
        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertEqual(UserDefaults.standard.data(forKey: GardenPersistence.plantsKey), primaryBefore)
        XCTAssertEqual(UserDefaults.standard.data(forKey: GardenPersistence.backupPlantsKey), backupBefore)
        XCTAssertEqual(GardenPersistence.loadPlants(ownerID: firstOwner), [plant])
    }

    func testIdentityMismatchDuringActiveGardenSyncCannotRestorePendingStatus() async {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let firstOwner = UUID()
        let secondOwner = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Original account rose")
        XCTAssertTrue(GardenPersistence.savePlants([plant], ownerID: firstOwner))
        let savedSession = AuthSession(
            accessToken: "expired-a",
            refreshToken: "refresh-a",
            expiresAt: .distantPast,
            user: AuthUser(id: firstOwner, email: "account-a@example.com")
        )
        let shortLivedFirstOwnerSession = AuthSession(
            accessToken: "short-a",
            refreshToken: "rotated-a",
            expiresAt: Date().addingTimeInterval(10),
            user: savedSession.user
        )
        let wrongSession = AuthSession(
            accessToken: "access-b",
            refreshToken: "refresh-b",
            expiresAt: .distantFuture,
            user: AuthUser(id: secondOwner, email: "account-b@example.com")
        )
        var refreshCount = 0
        var savedSessions: [AuthSession] = []
        var didClearSession = false
        let gardenStore = GardenStore()
        let sessionStore = SessionStore(
            configuration: BackendConfiguration(
                baseURL: URL(string: "https://example.supabase.co")!,
                anonymousKey: "public-key"
            ),
            sessionPersistence: SessionPersistence(
                load: { savedSession },
                save: { savedSessions.append($0) },
                clear: { didClearSession = true }
            ),
            refreshSession: { _ in
                refreshCount += 1
                return refreshCount == 1
                    ? shortLivedFirstOwnerSession
                    : wrongSession
            }
        )

        await sessionStore.bootstrap(gardenStore: gardenStore)

        XCTAssertEqual(refreshCount, 2)
        XCTAssertEqual(savedSessions, [shortLivedFirstOwnerSession])
        XCTAssertTrue(didClearSession)
        XCTAssertEqual(sessionStore.state, .signedOut)
        XCTAssertEqual(sessionStore.gardenSyncStatus, .local)
        XCTAssertNil(gardenStore.persistenceOwnerID)
        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertEqual(GardenPersistence.loadPlants(ownerID: firstOwner), [plant])
    }

    func testUpdateNormalizesLocalPlantAndCloudUpsertPayload() {
        let original = GardenPlant(flowerId: "rosa", nickname: "Original")
        let store = GardenStore(plants: [original])
        var upsertedPlants: [GardenPlant] = []
        store.cloudChangeHandler = { change in
            guard case let .upsert(plant) = change else { return true }
            upsertedPlants.append(plant)
            return true
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
        GardenPersistence.clearPlants()
        let store = GardenStore()
        store.activatePersistence(for: gardenPersistenceOwnerID)
        defer { GardenPersistence.clearPlants() }

        store.replaceFromCloud([legacyPlant])

        XCTAssertEqual(store.plants[0].nickname, nicknamePrefix)
        XCTAssertEqual(store.plants[0].notes, notesPrefix)
        XCTAssertEqual(
            GardenPersistence.loadPlants(ownerID: gardenPersistenceOwnerID),
            store.plants
        )
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
        XCTAssertEqual(summary.unscheduledCount, 0)
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

    func testGardenExportPayloadContainsArbitraryPlantIdentityAndOptionalCare() {
        let plant = GardenPlant(
            identity: PlantIdentity(
                source: .plantID,
                sourceID: "plant-id-456",
                commonName: "Swiss cheese plant",
                scientificName: "Monstera deliciosa",
                rank: "species",
                nameLocale: "en"
            ),
            careProfile: PlantCareProfile(
                wateringIntervalDays: nil,
                waterAmountMl: nil,
                wateringPreference: .medium,
                source: .plantID
            ),
            nickname: "Living room monstera"
        )

        let payload = GardenExport.payload(
            plants: [plant],
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertTrue(payload.contains("\"commonName\" : \"Swiss cheese plant\""))
        XCTAssertTrue(payload.contains("\"scientificName\" : \"Monstera deliciosa\""))
        XCTAssertTrue(payload.contains("\"source\" : \"plant_id\""))
        XCTAssertTrue(payload.contains("\"wateringPreference\" : \"medium\""))
        XCTAssertFalse(payload.contains("\"flowerId\""))
    }

    func testGardenPlantEntityUsesGenericIdentityWithoutCatalogLookup() {
        let plant = GardenPlant(
            identity: PlantIdentity(
                source: .manual,
                commonName: "Snake plant",
                scientificName: "Dracaena trifasciata"
            ),
            careProfile: PlantCareProfile(source: .manual),
            nickname: "Desk plant"
        )

        let entity = GardenPlantEntity(plant: plant)

        XCTAssertEqual(entity.id, plant.id.uuidString)
        XCTAssertEqual(entity.name, "Desk plant")
        XCTAssertEqual(entity.plantName, "Dracaena trifasciata")
    }

    func testResetClearsPlants() {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let plant = GardenPlant(flowerId: "rosa", nickname: "Rosa")
        XCTAssertTrue(
            GardenPersistence.savePlants(
                [plant],
                ownerID: gardenPersistenceOwnerID
            )
        )
        let store = GardenStore()
        store.activatePersistence(for: gardenPersistenceOwnerID)

        store.reset()

        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertEqual(store.persistenceStatus, .empty)
        XCTAssertTrue(store.canAcceptLocalChanges)
        XCTAssertTrue(
            GardenPersistence.loadPlants(ownerID: gardenPersistenceOwnerID).isEmpty
        )
    }

    func testDeleteAndResetEmitDatedCloudTombstones() {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Rosa")
        let deleteDate = Date(timeIntervalSince1970: 1_800_000_100)
        let resetDate = Date(timeIntervalSince1970: 1_800_000_200)
        let store = GardenStore(plants: [plant])
        var changes: [GardenChange] = []
        store.cloudChangeHandler = {
            changes.append($0)
            return true
        }

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

    func testRejectedCloudJournalLeavesWaterEditDeleteAndResetUnchanged() {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_800)
        let plant = GardenPlant(
            flowerId: "rosa",
            nickname: "Original",
            addedAt: timestamp,
            lastWateredAt: timestamp,
            notes: "Original notes",
            updatedAt: timestamp
        )
        let store = GardenStore(plants: [plant])
        store.cloudChangeHandler = { _ in false }

        XCTAssertFalse(store.water(plant, at: timestamp.addingTimeInterval(60)))
        XCTAssertFalse(
            store.update(
                plant,
                nickname: "Rejected edit",
                status: .needsSun,
                notes: "Rejected notes"
            )
        )
        XCTAssertFalse(store.delete(plant))
        XCTAssertEqual(store.reset(), .rejected)
        XCTAssertEqual(store.plants, [plant])
        XCTAssertNotNil(store.mutationErrorMessage)
        store.clearMutationError()
        XCTAssertNil(store.mutationErrorMessage)
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

    func testLocalDataResetRecoversAnUnreadableDeviceSnapshot() async {
        GardenPersistence.clearPlants()
        UserDefaults.standard.set(
            Data("corrupt-primary".utf8),
            forKey: GardenPersistence.plantsKey
        )
        UserDefaults.standard.set(
            Data("corrupt-backup".utf8),
            forKey: GardenPersistence.backupPlantsKey
        )
        defer { GardenPersistence.clearPlants() }
        let store = GardenStore()
        store.activatePersistence(for: gardenPersistenceOwnerID)
        var didCancelPendingNotifications = false
        let resetter = LocalDataResetter {
            didCancelPendingNotifications = true
        }

        XCTAssertEqual(store.persistenceStatus, .unrecoverableCorruption)
        let status = await resetter.reset(gardenStore: store)

        XCTAssertEqual(status, .localOnly)
        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertEqual(store.persistenceStatus, .empty)
        XCTAssertTrue(didCancelPendingNotifications)
        XCTAssertNil(UserDefaults.standard.data(forKey: GardenPersistence.plantsKey))
        XCTAssertNil(UserDefaults.standard.data(forKey: GardenPersistence.backupPlantsKey))
    }

    func testLocalDataResetRemovesFutureSchemaSnapshots() async {
        GardenPersistence.clearPlants()
        let futurePrimary = Data(
            """
            {"schemaVersion":999,"ownerID":"\(gardenPersistenceOwnerID.uuidString)","futureData":"primary"}
            """.utf8
        )
        let futureBackup = Data(#"{"schemaVersion":999,"futureData":"backup"}"#.utf8)
        UserDefaults.standard.set(futurePrimary, forKey: GardenPersistence.plantsKey)
        UserDefaults.standard.set(futureBackup, forKey: GardenPersistence.backupPlantsKey)
        defer { GardenPersistence.clearPlants() }
        let store = GardenStore()
        store.activatePersistence(for: gardenPersistenceOwnerID)
        let resetter = LocalDataResetter(cancelPendingNotifications: {})

        XCTAssertEqual(store.persistenceStatus, .unrecoverableCorruption)
        let status = await resetter.reset(gardenStore: store)

        XCTAssertEqual(status, .localOnly)
        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertEqual(store.persistenceStatus, .empty)
        XCTAssertNil(UserDefaults.standard.data(forKey: GardenPersistence.plantsKey))
        XCTAssertNil(UserDefaults.standard.data(forKey: GardenPersistence.backupPlantsKey))
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

    func testAcceptedCloudResetReportsForcedLocalPurgeFailureTruthfully() async {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let ownerID = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Retained rose")
        XCTAssertTrue(GardenPersistence.savePlants([plant], ownerID: ownerID))
        let store = GardenStore(gardenDataPurger: { _ in false })
        store.activatePersistence(for: ownerID)
        var didAcceptCloudReset = false
        store.cloudChangeHandler = { change in
            guard case .reset = change else { return false }
            didAcceptCloudReset = true
            return true
        }
        var didCancelPendingNotifications = false
        var didWaitForCloud = false
        let resetter = LocalDataResetter {
            didCancelPendingNotifications = true
        }

        let status = await resetter.reset(
            gardenStore: store,
            waitForCloudConfirmation: {
                didWaitForCloud = true
                return true
            }
        )

        XCTAssertEqual(status, .localPurgeFailed)
        XCTAssertTrue(didAcceptCloudReset)
        XCTAssertTrue(didCancelPendingNotifications)
        XCTAssertTrue(didWaitForCloud)
        XCTAssertEqual(store.plants, [plant])
        XCTAssertEqual(GardenPersistence.loadPlants(ownerID: ownerID), [plant])
    }

    func testAccountDeletionPurgePreservesAnotherAccountsRecoverableGarden() {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let firstOwner = UUID()
        let deletedOwner = UUID()
        let firstPlant = GardenPlant(flowerId: "rosa", nickname: "Account A rose")
        XCTAssertTrue(GardenPersistence.savePlants([firstPlant], ownerID: firstOwner))
        let store = GardenStore()
        store.activatePersistence(for: deletedOwner)

        XCTAssertEqual(store.persistenceStatus, .ownerMismatch)
        XCTAssertTrue(store.purgeAllLocalGardenData())

        XCTAssertNil(store.persistenceOwnerID)
        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertEqual(GardenPersistence.loadPlants(ownerID: firstOwner), [firstPlant])
    }

    func testFailedAccountDeletionPurgeStillHidesTheDeletedAccountsGarden() {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let deletedOwner = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Deleted account rose")
        XCTAssertTrue(GardenPersistence.savePlants([plant], ownerID: deletedOwner))
        let store = GardenStore(gardenDataPurger: { _ in false })
        store.activatePersistence(for: deletedOwner)

        XCTAssertFalse(store.purgeAllLocalGardenData())

        XCTAssertNil(store.persistenceOwnerID)
        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertEqual(store.persistenceStatus, .empty)
        XCTAssertEqual(GardenPersistence.loadPlants(ownerID: deletedOwner), [plant])
    }

    func testAccountDeletionPurgeRemovesFutureSchemaSnapshots() {
        GardenPersistence.clearPlants()
        UserDefaults.standard.set(
            Data(#"{"schemaVersion":999,"futureData":"primary"}"#.utf8),
            forKey: GardenPersistence.plantsKey
        )
        UserDefaults.standard.set(
            Data(#"{"schemaVersion":999,"futureData":"backup"}"#.utf8),
            forKey: GardenPersistence.backupPlantsKey
        )
        defer { GardenPersistence.clearPlants() }
        let store = GardenStore()
        store.activatePersistence(for: gardenPersistenceOwnerID)

        XCTAssertEqual(store.persistenceStatus, .unrecoverableCorruption)
        XCTAssertTrue(store.purgeAllLocalGardenData())

        XCTAssertNil(store.persistenceOwnerID)
        XCTAssertTrue(store.plants.isEmpty)
        XCTAssertEqual(store.persistenceStatus, .empty)
        XCTAssertNil(UserDefaults.standard.data(forKey: GardenPersistence.plantsKey))
        XCTAssertNil(UserDefaults.standard.data(forKey: GardenPersistence.backupPlantsKey))
    }

    func testAccountBResetAndCloudReplacementPreserveAccountAOffline() {
        GardenPersistence.clearPlants()
        defer { GardenPersistence.clearPlants() }
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstPlant = GardenPlant(flowerId: "rosa", nickname: "Account A rose")
        XCTAssertTrue(GardenPersistence.savePlants([firstPlant], ownerID: firstOwner))
        let store = GardenStore()
        store.activatePersistence(for: secondOwner)
        store.cloudChangeHandler = { _ in true }

        XCTAssertEqual(store.reset(), .accepted)
        XCTAssertEqual(store.persistenceStatus, .ownerMismatch)
        XCTAssertTrue(store.replaceFromCloud([]))
        XCTAssertEqual(store.persistenceStatus, .loaded)

        XCTAssertEqual(GardenPersistence.loadPlants(ownerID: firstOwner), [firstPlant])
        XCTAssertTrue(GardenPersistence.loadPlants(ownerID: secondOwner).isEmpty)
        XCTAssertEqual(GardenPersistence.loadPlants(ownerID: firstOwner), [firstPlant])
    }

    func testRejectedDataResetTruthfullyKeepsPlantsAndReminders() async {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Rosa")
        let store = GardenStore(plants: [plant])
        store.cloudChangeHandler = { _ in false }
        var didCancelPendingNotifications = false
        let resetter = LocalDataResetter {
            didCancelPendingNotifications = true
        }

        let status = await resetter.reset(
            gardenStore: store,
            waitForCloudConfirmation: { true }
        )

        XCTAssertEqual(status, .rejected)
        XCTAssertEqual(store.plants, [plant])
        XCTAssertFalse(didCancelPendingNotifications)
        XCTAssertTrue(status.message.contains("Nothing was deleted"))
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

private struct LegacyGardenPlantFixture: Codable {
    let id: UUID
    let flowerId: String
    let nickname: String
    let addedAt: Date
    let lastWateredAt: Date
    let status: PlantStatus
    let notes: String
}

private final class CoordinatedUserDefaults: UserDefaults, @unchecked Sendable {
    let didReachBlockedSet = DispatchSemaphore(value: 0)
    let allowBlockedSet = DispatchSemaphore(value: 0)

    private let coordinationLock = NSLock()
    private var blockedData: Data?
    private var blockedKey: String?
    private var shouldBlock = false

    func blockNextSet(data: Data, forKey key: String) {
        coordinationLock.lock()
        blockedData = data
        blockedKey = key
        shouldBlock = true
        coordinationLock.unlock()
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        coordinationLock.lock()
        let shouldPause =
            shouldBlock &&
            blockedKey == defaultName &&
            blockedData == value as? Data
        if shouldPause {
            shouldBlock = false
        }
        coordinationLock.unlock()

        if shouldPause {
            didReachBlockedSet.signal()
            _ = allowBlockedSet.wait(timeout: .now() + 5)
        }
        super.set(value, forKey: defaultName)
    }
}
