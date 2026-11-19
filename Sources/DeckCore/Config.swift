import Foundation

public struct DisplayConfig: Codable {
    public let name: String
    public let serial: String          // AN Serial from `m1ddc display list detailed`
}

public struct DeckConfig: Codable {
    public let brightness: Int
    public let buttons: [String: ButtonConfig]
    public let knobs: [String: KnobConfig]
    public let displays: [DisplayConfig]?

    public static func load(from path: String) -> DeckConfig? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            print("Error: config file not found at \(path)")
            return nil
        }
        do {
            return try JSONDecoder().decode(DeckConfig.self, from: data)
        } catch {
            print("Error: failed to parse config at \(path): \(error)")
            return nil
        }
    }
}

public struct ButtonConfig: Codable {
    public let action: String
    public let icon: String?
}

public struct KnobConfig: Codable {
    public let rotate: KnobAction
    public let press: KnobAction
}

public struct KnobAction: Codable {
    public let action: String
    public let step: Int?
}
