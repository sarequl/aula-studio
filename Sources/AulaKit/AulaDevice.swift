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

public func currentConnectionState() -> ConnectionState {
    if !matchingDevices(vendor: F108.vendorID, product: F108.productID).isEmpty { return .wired }
    // The wireless modes reuse Apple's VID, so also check the product name.
    let wireless = matchingDevices(vendor: F108.wirelessVendorID, product: F108.wirelessProductID)
    if wireless.contains(where: { (stringProperty($0, kIOHIDProductKey) ?? "").uppercased().contains("F108") }) {
        return .wireless
    }
    return .absent
}

/// An open, wired AULA F108 Pro. Not thread-safe: drive it from one thread at a time.
public final class AulaDevice {
    private let config: IOHIDDevice
    private let lcd: IOHIDDevice
    private var lcdActivated = false
    private let ackQueue = DispatchQueue(label: "aula.lcd.ack")
    private let ackSemaphore = DispatchSemaphore(value: 0)
    private let ackBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: F108.reportSize)

    /// Called with human-readable protocol traces. Useful for `--verbose`.
    public var log: ((String) -> Void)?

    public init() throws {
        let devices = matchingDevices(vendor: F108.vendorID, product: F108.productID)
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
            if resp[3] != 0x01 { log?("warning: no ACK for \(hex(payload.prefix(2)))") }
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
    /// (roughly 70 ms per 4 KB page, so a full 141-frame animation takes ~2.5 min).
    public func uploadScreen(_ buffer: Data, progress: ((Int, Int) -> Void)? = nil) throws {
        // Re-validate here as the last line of defence for the flash layout.
        guard !buffer.isEmpty, buffer.count % F108.pageSize == 0 else {
            throw AulaError.badBuffer("size \(buffer.count) is not a multiple of \(F108.pageSize)")
        }
        let frames = Int(buffer[buffer.startIndex])
        guard frames >= 1 else { throw AulaError.badBuffer("zero frames") }
        guard frames <= F108.maxFrames else { throw AulaError.tooManyFrames(frames) }
        let pages = buffer.count / F108.pageSize
        let expectedPages = (F108.headerBytes + frames * F108.frameBytes + F108.pageSize - 1) / F108.pageSize
        guard pages == expectedPages, pages <= F108.maxPages else {
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
