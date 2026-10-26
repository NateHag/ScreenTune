import Foundation

/// All user settings. Saved as JSON in UserDefaults.
struct Tune: Codable, Equatable {
    var enabled = true

    // Color
    var saturation = 1.0
    var contrast = 1.0
    var gamma = 1.0
    var kelvin = 6500.0
    var dim = 1.0
    var red = 1.0
    var green = 1.0
    var blue = 1.0

    // Auto-brightness
    var autoBrightness = false
    var curve: [Double] = AutoBrightness.defaultCurve
    var reaction = 3.0
    var offset = 0.0

    static let key = "tune"

    static func load() -> Tune {
        guard let data = UserDefaults.standard.data(forKey: key),
              let t = try? JSONDecoder().decode(Tune.self, from: data) else { return Tune() }
        return t
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Tune.key)
        }
    }
}
