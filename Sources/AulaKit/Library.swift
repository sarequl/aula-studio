import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A saved screen: either a media file the user picked (kept as a copy) or a generator recipe.
public struct LibraryItem: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case media, text, gradient, solid }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var added: Date
    public var lastSent: Date?
    public var frameCount: Int
    public var duration: Double

    // media
    public var fileName: String?
    public var scaleMode: String?
    public var speed: Double?
    public var videoFPS: Double?

    // text
    public var text: String?
    public var fontName: String?
    public var fontSize: Double?
    public var scrollSpeed: Double?
    public var color: [UInt8]?
    public var background: [UInt8]?

    // gradient / solid
    public var preset: String?
    public var animated: Bool?

    public init(id: UUID = UUID(), name: String, kind: Kind, frameCount: Int, duration: Double) {
        self.id = id
        self.name = name
        self.kind = kind
        self.added = Date()
        self.frameCount = frameCount
        self.duration = duration
    }
}

/// Persists library items under Application Support, with a PNG thumbnail and, for
/// media, a private copy of the source file so it survives the original moving.
public final class LibraryStore {
    public let root: URL
    private let indexURL: URL

    public init(directory: URL? = nil) throws {
        let base = try directory ?? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AulaStudio/Library", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base
        indexURL = base.appendingPathComponent("index.json")
    }

    public func load() -> [LibraryItem] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([LibraryItem].self, from: data)) ?? []
    }

    public func save(_ items: [LibraryItem]) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(items).write(to: indexURL, options: .atomic)
    }

    public func thumbnailURL(_ item: LibraryItem) -> URL { root.appendingPathComponent("\(item.id.uuidString).png") }
    public func mediaURL(_ item: LibraryItem) -> URL? { item.fileName.map { root.appendingPathComponent($0) } }

    /// Copies the source file in and writes the thumbnail from the rendered first frame.
    public func store(_ item: inout LibraryItem, sourceFile: URL?, thumbnail: CGImage) throws {
        if let src = sourceFile {
            let name = "\(item.id.uuidString).\(src.pathExtension)"
            let dst = root.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: src, to: dst)
            item.fileName = name
        }
        guard let dest = CGImageDestinationCreateWithURL(thumbnailURL(item) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw AulaError.badBuffer("could not write thumbnail")
        }
        CGImageDestinationAddImage(dest, thumbnail, nil)
        CGImageDestinationFinalize(dest)
    }

    public func remove(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: thumbnailURL(item))
        if let m = mediaURL(item) { try? FileManager.default.removeItem(at: m) }
    }
}
