import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import Vision
import XCTest
@testable import PetIsland

@MainActor
final class PetWalkPostcardTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let locale = Locale(identifier: "en_US")
    private let zone = TimeZone(secondsFromGMT: 0)!

    private func memory(kind: PetDiscoveryKind = .shell, story: PetWalkStory? = .curious,
                        pet: PetProfile? = nil) throws -> PetDiscoveryMemory {
        let companion = pet ?? PetProfile(id: UUID(), name: "Pixel", species: .cat, coat: .sunrise,
            createdAt: date, breed: .maineCoon, outfit: PetOutfit(headwear: .knitHat))
        return PetDiscoveryMemory(walk: try XCTUnwrap(PetDiscoveryWalk(pet: companion, route: kind.discoveryRoute,
            startedAt: date, endsAt: date.addingTimeInterval(kind.discoveryRoute.duration), discovery: kind, story: story)))
    }

    func testEveryFindAndLegacyStoryProducesACompleteOpaquePNG() throws {
        for kind in PetDiscoveryKind.allCases {
            for story in [nil, PetWalkStory.curious] {
                let memory = try memory(kind: kind, story: story)
                let postcard = try PetWalkPostcard.render(memory: memory, locale: locale, timeZone: zone)
                let image = try XCTUnwrap(UIImage(data: postcard.file.data)?.cgImage)
                XCTAssertEqual(image.width, 1080)
                XCTAssertGreaterThan(image.height, 1200)
                XCTAssertLessThan(image.height, 2400)
                XCTAssertEqual(Array(postcard.file.data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
                let pixels = try pixels(image)
                XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
                if kind == kind.discoveryRoute.discoveryIDs.first, story != nil {
                    attach(postcard.image, name: "Postcard — \(memory.route.rawValue)")
                }
            }
        }
    }

    func testSharingExportsExactlyThePreviewPNGWithASafeUniqueFilename() async throws {
        guard #available(iOS 18.2, *) else { throw XCTSkip("Transferable inspection requires iOS 18.2; sharing supports iOS 17.") }
        var pet = PetProfile.starter
        pet.name = "../Pixel : / 🐾"
        let original = try memory(pet: pet)
        let postcard = try PetWalkPostcard.render(memory: original)
        let shared = try await postcard.file.exported(as: .png)
        XCTAssertEqual(shared, postcard.file.data)
        XCTAssertEqual(postcard.file.suggestedFilename, postcard.file.filename + ".png")
        XCTAssertFalse(postcard.file.filename.contains("/"))
        XCTAssertFalse(postcard.file.filename.contains(":"))
        let another = try PetWalkPostcard.render(memory: memory(pet: pet))
        XCTAssertNotEqual(another.file.filename, postcard.file.filename)
        XCTAssertEqual(try PetWalkPostcard.render(memory: original).file.filename, postcard.file.filename)
    }

    func testSavedCompanionAndImageSurviveRenameOutfitChangeAndReload() throws {
        var pet = PetProfile.starter
        pet.outfit = PetOutfit(headwear: .tinyCrown)
        let original = try memory(pet: pet)
        let before = try PetWalkPostcard.render(memory: original, locale: locale, timeZone: zone)
        pet.name = "Another name"; pet.breed = .cardigan; pet.coat = .midnight; pet.outfit = nil
        let reloaded = try JSONDecoder().decode(PetDiscoveryMemory.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(reloaded, original)
        XCTAssertNotEqual(reloaded.pet, pet)
        let after = try PetWalkPostcard.render(memory: reloaded, locale: locale, timeZone: zone)
        XCTAssertEqual(after.file.data, before.file.data)
    }

    func testLongNameAndWholeStoryRemainReadableInTheExport() throws {
        var pet = PetProfile.starter
        pet.name = "Pixel the Fluffy Explorer of the Quiet Island and Beyond"
        let memory = try memory(kind: .mapleLeaf, story: .original, pet: pet)
        let postcard = try PetWalkPostcard.render(memory: memory, locale: locale, timeZone: zone)
        let cgImage = try XCTUnwrap(postcard.image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.contains("Quiet Island and Beyond"), text)
        let ending = memory.storyText.split(separator: " ").suffix(3).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        XCTAssertTrue(text.contains(ending), text)
        XCTAssertTrue(text.contains("Pet Island"), text)
        XCTAssertLessThan(cgImage.height, 2600)
        attach(postcard.image, name: "Postcard — long name and complete story")
    }

    func testAllTwentyCompanionsRenderWithEveryOutfitAndStayWithinTheScene() throws {
        let size = CGSize(width: 492, height: 328)
        let background = try render(DiscoveryLandscape(route: .shore).overlay {
            DiscoveryLandscape(route: .shore, foreground: true)
        }.frame(width: size.width, height: size.height))
        let backgroundPixels = try pixels(XCTUnwrap(background.cgImage))
        var images: [(String, UIImage)] = []
        for species in PetSpecies.allCases {
            for breed in PetBreed.available(for: species) {
                var previous: Data?
                for accessory in [nil] + PetAccessory.allCases.map(Optional.some) {
                    let pet = PetProfile(id: UUID(), name: breed.rawValue, species: species, coat: .sunrise,
                        createdAt: date, breed: breed, outfit: accessory.map { PetOutfit(headwear: $0) })
                    let image = try render(PetWalkPostcardScene(pet: pet, route: .shore)
                        .frame(width: size.width, height: size.height))
                    let pixels = try pixels(XCTUnwrap(image.cgImage))
                    var changed = 0
                    var staysInside = true
                    for y in 0..<Int(size.height) {
                        for x in 0..<Int(size.width) {
                            let offset = (y * Int(size.width) + x) * 4
                            if (0..<3).contains(where: { abs(Int(pixels[offset + $0]) - Int(backgroundPixels[offset + $0])) > 12 }) {
                                changed += 1
                                staysInside = staysInside && (100...390).contains(x) && (20...285).contains(y)
                            }
                        }
                    }
                    XCTAssertGreaterThan(changed, 2000, "Missing companion: \(breed)")
                    XCTAssertTrue(staysInside, "Clipped companion: \(breed), \(String(describing: accessory))")
                    let png = try XCTUnwrap(image.pngData())
                    if let previous { XCTAssertNotEqual(png, previous, "Missing outfit: \(breed)") }
                    previous = png
                    images.append(("\(breed.rawValue) · \(accessory?.rawValue ?? "none")", image))
                }
            }
        }
        // Keep a visual proof of the production scene for each approved animal.
        for page in 0..<4 {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let sheet = UIGraphicsImageRenderer(size: CGSize(width: 984, height: 920), format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 984, height: 920))
                for (index, entry) in images[(page * 20)..<((page + 1) * 20)].enumerated() {
                    let x = CGFloat(index % 4) * 246, y = CGFloat(index / 4) * 184
                    entry.1.draw(in: CGRect(x: x, y: y, width: 246, height: 164))
                    (entry.0 as NSString).draw(at: CGPoint(x: x + 5, y: y + 165), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.black])
                }
            }
            attach(sheet, name: "Postcard companions — \(page + 1)")
        }
    }

    func testCustomCoatAndAccessoryBothReachThePostcard() throws {
        var pet = PetProfile.starter
        let normal = try PetWalkPostcard.render(memory: memory(pet: pet))
        pet.customColor = PetColorSelection(red: 0.2, green: 0.7, blue: 0.9)
        let recoloredMemory = try memory(pet: pet)
        let recolored = try PetWalkPostcard.render(memory: recoloredMemory)
        pet.outfit = PetOutfit(headwear: .ribbonBow)
        let dressed = try PetWalkPostcard.render(memory: memory(pet: pet))
        XCTAssertNotEqual(normal.file.data, recolored.file.data)
        XCTAssertNotEqual(dressed.file.data, recolored.file.data)
        XCTAssertEqual(recoloredMemory.pet.customColor, pet.customColor)
        attach(dressed.image, name: "Postcard — custom coat with bow")
    }

    private func render<V: View>(_ view: V) throws -> UIImage {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0, y: CGFloat(image.height)); context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
