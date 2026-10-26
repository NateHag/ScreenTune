import CoreGraphics
import Foundation

/// Per-channel color curves (brightness, contrast, mid tones, warmth, RGB gains).
/// Uses the display gamma table. macOS resets it when this process exits.
enum Gamma {
    static func isIdentity(_ t: Tune) -> Bool {
        t.contrast == 1 && t.gamma == 1 && t.kelvin >= 6500 && t.dim == 1
            && t.red == 1 && t.green == 1 && t.blue == 1
    }

    /// True while the display uses its normal (ColorSync) curves.
    private static var restored = true

    /// Safe to call often: it changes the display only when the table is different.
    static func apply(_ t: Tune) {
        guard t.enabled, !isIdentity(t) else {
            if !restored {
                CGDisplayRestoreColorSyncSettings()
                restored = true
            }
            return
        }
        let k = kelvinRGB(t.kelvin)
        let gains = [k.0 * t.red, k.1 * t.green, k.2 * t.blue]
        let n = 256
        let tables: [[CGGammaValue]] = gains.map { gain in
            (0..<n).map { i in
                var x = Double(i) / Double(n - 1)
                x = clamp((x - 0.5) * t.contrast + 0.5)
                x = pow(x, 1 / t.gamma)
                return CGGammaValue(clamp(x * gain * t.dim))
            }
        }
        restored = false
        for id in displays() where !matches(id, tables) {
            CGSetDisplayTransferByTable(id, UInt32(n), tables[0], tables[1], tables[2])
        }
    }

    private static func matches(_ id: CGDirectDisplayID, _ tables: [[CGGammaValue]]) -> Bool {
        let n = tables[0].count
        var r = [CGGammaValue](repeating: 0, count: n), g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, UInt32(n), &r, &g, &b, &count) == .success,
              Int(count) == n else { return false }
        return zip([r, g, b], tables).allSatisfy { zip($0, $1).allSatisfy { abs($0 - $1) < 0.002 } }
    }

    static func displays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// RGB multipliers for a color temperature, normalized so 6500 K = (1, 1, 1).
    static func kelvinRGB(_ kelvin: Double) -> (Double, Double, Double) {
        func raw(_ k: Double) -> (Double, Double, Double) {
            let t = k / 100
            let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
            let g = t <= 66
                ? 99.4708025861 * log(t) - 161.1195681661
                : 288.1221695283 * pow(t - 60, -0.0755148492)
            let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
            return (clamp(r / 255), clamp(g / 255), clamp(b / 255))
        }
        let a = raw(kelvin), w = raw(6500)
        return (min(a.0 / w.0, 1), min(a.1 / w.1, 1), min(a.2 / w.2, 1))
    }
}

func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
    min(max(x, lo), hi)
}
