import Foundation
import IOKit.hid

public enum ConnectionState: Equatable, Sendable {
    case wired
    case wireless
    case absent
}

/// Enumerates HID devices without opening the manager, so the keyboard's own
/// key-input interface is never touched (that one would need Input Monitoring).
private func matchingDevices(vendor: Int, product: Int) -> [IOHIDDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [
        kIOHIDVendorIDKey: vendor,
        kIOHIDProductIDKey: product,
    ] as CFDictionary)
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    return Array(set)
}

private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int
}

private func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
}

/// The first profile that is present over USB, or over wireless.
public func detectKeyboard() -> (KeyboardProfile, ConnectionState)? {
    for p in KeyboardProfile.all where !matchingDevices(vendor: p.vendorID, product: p.productID).isEmpty {
        return (p, .wired)
    }
    for p in KeyboardProfile.all {
        guard let wv = p.wirelessVendorID, let wp = p.wirelessProductID else { continue }
        // The wireless ids reuse Apple's VID, so also check the product name.
        let wireless = matchingDevices(vendor: wv, product: wp)
        let tag = p.name.uppercased().replacingOccurrences(of: "AULA ", with: "").replacingOccurrences(of: " ", with: "")
        if wireless.contains(where: { (stringProperty($0, kIOHIDProductKey) ?? "").uppercased()
                .replacingOccurrences(of: " ", with: "").contains(tag) }) {
            return (p, .wireless)
        }
    }
    return nil
}

public func currentConnectionState() -> ConnectionState {
    detectKeyboard()?.1 ?? .absent
}

/// An open, wired AULA F108 Pro. Not thread-safe: drive it from one thread at a time.
public final class AulaDevice {
    public let profile: KeyboardProfile
    private let config: IOHIDDevice
    private let lcd: IOHIDDevice
    private var lcdActivated = false
    private let ackQueue = DispatchQueue(label: "aula.lcd.ack")
    private let ackSemaphore = DispatchSemaphore(value: 0)
    private let ackBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: F108.reportSize)

    /// Called with human-readable protocol traces. Useful for `--verbose`.
    public var log: ((String) -> Void)?

    /// Opens the given model, or whichever supported model is plugged in.
    public init(profile: KeyboardProfile? = nil) throws {
        guard let profile = profile ?? detectKeyboard().flatMap({ $0.1 == .wired ? $0.0 : nil }) else {
            throw currentConnectionState() == .wireless ? AulaError.wirelessOnly : AulaError.notFound
        }
        self.profile = profile
        let devices = matchingDevices(vendor: profile.vendorID, product: profile.productID)
        if devices.isEmpty {
            throw currentConnectionState() == .wireless ? AulaError.wirelessOnly : AulaError.notFound
        }
        func find(_ page: Int) -> IOHIDDevice? {
            devices.first { intProperty($0, kIOHIDPrimaryUsagePageKey) == page }
        }
        guard let config = find(F108.configUsagePage) else { throw AulaError.interfaceMissing("configuration (0xFF13)") }
        guard let lcd = find(F108.lcdUsagePage) else { throw AulaError.interfaceMissing("screen (0xFF68)") }

        var r = IOHIDDeviceOpen(config, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw AulaError.io("Opening configuration interface", r) }
        r = IOHIDDeviceOpen(lcd, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else {
            IOHIDDeviceClose(config, IOOptionBits(kIOHIDOptionsTypeNone))
            throw AulaError.io("Opening screen interface", r)
        }
        self.config = config
        self.lcd = lcd
    }

    deinit {
        if lcdActivated {
            // A device bound to a dispatch queue must be cancelled before release.
            let done = DispatchSemaphore(value: 0)
            IOHIDDeviceSetCancelHandler(lcd) { done.signal() }
            IOHIDDeviceCancel(lcd)
            done.wait()
        }
        IOHIDDeviceClose(lcd, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceClose(config, IOOptionBits(kIOHIDOptionsTypeNone))
        ackBuffer.deallocate()
    }

    // MARK: Feature reports (interface 3)

    private func hex(_ bytes: some Collection<UInt8>, _ n: Int = 16) -> String {
        bytes.prefix(n).map { String(format: "%02x", $0) }.joined()
    }

    private func setFeature(_ payload: [UInt8]) throws {
        var report = [UInt8](repeating: 0, count: F108.reportSize)
        report.replaceSubrange(0..<min(payload.count, F108.reportSize), with: payload.prefix(F108.reportSize))
        log?("SEND \(hex(report))")
        let r = IOHIDDeviceSetReport(config, kIOHIDReportTypeFeature, 0, report, report.count)
        guard r == kIOReturnSuccess else { throw AulaError.io("SET_REPORT", r) }
    }

    @discardableResult
    private func getFeature() throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: F108.reportSize)
        var len = CFIndex(buf.count)
        let r = IOHIDDeviceGetReport(config, kIOHIDReportTypeFeature, 0, &buf, &len)
        guard r == kIOReturnSuccess else { throw AulaError.io("GET_REPORT", r) }
        log?("RECV \(hex(buf))")
        return buf
    }

    /// The firmware ignores the next command unless each one is read back.
    private func command(_ payload: [UInt8], readback: Bool = true) throws {
        try setFeature(payload)
        Thread.sleep(forTimeInterval: F108.commandDelay)
        if readback {
            let resp = try getFeature()
            // Only `04 xx` commands answer with an ACK flag; data packets are echoed back.
            if payload.first == 0x04, resp[3] != 0x01 { log?("warning: no ACK for \(hex(payload.prefix(2)))") }
            Thread.sleep(forTimeInterval: F108.commandDelay)
        }
    }

    private func begin() throws { try command([0x04, 0x18]) }
    private func apply() throws { try command([0x04, 0x02]) }
    private func finalize() throws { try command([0x04, 0xF0], readback: false) }

    // MARK: Public API

    public func syncClock(to date: Date = Date(), calendar: Calendar = .current) throws {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        try begin()
        var initCmd = [UInt8](repeating: 0, count: 64)
        initCmd[0] = 0x04; initCmd[1] = 0x28; initCmd[8] = 0x01
        try command(initCmd)

        var data = [UInt8](repeating: 0, count: 64)
        data[1] = 0x01                               // profile
        data[2] = 0x5A                               // magic
        data[3] = UInt8((c.year ?? 2000) % 100)
        data[4] = UInt8(c.month ?? 1)
        data[5] = UInt8(c.day ?? 1)
        data[6] = UInt8(c.hour ?? 0)
        data[7] = UInt8(c.minute ?? 0)
        data[8] = UInt8(c.second ?? 0)
        data[10] = UInt8((c.weekday ?? 1) - 1)       // Foundation: 1 = Sunday; keyboard: 0 = Sunday
        data[62] = 0x55
        data[63] = 0xAA
        try command(data)
        try apply()
    }

    public func setLighting(_ cfg: LightingConfig) throws {
        try begin()
        var initCmd = [UInt8](repeating: 0, count: 64)
        initCmd[0] = 0x04; initCmd[1] = 0x13; initCmd[8] = 0x01
        try command(initCmd)

        var data = [UInt8](repeating: 0, count: 64)
        data[0] = UInt8(cfg.mode.rawValue)
        if cfg.mode != .off {
            data[1] = cfg.red
            data[2] = cfg.green
            data[3] = cfg.blue
            data[8] = cfg.colorful ? 1 : 0
            data[9] = min(cfg.brightness, 5)
            data[10] = min(cfg.speed, 5)
            data[11] = min(cfg.direction, 1)
        }
        data[14] = 0x55
        data[15] = 0xAA
        try command(data, readback: false)
        try apply()
        try finalize()
    }

    /// Sets individual key colors. Keys not in `colors` go dark. `brightness` 0...5.
    /// Sequence (from the vendor app): light-strip preamble, then `04 23` with a
    /// 576-byte table of (index, r, g, b) per light index, trailer 55 AA.
    public func setPerKeyColors(_ colors: [UInt8: (r: UInt8, g: UInt8, b: UInt8)], brightness: UInt8 = 5) throws {
        // Preamble: begin -> lighting init -> brightness -> apply -> finalize.
        try begin()
        var initCmd = [UInt8](repeating: 0, count: 64)
        initCmd[0] = 0x04; initCmd[1] = 0x13; initCmd[8] = 0x01
        try command(initCmd)
        var pre = [UInt8](repeating: 0, count: 64)
        pre[0] = 0x80
        pre[9] = min(brightness, 5)
        pre[14] = 0x55; pre[15] = 0xAA
        try command(pre, readback: false)
        try apply()
        try finalize()

        // Per-key table.
        try begin()
        var keyInit = [UInt8](repeating: 0, count: 64)
        keyInit[0] = 0x04; keyInit[1] = 0x23; keyInit[8] = 0x09   // 0x09 = RGB mode
        try command(keyInit)

        let size = 0x240
        var table = [UInt8](repeating: 0, count: size)
        for (idx, c) in colors {
            let off = Int(idx) * 4
            guard idx > 0, off + 3 < size - 2 else { continue }
            table[off] = idx
            table[off + 1] = c.r
            table[off + 2] = c.g
            table[off + 3] = c.b
        }
        table[size - 2] = 0x55
        table[size - 1] = 0xAA
        for chunk in stride(from: 0, to: size, by: F108.reportSize) {
            try setFeature(Array(table[chunk..<chunk + F108.reportSize]))
            Thread.sleep(forTimeInterval: F108.commandDelay)
        }
        try getFeature()
        Thread.sleep(forTimeInterval: F108.commandDelay)

        try apply()
        try command([0x04, 0xF0])   // this finalize is read back, unlike the lighting one
    }

    /// Sends a complete remap table for one layer. Keys absent from `map` return to
    /// factory behaviour, so an empty map is a reset. `04 11` normal layer, `04 27` FN layer.
    public func setRemap(_ map: KeyMap, fnLayer: Bool = false) throws {
        try begin()
        var initCmd = [UInt8](repeating: 0, count: 64)
        initCmd[0] = 0x04; initCmd[1] = fnLayer ? 0x27 : 0x11; initCmd[8] = 0x09
        try command(initCmd)

        let size = 0x240
        var table = [UInt8](repeating: 0, count: size)
        for (idx, action) in map {
            let off = Int(idx) * 4
            guard idx > 0, off + 3 < size - 2 else { continue }
            table.replaceSubrange(off..<off + 4, with: action.slot)
        }
        // Trailer is 0x55AA little-endian here (AA 55 on the wire), the opposite
        // byte order from the lighting packets. The firmware silently ignores the
        // table if this is wrong.
        table[size - 2] = 0xAA
        table[size - 1] = 0x55
        for chunk in stride(from: 0, to: size, by: F108.reportSize) {
            try setFeature(Array(table[chunk..<chunk + F108.reportSize]))
            Thread.sleep(forTimeInterval: F108.commandDelay)
        }

        try apply()
        try command([0x04, 0xF0])
    }

    // MARK: LCD upload (interface 2)

    private func activateLCD() {
        guard !lcdActivated else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(lcd, ackBuffer, F108.reportSize, { ctx, _, _, _, _, _, _ in
            guard let ctx else { return }
            Unmanaged<AulaDevice>.fromOpaque(ctx).takeUnretainedValue().ackSemaphore.signal()
        }, context)
        IOHIDDeviceSetDispatchQueue(lcd, ackQueue)
        IOHIDDeviceActivate(lcd)
        lcdActivated = true
    }

    /// Uploads a buffer built by `LCDImage.encode`. Blocks for the whole transfer
    /// (about 150 ms per 4 KB page, so a full 141-frame animation takes ~5.5 min).
    public func uploadScreen(_ buffer: Data, progress: ((Int, Int) -> Void)? = nil) throws {
        // Re-validate here as the last line of defence for the flash layout.
        guard !buffer.isEmpty, buffer.count % F108.pageSize == 0 else {
            throw AulaError.badBuffer("size \(buffer.count) is not a multiple of \(F108.pageSize)")
        }
        let frames = Int(buffer[buffer.startIndex])
        guard frames >= 1 else { throw AulaError.badBuffer("zero frames") }
        guard frames <= profile.maxFrames else { throw AulaError.tooManyFrames(frames, limit: profile.maxFrames) }
        let pages = buffer.count / F108.pageSize
        let expectedPages = profile.pageCount(frames: frames)
        guard pages == expectedPages, pages <= profile.maxPages else {
            throw AulaError.badBuffer("\(pages) pages for \(frames) frames (expected \(expectedPages))")
        }

        activateLCD()
        while ackSemaphore.wait(timeout: .now()) == .success {}

        try begin()
        var header = [UInt8](repeating: 0, count: 64)
        header[0] = 0x04; header[1] = 0x72
        header[2] = 0x01                              // image slot 1
        header[8] = UInt8(pages & 0xFF)
        header[9] = UInt8((pages >> 8) & 0xFF)
        try command(header)

        var missedAcks = 0
        try buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<pages {
                // Output reports go out on the interrupt OUT endpoint (EP3). Sending
                // these as control transfers crashes the firmware.
                let r = IOHIDDeviceSetReport(lcd, kIOHIDReportTypeOutput, 0, base + i * F108.pageSize, F108.pageSize)
                guard r == kIOReturnSuccess else { throw AulaError.io("Writing screen page \(i + 1)/\(pages)", r) }
                if ackSemaphore.wait(timeout: .now() + 1.0) == .timedOut {
                    missedAcks += 1
                    log?("warning: no ack for page \(i + 1)")
                }
                progress?(i + 1, pages)
            }
        }
        if missedAcks > 0 { log?("\(missedAcks) page acks missed") }
        try apply()
    }
}
