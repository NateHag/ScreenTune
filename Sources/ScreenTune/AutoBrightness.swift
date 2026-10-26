import Foundation

/// Sets the built-in backlight from the light sensor, along a curve the user draws.
final class AutoBrightness {
    /// Light levels (lux) for the curve points. Even spacing in the editor ≈ log scale.
    static let luxPoints: [Double] = [0, 5, 30, 150, 600, 3000]
    static let defaultCurve: [Double] = [0.12, 0.3, 0.5, 0.68, 0.85, 1.0]
    static let tick = 0.5

    private let sensor = LightSensor()
    private var timer: Timer?
    private var smoothedLux: Double?
    private var lastSet: Double?
    private unowned let model: Model

    init(model: Model) { self.model = model }

    var sensorAvailable: Bool { sensor.available }

    func start() {
        guard timer == nil else { return }
        lastSet = nil
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in self?.step() }
        step()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reads the sensor only, for the live readout when auto mode is off.
    func readLux() -> Double? { sensor.lux() }

    private func step() {
        guard let lux = sensor.lux() else { return }
        let alpha = 1 - exp(-Self.tick / max(model.tune.reaction, 0.1))
        let smooth = smoothedLux.map { $0 + alpha * (lux - $0) } ?? lux
        smoothedLux = smooth
        model.currentLux = smooth

        guard let display = Brightness.builtIn, let current = Brightness.get(display) else { return }
        model.currentBrightness = current

        // The user moved brightness with the keys: keep their change as an offset.
        if let lastSet, abs(current - lastSet) > 0.02 {
            model.tune.offset = clamp(model.tune.offset + current - lastSet, -0.6, 0.6)
        }

        let target = clamp(Self.value(model.tune.curve, at: smooth) + model.tune.offset, 0.01, 1)
        let diff = target - current
        guard abs(diff) > 0.003 else {
            lastSet = current
            return
        }
        // Glide: move part of the way each tick, never more than 4%.
        let next = current + clamp(diff * 0.35, -0.04, 0.04)
        Brightness.set(display, next)
        lastSet = Brightness.get(display) ?? next
        model.currentBrightness = lastSet ?? next
    }

    /// Curve position (0 = first point, n-1 = last) for a light level.
    static func position(lux: Double) -> Double {
        let x = log10(lux + 1)
        let xs = luxPoints.map { log10($0 + 1) }
        if x <= xs[0] { return 0 }
        for i in 1..<xs.count where x <= xs[i] {
            return Double(i - 1) + (x - xs[i - 1]) / (xs[i] - xs[i - 1])
        }
        return Double(xs.count - 1)
    }

    static func value(_ curve: [Double], at lux: Double) -> Double {
        let p = position(lux: lux)
        let i = min(Int(p), curve.count - 2)
        let f = p - Double(i)
        return curve[i] + (curve[i + 1] - curve[i]) * f
    }
}
