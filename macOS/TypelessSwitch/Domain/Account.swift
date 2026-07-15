import Foundation

struct Account: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var nickname: String
    var email: String
    var role: String
    var capturedAt: Date?
    var addedAt: Date?
    var live: AccountLiveStatus?
    var hasSnapshot: Bool
    var snapshotModifiedAt: Date?
    var tokenExpiresAt: Date?
    var tokenDaysLeft: Int?

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case nickname, email, role, live
        case capturedAt = "captured_at"
        case addedAt = "added_at"
        case hasSnapshot = "has_snapshot"
        case snapshotModifiedAt = "snapshot_mtime"
        case tokenExpiresAt = "token_expires_at"
        case tokenDaysLeft = "token_days_left"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        email = try values.decodeIfPresent(String.self, forKey: .email) ?? ""
        role = try values.decodeIfPresent(String.self, forKey: .role) ?? ""
        capturedAt = try values.decodeIfPresent(Date.self, forKey: .capturedAt)
        addedAt = try values.decodeIfPresent(Date.self, forKey: .addedAt)
        live = try values.decodeIfPresent(AccountLiveStatus.self, forKey: .live)
        hasSnapshot = try values.decodeIfPresent(Bool.self, forKey: .hasSnapshot) ?? false
        snapshotModifiedAt = try values.decodeIfPresent(Date.self, forKey: .snapshotModifiedAt)
        tokenExpiresAt = try values.decodeIfPresent(Date.self, forKey: .tokenExpiresAt)
        tokenDaysLeft = try values.decodeIfPresent(Int.self, forKey: .tokenDaysLeft)
    }
}

struct AccountLiveStatus: Codable, Equatable, Sendable {
    var tokenValid: Bool
    var usage: AccountUsage?
    var personal: PersonalizationStatus?
    var dictionaryCount: Int
    var error: String?

    enum CodingKeys: String, CodingKey {
        case tokenValid = "token_valid"
        case usage, personal, error
        case dictionaryCount = "dict_count"
    }
}

struct AccountUsage: Codable, Equatable, Sendable {
    var weeklyWordUsage: Double?
    var weeklyWordLimit: Double?
    var totalWords: Double?
    var totalAudioSeconds: Double?
    var minutesSaved: Double?
    var averageWordsPerMinute: Double?

    enum CodingKeys: String, CodingKey {
        case weeklyWordUsage = "week_word_usage_value"
        case weeklyWordLimit = "week_word_usage_limit"
        case totalWords = "total_words"
        case totalAudioSeconds = "total_audio_seconds"
        case minutesSaved = "mins_saved"
        case averageWordsPerMinute = "avg_wpm"
    }
}

struct PersonalizationStatus: Codable, Equatable, Sendable {
    var totalLearningRatio: Double?
    var enabled: Bool
    var categoryCount: Int?

    enum CodingKeys: String, CodingKey {
        case totalLearningRatio = "total_learning_ratio"
        case enabled
        case categoryCount = "category_count"
    }
}

struct AccountCapture: Codable, Identifiable, Equatable, Sendable {
    var captureID: String?
    let userID: String
    var nickname: String
    var email: String
    var role: String
    var capturedAt: Date?

    var id: String { captureID ?? userID }

    enum CodingKeys: String, CodingKey {
        case captureID = "capture_id"
        case userID = "user_id"
        case nickname, email, role
        case capturedAt = "captured_at"
    }
}

struct AccountDeletionResult: Codable, Equatable, Sendable {
    let deleted: Bool
    let userID: String

    enum CodingKeys: String, CodingKey { case deleted; case userID = "user_id" }
}

struct SnapshotResult: Codable, Equatable, Sendable {
    let userID: String
    let hasSnapshot: Bool?
    let switched: Bool?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case hasSnapshot = "has_snapshot"
        case switched
    }
}
