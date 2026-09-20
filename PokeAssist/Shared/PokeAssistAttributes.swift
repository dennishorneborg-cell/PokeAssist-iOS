import ActivityKit
import Foundation

struct PokeAssistAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var frameCount: Int
        var status: String
        var recognitionSummary: String
    }

    var sessionName: String
}
