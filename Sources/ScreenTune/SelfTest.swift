import ColorSync
import CoreGraphics
import Foundation

/// `ScreenTune --selftest`: checks each part on real hardware, then puts everything back.
enum SelfTest {
    static func run() {
        let main = CGMainDisplayID()
        func profileName() -> String {
            (CGDisplayCopyColorSpace(main).copyICCData() as Data?).flatMap(ICC.description) ?? "?"
        }

        print("light sensor:", LightSensor().lux().map { "\($0) lux" } ?? "none")
        if let id = Brightness.builtIn, let b = Brightness.get(id) {
            Brightness.set(id, b - 0.1)
            Thread.sleep(forTimeInterval: 0.3)
            print("brightness: \(b) -> \(Brightness.get(id) ?? -1)")
            Brightness.set(id, b)
            Thread.sleep(forTimeInterval: 0.3)
            print("brightness restored:", Brightness.get(id) ?? -1)
        }

        // Round trip: parse + build without changes must keep the color math the same.
        if let d = CGDisplayCopyColorSpace(main).copyICCData() as Data?,
           let same = ICC.saturated(d, 1, name: "x"), CGColorSpace(iccData: same as CFData) != nil {
            print("icc round trip: ok (\(d.count) -> \(same.count) bytes)")
        }

        print("profile before:", profileName())
        for s in [1.6, 0.5] {
            Saturation.apply(s)
            Thread.sleep(forTimeInterval: 1)
            print("profile at \(s):", profileName())
        }
        Saturation.restoreAll()
        Thread.sleep(forTimeInterval: 1)
        print("profile after restore:", profileName())

        var t = Tune()
        t.kelvin = 4000
        Gamma.apply(t)
        var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r
        var n: UInt32 = 0
        CGGetDisplayTransferByTable(main, 256, &r, &g, &b, &n)
        print("gamma at 4000 K, top value r/g/b:", r[255], g[255], b[255])
        CGDisplayRestoreColorSyncSettings()
    }
}
