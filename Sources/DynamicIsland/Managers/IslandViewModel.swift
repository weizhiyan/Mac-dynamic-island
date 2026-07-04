import Foundation
import Combine

final class IslandViewModel: ObservableObject {
    static let shared = IslandViewModel()
    @Published var isExpanded: Bool = false
}
