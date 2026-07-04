import Foundation

struct AppItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var bundleId: String?
    var path: String?
    var order: Int = 0
}
