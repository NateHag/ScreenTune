import ColorSync
import CoreGraphics
import Foundation

/// Saturation through a custom display profile. ColorSync does the color math,
/// so there is no lag and no GPU cost. The user's own profile comes back on restore.
enum Saturation {
    static let marker = "ScreenTune"

    static var profilesDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/ColorSync/Profiles")
    }

    static var supportDir: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(marker)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var deviceClass: CFString { kColorSyncDisplayDeviceClass.takeUnretainedValue() }

    /// Value now active per display. A profile change makes every app redraw,
    /// so we never write a profile that is already active.
    private static var active: [String: Double] = [:]
    private static var recentWrites: [Date] = []

    static func apply(_ s: Double) {
        for id in Gamma.displays() {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
            let key = CFUUIDCreateString(nil, uuid) as String
            if abs(s - 1) < 0.005 {
                restore(uuid)
                continue
            }
            if let current = active[key], abs(current - s) < 0.005, isOurs(currentCustomURL(uuid)) { continue }
            // Safety net: never more than 8 profile changes in 10 seconds.
            let now = Date()
            recentWrites = recentWrites.filter { now.timeIntervalSince($0) < 10 }
            guard recentWrites.count < 8 else {
                NSLog("ScreenTune: too many profile changes, skipping")
                continue
            }
            recentWrites.append(now)
            rememberOriginal(id, uuid, key)
            guard let original = try? Data(contentsOf: originalCopy(key)),
                  let patched = ICC.saturated(original, s, name: "\(marker) \(Int((s * 100).rounded()))%")
            else { continue }

            // A new file name each time makes ColorSync reload the profile.
            removeOurProfiles(key)
            try? FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            let url = profilesDir.appendingPathComponent("\(marker)-\(key)-\(stamp).icc")
            guard (try? patched.write(to: url)) != nil else { continue }
            setProfile(uuid, url as CFURL)
            active[key] = s
            NSLog("ScreenTune: saturation profile \(s) on \(key)")
        }
    }

    /// Lowest saturation that Chrome-based browsers still draw on every display (see ICC.lowestSafeSaturation).
    static func lowestSafe() -> Double? {
        Gamma.displays().compactMap { id -> Double? in
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            let key = CFUUIDCreateString(nil, uuid) as String
            // While our profile is active, the display's own profile is the saved copy.
            let own = isOurs(currentCustomURL(uuid))
                ? try? Data(contentsOf: originalCopy(key))
                : CGDisplayCopyColorSpace(id).copyICCData() as Data?
            return own.flatMap(ICC.lowestSafeSaturation)
        }.max()
    }

    static func restoreAll() {
        for id in Gamma.displays() {
            if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() { restore(uuid) }
        }
    }

    private static func restore(_ uuid: CFUUID) {
        let key = CFUUIDCreateString(nil, uuid) as String
        active[key] = nil
        guard isOurs(currentCustomURL(uuid)) else { return }
        if let saved = UserDefaults.standard.string(forKey: "originalURL-\(key)"),
           let url = URL(string: saved), FileManager.default.fileExists(atPath: url.path) {
            setProfile(uuid, url as CFURL)
        } else {
            setProfile(uuid, kCFNull)  // back to the factory profile
        }
        removeOurProfiles(key)
    }

    /// Saves the user's own profile (URL and data) the first time we take over a display.
    private static func rememberOriginal(_ id: CGDirectDisplayID, _ uuid: CFUUID, _ key: String) {
        let current = currentCustomURL(uuid)
        if isOurs(current) { return }  // already ours (for example after a crash): keep the saved copy
        UserDefaults.standard.set(current?.absoluteString ?? "", forKey: "originalURL-\(key)")
        if let data = CGDisplayCopyColorSpace(id).copyICCData() as Data? {
            try? data.write(to: originalCopy(key))
        }
    }

    private static func originalCopy(_ key: String) -> URL {
        supportDir.appendingPathComponent("original-\(key).icc")
    }

    private static func currentCustomURL(_ uuid: CFUUID) -> URL? {
        guard let info = ColorSyncDeviceCopyDeviceInfo(deviceClass, uuid)?.takeRetainedValue() as? [String: Any],
              let custom = info[kColorSyncCustomProfiles.takeUnretainedValue() as String] as? [String: Any]
        else { return nil }
        let value = custom["1"] ?? custom.first(where: { $0.key != kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String })?.value
        if let url = value as? URL { return url }
        if let s = value as? String { return URL(string: s) }
        return nil
    }

    private static func isOurs(_ url: URL?) -> Bool {
        url?.lastPathComponent.hasPrefix(marker + "-") ?? false
    }

    private static func setProfile(_ uuid: CFUUID, _ value: CFTypeRef) {
        let profiles = [kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String: value] as CFDictionary
        _ = ColorSyncDeviceSetCustomProfiles(deviceClass, uuid, profiles)
    }

    private static func removeOurProfiles(_ key: String) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: profilesDir.path)) ?? []
        for name in names where name.hasPrefix("\(marker)-\(key)-") {
            try? fm.removeItem(at: profilesDir.appendingPathComponent(name))
        }
    }
}
