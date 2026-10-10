import Foundation
import SwiftUI
import CoreText
import UIKit

enum PetAccessory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case knitHat, tinyCrown, ribbonBow
    var id: String { rawValue }
    var price: Int {
        switch self { case .knitHat: 70; case .tinyCrown: 110; case .ribbonBow: 50 }
    }
    var title: String {
        switch self {
        case .knitHat: String(localized: "Cloud beanie")
        case .tinyCrown: String(localized: "Little crown")
        case .ribbonBow: String(localized: "Berry bow")
        }
    }
}

struct PetOutfit: Codable, Equatable, Hashable, Sendable {
    var headwear: PetAccessory?
    init(headwear: PetAccessory? = nil) { self.headwear = headwear }
    private enum CodingKeys: String, CodingKey { case headwear }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headwear = (try container.decodeIfPresent(String.self, forKey: .headwear)).flatMap(PetAccessory.init(rawValue:))
    }
}

/// Every accessory uses a complete authored outfit frame. The small patterns
/// below are shop icons; they are never stamped over the pet at runtime.
enum PetAccessoryAssets {
    struct Pattern: Decodable {
        let palette: [String: String]
        let rows: [String]
        var width: Int { rows.map(\.count).max() ?? 0 }
    }
    struct Catalog: Decodable {
        let version: Int
        let art: [String: Pattern]
        let anchors: [String: [CGFloat]]
        let poses: [String: HeadPose]
        // Item-specific fits use the same source-image coordinates as anchors.
        // A beanie wraps the head; a crown or bow sits on top of it.
        let fits: [String: [String: [CGFloat]]]
    }
    struct HeadPose: Decodable {
        // Source-image coordinates: degrees clockwise, perspective width,
        // fabric compression, and sideways flex as a fraction of brim width.
        let angle: CGFloat
        let width: CGFloat
        let height: CGFloat
        let bend: CGFloat
    }
    final class Raster: NSObject {
        let image: UIImage
        let sourceBounds: CGRect
        init(image: UIImage, sourceBounds: CGRect) {
            self.image = image
            self.sourceBounds = sourceBounds
        }
    }
    static let catalog: Catalog? = {
        guard let url = Bundle.main.url(forResource: "PetAccessories", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }()

    // Undeformed icons for the shop and wardrobe tiles.
    static let images: [PetAccessory: UIImage] = Dictionary(uniqueKeysWithValues: PetAccessory.allCases.compactMap { accessory in
        guard let pattern = catalog?.art[accessory.rawValue], pattern.width > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: pattern.width, height: pattern.rows.count), format: format).image { renderer in
            let context = renderer.cgContext
            context.setShouldAntialias(false)
            for (y, row) in pattern.rows.enumerated() {
                for (x, cell) in row.enumerated() {
                    guard let hex = pattern.palette[String(cell)], let rgb = UInt32(hex, radix: 16) else { continue }
                    context.setFillColor(UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                                                 green: CGFloat((rgb >> 8) & 255) / 255,
                                                 blue: CGFloat(rgb & 255) / 255, alpha: 1).cgColor)
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return (accessory, image)
    })

    static func raster(for accessory: PetAccessory, assetName: String) -> Raster? {
        PetDressedAssets.frame(for: accessory, assetName: assetName)?.ink
    }

    static func frame(for accessory: PetAccessory, assetName: String,
                      geometry: PetSpriteGeometry, viewport: CGSize) -> CGRect? {
        guard let raster = raster(for: accessory, assetName: assetName) else { return nil }
        let rect = geometry.rect(in: viewport)
        let scale = rect.width / geometry.sourceSize.width
        let bounds = raster.sourceBounds
        return CGRect(x: rect.minX + bounds.minX * scale, y: rect.minY + bounds.minY * scale,
                      width: bounds.width * scale, height: bounds.height * scale)
    }
}

/// Alternate complete sprites share the original source canvas and registration.
/// The ink contains the accessory pixels of that same frame, preserving its
/// colours when a custom coat is applied to the animal.
enum PetDressedAssets {
    final class Frame: NSObject {
        let image: UIImage
        let ink: PetAccessoryAssets.Raster
        init(image: UIImage, ink: PetAccessoryAssets.Raster) {
            self.image = image
            self.ink = ink
        }
    }
    struct Entry: Decodable { let inkBounds: [CGFloat] }
    private static let manifests: [PetAccessory: [String: Entry]] = Dictionary(uniqueKeysWithValues:
        PetAccessory.allCases.map { accessory in
            let folder = "PetOutfits/\(accessory.rawValue)"
            guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: folder),
                  let data = try? Data(contentsOf: url),
                  let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
                return (accessory, [:])
            }
            return (accessory, entries)
        })
    static func manifest(for accessory: PetAccessory) -> [String: Entry] { manifests[accessory] ?? [:] }
    private static let cache: NSCache<NSString, Frame> = {
        let cache = NSCache<NSString, Frame>()
        cache.countLimit = 64
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    static func frame(for accessory: PetAccessory = .knitHat, assetName: String) -> Frame? {
        let key = "\(accessory.rawValue):\(assetName)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let folder = "PetOutfits/\(accessory.rawValue)"
        guard let entry = manifest(for: accessory)[assetName], entry.inkBounds.count == 4,
              let fullURL = Bundle.main.url(forResource: assetName, withExtension: "png", subdirectory: folder),
              let inkURL = Bundle.main.url(forResource: assetName + "-ink", withExtension: "png", subdirectory: folder),
              let full = UIImage(contentsOfFile: fullURL.path),
              let color = UIImage(contentsOfFile: inkURL.path)?.cgImage else { return nil }
        let b = entry.inkBounds
        let bounds = CGRect(x: b[0], y: b[1], width: b[2] - b[0], height: b[3] - b[1])
        guard let cropped = color.cropping(to: bounds) else { return nil }
        let frame = Frame(image: full, ink: PetAccessoryAssets.Raster(image: UIImage(cgImage: cropped), sourceBounds: bounds))
        cache.setObject(frame, forKey: key, cost: Int(full.size.width * full.size.height * 4) + color.bytesPerRow * color.height)
        return frame
    }
}

struct PetAccessoryArtwork: View {
    let accessory: PetAccessory
    var body: some View {
        if let image = PetAccessoryAssets.images[accessory] {
            Image(uiImage: image).resizable().interpolation(.none)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

struct PetAccessoryOverlay: View {
    let accessory: PetAccessory
    let assetName: String
    let surface: PetArtworkSurface
    var body: some View {
        GeometryReader { proxy in
            if let raster = PetAccessoryAssets.raster(for: accessory, assetName: assetName),
               let geometry = PetSpriteGeometry.load(assetName: assetName, surface: surface),
               let frame = PetAccessoryAssets.frame(for: accessory, assetName: assetName,
                                                   geometry: geometry, viewport: proxy.size) {
                Image(uiImage: raster.image).resizable().interpolation(.none)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum PetAccessoryTimerFonts {
    /// Production reads its own extension bundle. App-hosted render tests and
    /// previews can read the embedded extension, without shipping a second copy.
    static let resourceDirectory: URL? = {
        if let index = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "PetOutfitFonts") {
            return index.deletingLastPathComponent()
        }
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let bundle = Bundle(url: plugins.appendingPathComponent("PetIslandLiveActivity.appex")),
              let index = bundle.url(forResource: "index", withExtension: "json", subdirectory: "PetOutfitFonts") else { return nil }
        return index.deletingLastPathComponent()
    }()
    private static let registry = Registry(directory: resourceDirectory)

    /// One collection contains only one breed's accessory (24 timer faces).
    /// Registration and successful lookups are shared across SwiftUI renders.
    final class Registry {
        private let directory: URL?
        private let index: [String: String]
        private let lock = NSLock()
        private var registered = Set<String>()
        private var resolved = Set<String>()

        init(directory: URL?) {
            self.directory = directory
            if let url = directory?.appendingPathComponent("index.json"),
               let data = try? Data(contentsOf: url),
               let index = try? JSONDecoder().decode([String: String].self, from: data) {
                self.index = index
            } else {
                index = [:]
            }
        }

        var loadedCollectionCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return registered.count
        }

        func fontName(_ name: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            if resolved.contains(name) { return name }
            guard let resource = index[name], let directory else { return nil }
            if !registered.contains(resource) {
                let url = directory.appendingPathComponent(resource).appendingPathExtension("ttc")
                // CoreText may report "already registered" when a preview has
                // loaded this collection. Verify the requested face either way.
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            guard CTFontCopyPostScriptName(font) as String == name else { return nil }
            registered.insert(resource)
            resolved.insert(name)
            return name
        }
    }

    static func name(baseFontName: String, accessory: PetAccessory) -> String? {
        let name = baseFontName.replacingOccurrences(of: "PetIsland", with: "PetAccessory") + accessory.rawValue
        return registry.fontName(name)
    }
    static func dressedName(baseFontName: String, accessory: PetAccessory = .knitHat) -> String? {
        let name = baseFontName.replacingOccurrences(of: "PetIsland", with: "PetDressed") + accessory.rawValue
        return registry.fontName(name)
    }
}

/// The complete outfit replaces the bare pet glyph. Both the authored sprite
/// and its colour-preservation mask use the same system timer.
struct PetOutfittedTimerGlyph: View {
    let timerStart: Date
    let timerEnd: Date
    let baseFontName: String
    let viewport: CGSize
    let direction: PetDirection
    let species: PetSpecies
    let coat: PetCoat
    let customColor: PetColorSelection?
    let accessory: PetAccessory?

    var body: some View {
        let dressed = accessory.flatMap { PetAccessoryTimerFonts.dressedName(baseFontName: baseFontName, accessory: $0) }
        PetTimerGlyph(timerStart: timerStart, timerEnd: timerEnd, fontName: dressed ?? baseFontName,
                      viewport: viewport, direction: direction)
            .petCoat(species: species, coat: coat, customColor: customColor)
            .overlay {
                if coat != .sunrise || customColor != nil, let accessory, dressed != nil,
                   let font = PetAccessoryTimerFonts.name(baseFontName: baseFontName, accessory: accessory) {
                    PetTimerGlyph(timerStart: timerStart, timerEnd: timerEnd, fontName: font,
                                  viewport: viewport, direction: direction)
                        .accessibilityHidden(true)
                }
            }
    }
}
