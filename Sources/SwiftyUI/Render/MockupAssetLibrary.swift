import AppKit
import SwiftUI

/// One bitmap the renderer can resolve from `Image("name")`. The host maps its own storage
/// into these records; the renderer never sees SwiftData.
public nonisolated struct MockupAssetRecord: Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var data: Data
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(id: UUID, name: String, data: Data, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.name = name
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Resolves `Image("name")` references in the rendered tree. Decoding is lazy and cached by
/// name — asset bytes never change after import, only the name, so `update(from:)` only
/// invalidates entries whose `(id, name)` pair changed.
@MainActor
public final class MockupAssetLibrary {
    public private(set) var names: [String] = []
    private var byName: [String: MockupAssetRecord] = [:]
    private var decoded: [String: NSImage] = [:]
    private var fingerprint: [UUID: String] = [:]

    public init() {}

    public func update(from records: [MockupAssetRecord]) {
        let incoming = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.name) })
        if incoming != fingerprint {
            decoded.removeAll()
        }
        fingerprint = incoming
        byName = Dictionary(uniqueKeysWithValues: records.map { ($0.name, $0) })
        names = records.map(\.name)
    }

    /// Dimensions of an asset, for the "no `.resizable()`" safety cap in `MockNodeView`.
    public func pixelSize(named name: String) -> CGSize? {
        guard let asset = byName[name] else { return nil }
        return CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
    }

    public func image(named name: String) -> NSImage? {
        if let cached = decoded[name] { return cached }
        guard let asset = byName[name], let image = NSImage(data: asset.data) else { return nil }
        decoded[name] = image
        return image
    }
}

public extension EnvironmentValues {
    @Entry var mockupAssets: MockupAssetLibrary? = nil
}
