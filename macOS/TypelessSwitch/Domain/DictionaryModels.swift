import Foundation

struct DictionaryWord: Codable, Identifiable, Equatable, Sendable {
    let term: String
    var auto: Bool
    var id: String { term }
}

struct AccountDictionary: Codable, Equatable, Sendable { var words: [DictionaryWord] }
struct MasterDictionary: Codable, Equatable, Sendable { var words: [String] }
struct AddedWordResult: Codable, Equatable, Sendable { let term: String }
struct DeletedWordResult: Codable, Equatable, Sendable { let term: String; let deleted: Bool }
struct BulkImportResult: Codable, Equatable, Sendable { let requested: Int; let imported: Int }
