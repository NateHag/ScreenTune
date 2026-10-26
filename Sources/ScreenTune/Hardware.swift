import CoreGraphics
import Foundation

/// Built-in display backlight through the private DisplayServices framework.
enum Brightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn = dlsym(lib, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: Get.self) }
    private static let setFn = dlsym(lib, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: Set.self) }

    static var builtIn: CGDirectDisplayID? {
        Gamma.displays().first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func get(_ id: CGDirectDisplayID) -> Double? {
        var value: Float = 0
        guard let getFn, getFn(id, &value) == 0 else { return nil }
        return Double(value)
    }

    static func set(_ id: CGDirectDisplayID, _ value: Double) {
        _ = setFn?(id, Float(clamp(value)))
    }
}

/// Ambient light sensor through the private IOHIDEventSystemClient API.
final class LightSensor {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    private static let ambientLightEvent: Int64 = 12
    private static let luxField: Int32 = 12 << 16

    private let copyEvent: CopyEvent?
    private let getFloat: GetFloat?
    private var services: [AnyObject] = []
    private var client: AnyObject?

    init() {
        let lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func fn<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(lib, name).map { unsafeBitCast($0, to: type) }
        }
        copyEvent = fn("IOHIDServiceClientCopyEvent", CopyEvent.self)
        getFloat = fn("IOHIDEventGetFloatValue", GetFloat.self)
        guard let create = fn("IOHIDEventSystemClientCreate", Create.self),
              let setMatching = fn("IOHIDEventSystemClientSetMatching", SetMatching.self),
              let copyServices = fn("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let c = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        setMatching(c, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4] as CFDictionary)
        client = c
        services = copyServices(c)?.takeRetainedValue() as? [AnyObject] ?? []
    }

    var available: Bool { !services.isEmpty }

    /// Current light level in lux, or nil when there is no sensor.
    func lux() -> Double? {
        guard let copyEvent, let getFloat else { return nil }
        for service in services {
            if let event = copyEvent(service, Self.ambientLightEvent, 0, 0)?.takeRetainedValue() {
                return max(getFloat(event, Self.luxField), 0)
            }
        }
        return nil
    }
}
