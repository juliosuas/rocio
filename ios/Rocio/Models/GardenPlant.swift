import Foundation

struct GardenPlant: Identifiable, Codable, Equatable, Hashable {
    static let arbitraryCloudFlowerID = "__arbitrary__"

    let id: UUID
    var flowerId: String?
    var identity: PlantIdentity
    var careProfile: PlantCareProfile
    var nickname: String
    var addedAt: Date
    var lastWateredAt: Date
    var status: PlantStatus
    var notes: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        flowerId: String,
        nickname: String,
        addedAt: Date = Date(),
        lastWateredAt: Date = Date(),
        status: PlantStatus = .healthy,
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.flowerId = flowerId
        if let flower = FlowerCatalog.flower(id: flowerId) {
            self.identity = .bundled(flower)
            self.careProfile = .bundled(flower)
        } else {
            self.identity = PlantIdentity(
                source: .bundled,
                sourceID: flowerId,
                commonName: nickname
            )
            self.careProfile = PlantCareProfile(source: .bundled)
        }
        self.nickname = nickname
        self.addedAt = addedAt
        self.lastWateredAt = lastWateredAt
        self.status = status
        self.notes = notes
        self.updatedAt = updatedAt
    }

    init(
        id: UUID = UUID(),
        identity: PlantIdentity,
        careProfile: PlantCareProfile,
        nickname: String? = nil,
        addedAt: Date = Date(),
        lastWateredAt: Date = Date(),
        status: PlantStatus = .healthy,
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        flowerId = identity.source == .bundled ? identity.sourceID : nil
        self.identity = identity
        self.careProfile = careProfile
        self.nickname = nickname ?? identity.commonName
        self.addedAt = addedAt
        self.lastWateredAt = lastWateredAt
        self.status = status
        self.notes = notes
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case flowerId
        case identity
        case careProfile
        case nickname
        case addedAt
        case lastWateredAt
        case status
        case notes
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(UUID.self, forKey: .id)
        let decodedFlowerID = try container.decodeIfPresent(String.self, forKey: .flowerId)
        let decodedNickname = try container.decode(String.self, forKey: .nickname)
        let decodedAddedAt = try container.decode(Date.self, forKey: .addedAt)
        let decodedIdentity = try container.decodeIfPresent(PlantIdentity.self, forKey: .identity)
        let decodedCareProfile = try container.decodeIfPresent(PlantCareProfile.self, forKey: .careProfile)

        id = decodedID
        flowerId = decodedFlowerID
        identity = decodedIdentity ?? Self.legacyIdentity(
            flowerID: decodedFlowerID,
            nickname: decodedNickname
        )
        careProfile = decodedCareProfile ?? Self.legacyCareProfile(flowerID: decodedFlowerID)
        nickname = decodedNickname
        addedAt = decodedAddedAt
        lastWateredAt = try container.decode(Date.self, forKey: .lastWateredAt)
        status = try container.decode(PlantStatus.self, forKey: .status)
        notes = try container.decode(String.self, forKey: .notes)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? decodedAddedAt
    }

    func normalizingTextFields(nicknameFallback: String? = nil) -> GardenPlant {
        var normalized = self
        normalized.identity = identity.normalized(fallback: nicknameFallback ?? nickname)
        normalized.careProfile = careProfile.normalized
        normalized.nickname = GardenPlantTextNormalizer.normalizeNickname(
            nickname,
            fallback: nicknameFallback ?? normalized.identity.commonName
        )
        normalized.notes = GardenPlantTextNormalizer.normalizeNotes(notes)
        return normalized
    }

    var displayName: String {
        GardenPlantTextNormalizer.normalizeNickname(nickname, fallback: identity.commonName)
    }

    /// One source of truth for calendar rows, urgency, and notifications.
    /// Legacy bundled rows can still resolve their catalog interval even when
    /// an older cloud record has no explicit care profile.
    var resolvedWateringIntervalDays: Int? {
        if let interval = careProfile.reminderIntervalDays {
            return interval
        }
        guard let flowerId else { return nil }
        return FlowerCatalog.flower(id: flowerId)?.waterDays
    }

    private static func legacyIdentity(flowerID: String?, nickname: String) -> PlantIdentity {
        if let flowerID, let flower = FlowerCatalog.flower(id: flowerID) {
            return .bundled(flower)
        }
        return PlantIdentity(
            source: .bundled,
            sourceID: flowerID,
            commonName: nickname
        )
    }

    private static func legacyCareProfile(flowerID: String?) -> PlantCareProfile {
        guard let flowerID, let flower = FlowerCatalog.flower(id: flowerID) else {
            return PlantCareProfile(source: .bundled)
        }
        return .bundled(flower)
    }
}

enum PlantIdentitySource: String, Codable, CaseIterable, Sendable {
    case bundled
    case plantID = "plant_id"
    case manual
}

struct PlantIdentity: Codable, Equatable, Hashable, Sendable {
    var source: PlantIdentitySource
    var sourceID: String?
    var commonName: String
    var scientificName: String?
    var rank: String?
    var nameLocale: String?

    // `convertFromSnakeCase` normalizes `source_id` to `sourceId`, while Swift
    // property style keeps the initialism capitalized. Pin the wire key so
    // local snapshots and Supabase JSON both retain the provider identifier.
    private enum CodingKeys: String, CodingKey {
        case source
        case sourceID = "sourceId"
        case commonName
        case scientificName
        case rank
        case nameLocale
    }

    init(
        source: PlantIdentitySource,
        sourceID: String? = nil,
        commonName: String,
        scientificName: String? = nil,
        rank: String? = nil,
        nameLocale: String? = nil
    ) {
        self.source = source
        self.sourceID = sourceID
        self.commonName = commonName
        self.scientificName = scientificName
        self.rank = rank
        self.nameLocale = nameLocale
    }

    init(
        source: PlantIdentitySource,
        sourceID: String? = nil,
        commonName: String,
        scientificName: String? = nil,
        rank: String? = nil,
        locale: String?
    ) {
        self.init(
            source: source,
            sourceID: sourceID,
            commonName: commonName,
            scientificName: scientificName,
            rank: rank,
            nameLocale: locale
        )
    }

    var locale: String? {
        get { nameLocale }
        set { nameLocale = newValue }
    }

    static func bundled(_ flower: Flower) -> PlantIdentity {
        PlantIdentity(
            source: .bundled,
            sourceID: flower.id,
            commonName: flower.name,
            scientificName: flower.scientific
        )
    }

    func normalized(fallback: String = "Plant") -> PlantIdentity {
        PlantIdentity(
            source: source,
            sourceID: GardenPlantTextNormalizer.normalizeOptional(
                sourceID,
                maximumUnicodeScalarCount: GardenPlantTextNormalizer.identityMaximumUnicodeScalarCount
            ),
            commonName: GardenPlantTextNormalizer.normalizeRequired(
                commonName,
                fallback: fallback,
                maximumUnicodeScalarCount: GardenPlantTextNormalizer.identityMaximumUnicodeScalarCount
            ),
            scientificName: GardenPlantTextNormalizer.normalizeOptional(
                scientificName,
                maximumUnicodeScalarCount: GardenPlantTextNormalizer.identityMaximumUnicodeScalarCount
            ),
            rank: GardenPlantTextNormalizer.normalizeOptional(
                rank,
                maximumUnicodeScalarCount: GardenPlantTextNormalizer.rankMaximumUnicodeScalarCount
            ),
            nameLocale: GardenPlantTextNormalizer.normalizeLocale(nameLocale)
        )
    }
}

enum PlantWateringPreference: String, Codable, CaseIterable, Sendable {
    case dry
    case medium
    case wet

    var label: String {
        switch self {
        case .dry:
            L10n.text("watering.preference.dry", fallback: "Drier soil (about 14 days)")
        case .medium:
            L10n.text("watering.preference.medium", fallback: "Moderate moisture (about 7 days)")
        case .wet:
            L10n.text("watering.preference.wet", fallback: "Moist soil (about 3 days)")
        }
    }

    fileprivate var defaultReminderIntervalDays: Int {
        switch self {
        case .dry: 14
        case .medium: 7
        case .wet: 3
        }
    }
}

enum PlantWateringSelection: String, CaseIterable, Identifiable, Sendable {
    case notSet
    case dry
    case medium
    case wet

    var id: String { rawValue }

    init(preference: PlantWateringPreference?) {
        switch preference {
        case .dry: self = .dry
        case .medium: self = .medium
        case .wet: self = .wet
        case nil: self = .notSet
        }
    }

    var label: String {
        switch self {
        case .notSet:
            L10n.text("watering.preference.not_set", fallback: "Not sure")
        case .dry:
            L10n.text("watering.preference.dry.short", fallback: "Let soil dry")
        case .medium:
            L10n.text("watering.preference.medium.short", fallback: "Keep moderately moist")
        case .wet:
            L10n.text("watering.preference.wet.short", fallback: "Keep moist")
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

enum PlantCareSource: String, Codable, CaseIterable, Sendable {
    case bundled
    case plantID = "plant_id"
    case manual
}

struct PlantCareProfile: Codable, Equatable, Hashable, Sendable {
    var source: PlantCareSource
    var wateringPreference: PlantWateringPreference?
    var wateringIntervalDays: Int?
    var waterAmountMl: Int?
    var lightPreference: Sunlight?
    var fetchedAt: Date?

    init(
        wateringIntervalDays: Int? = nil,
        waterAmountMl: Int? = nil,
        wateringPreference: PlantWateringPreference? = nil,
        lightPreference: Sunlight? = nil,
        source: PlantCareSource,
        fetchedAt: Date? = nil
    ) {
        self.source = source
        self.wateringPreference = wateringPreference
        self.wateringIntervalDays = wateringIntervalDays
        self.waterAmountMl = waterAmountMl
        self.lightPreference = lightPreference
        self.fetchedAt = fetchedAt
    }

    var reminderIntervalDays: Int? {
        if let wateringIntervalDays, (1...365).contains(wateringIntervalDays) {
            return wateringIntervalDays
        }
        return wateringPreference?.defaultReminderIntervalDays
    }

    static func bundled(_ flower: Flower) -> PlantCareProfile {
        PlantCareProfile(
            wateringIntervalDays: flower.waterDays,
            waterAmountMl: flower.waterMl,
            lightPreference: flower.sunlight,
            source: .bundled
        )
    }

    var normalized: PlantCareProfile {
        PlantCareProfile(
            wateringIntervalDays: wateringIntervalDays.flatMap { (1...365).contains($0) ? $0 : nil },
            waterAmountMl: waterAmountMl.flatMap { (1...10_000).contains($0) ? $0 : nil },
            wateringPreference: wateringPreference,
            lightPreference: lightPreference,
            source: source,
            fetchedAt: fetchedAt
        )
    }
}

enum GardenPlantTextNormalizer {
    static let nicknameMaximumUnicodeScalarCount = 80
    static let notesMaximumUnicodeScalarCount = 2_000
    static let identityMaximumUnicodeScalarCount = 200
    static let rankMaximumUnicodeScalarCount = 80
    static let localeMaximumUnicodeScalarCount = 32

    static func normalizeNickname(_ value: String, fallback: String) -> String {
        for candidate in [value, fallback, "Plant"] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = prefixWithoutSplittingCharacter(
                trimmed,
                maximumUnicodeScalarCount: nicknameMaximumUnicodeScalarCount
            )
            if !normalized.isEmpty {
                return normalized
            }
        }
        return "Plant"
    }

    static func normalizeNotes(_ value: String) -> String {
        prefixWithoutSplittingCharacter(
            value,
            maximumUnicodeScalarCount: notesMaximumUnicodeScalarCount
        )
    }

    static func normalizeRequired(
        _ value: String,
        fallback: String,
        maximumUnicodeScalarCount: Int
    ) -> String {
        for candidate in [value, fallback, "Plant"] {
            let normalized = normalizeOptional(
                candidate,
                maximumUnicodeScalarCount: maximumUnicodeScalarCount
            )
            if let normalized { return normalized }
        }
        return "Plant"
    }

    static func normalizeOptional(
        _ value: String?,
        maximumUnicodeScalarCount: Int
    ) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = prefixWithoutSplittingCharacter(
            trimmed,
            maximumUnicodeScalarCount: maximumUnicodeScalarCount
        )
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizeLocale(_ value: String?) -> String? {
        guard let normalized = normalizeOptional(
            value,
            maximumUnicodeScalarCount: localeMaximumUnicodeScalarCount
        ), normalized.unicodeScalars.count >= 2 else {
            return nil
        }
        return normalized
    }

    private static func prefixWithoutSplittingCharacter(
        _ value: String,
        maximumUnicodeScalarCount: Int
    ) -> String {
        guard value.unicodeScalars.count > maximumUnicodeScalarCount else { return value }

        var result = ""
        var unicodeScalarCount = 0
        for character in value {
            let characterScalarCount = character.unicodeScalars.count
            guard unicodeScalarCount + characterScalarCount <= maximumUnicodeScalarCount else { break }
            result.append(character)
            unicodeScalarCount += characterScalarCount
        }
        return result
    }
}

enum PlantStatus: String, Codable, CaseIterable, Identifiable {
    case healthy
    case needsWater
    case needsSun
    case sick

    var id: String { rawValue }

    var label: String {
        switch self {
        case .healthy: L10n.text("plant.status.healthy", fallback: "Healthy")
        case .needsWater: L10n.text("plant.status.water", fallback: "Needs water")
        case .needsSun: L10n.text("plant.status.sun", fallback: "Needs sun")
        case .sick: L10n.text("plant.status.sick", fallback: "Unwell")
        }
    }

    var systemImage: String {
        switch self {
        case .healthy: "checkmark.seal"
        case .needsWater: "drop"
        case .needsSun: "sun.max"
        case .sick: "cross.case"
        }
    }
}

enum WateringUrgency: String {
    case good
    case soon
    case overdue

    var label: String {
        switch self {
        case .good: L10n.text("watering.good", fallback: "On track")
        case .soon: L10n.text("watering.soon", fallback: "Soon")
        case .overdue: L10n.text("watering.overdue", fallback: "Water now")
        }
    }
}
