import AppKit
import Combine
import ServiceManagement

/// Holds the settings and pushes every change to the screen.
final class Model: ObservableObject {
    @Published var tune: Tune {
        didSet { changed(from: oldValue) }
    }
    @Published var currentLux: Double?
    @Published var currentBrightness: Double?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private(set) lazy var auto = AutoBrightness(model: self)
    private var saturationWork: DispatchWorkItem?
    private var refreshTimer: Timer?

    init() {
        tune = Tune.load()
    }

    func start() {
        applyAll()
        // macOS resets gamma tables on wake, display changes and profile changes.
        let nc = NotificationCenter.default, wnc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyAll()
        }
        wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyAll()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Gamma.apply(self.tune)
            if !self.tune.autoBrightness {
                self.currentLux = self.auto.readLux()
                self.currentBrightness = Brightness.builtIn.flatMap(Brightness.get)
            }
        }
    }

    func shutdown() {
        auto.stop()
        Saturation.restoreAll()
        CGDisplayRestoreColorSyncSettings()
    }

    func resetColor() {
        var t = Tune()
        t.autoBrightness = tune.autoBrightness
        t.curve = tune.curve
        t.reaction = tune.reaction
        t.offset = tune.offset
        tune = t
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ScreenTune: launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyAll() {
        Saturation.apply(tune.enabled ? tune.saturation : 1)
        reapplyGammaSoon()
        tune.autoBrightness && tune.enabled ? auto.start() : auto.stop()
    }

    private func changed(from old: Tune) {
        tune.save()
        if tune.enabled != old.enabled {
            applyAll()
            return
        }
        if tune.saturation != old.saturation {
            // Wait for the slider to settle: each profile change takes a moment.
            saturationWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Saturation.apply(self.tune.enabled ? self.tune.saturation : 1)
                self.reapplyGammaSoon()
            }
            saturationWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        if tune.autoBrightness != old.autoBrightness {
            tune.autoBrightness && tune.enabled ? auto.start() : auto.stop()
        }
        Gamma.apply(tune)
    }

    /// A profile change resets the gamma table, so set it again after ColorSync is done.
    private func reapplyGammaSoon() {
        Gamma.apply(tune)
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                Gamma.apply(self.tune)
            }
        }
    }
}
