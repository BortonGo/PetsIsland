import CoreTransferable
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The same PNG is used for preview, sharing and Files. No temporary copy or
/// new persisted state is needed; the album already owns the complete memory.
struct PetWalkPostcardFile: FileDocument, Transferable, Sendable {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data
    let filename: String

    init(data: Data, memoryID: UUID) {
        self.data = data
        filename = "Pet-Island-Postcard-\(memoryID.uuidString)"
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        filename = "Pet-Island-Postcard"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { $0.filename + ".png" }
    }
}

struct PetWalkPostcard {
    let image: UIImage
    let file: PetWalkPostcardFile

    /// Render only when the postcard is opened. A fixed print layout keeps
    /// export quality independent of screen size, theme and accessibility size.
    @MainActor
    static func render(memory: PetDiscoveryMemory, locale: Locale = .current,
                       timeZone: TimeZone = .current) throws -> Self {
        let renderer = ImageRenderer(content: PetWalkPostcardArtwork(memory: memory)
            .environment(\.locale, locale)
            .environment(\.timeZone, timeZone)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .medium))
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return Self(image: image, file: PetWalkPostcardFile(data: data, memoryID: memory.id))
    }
}

/// This is a still composition of existing artwork, not another sprite set.
/// Text has natural height so long names and translated stories never truncate.
struct PetWalkPostcardArtwork: View {
    let memory: PetDiscoveryMemory
    private let ink = Color(red: 0.18, green: 0.21, blue: 0.23)
    private let muted = Color(red: 0.39, green: 0.43, blue: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "A little adventure", table: "WalkPostcards"))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(muted)
                    Text(memory.pet.name)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "pawprint")
                    .font(.system(size: 24, weight: .light))
                    .frame(width: 54, height: 54)
                    .overlay(Circle().stroke(muted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .foregroundStyle(muted)
                    .rotationEffect(.degrees(-12))
            }
            PetWalkPostcardScene(pet: memory.pet, route: memory.route)
                .frame(height: 328)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    DiscoveryIllustration(kind: memory.discovery, size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(memory.discovery.discoveryTitle)
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        Label(memory.route.discoveryTitle, systemImage: memory.route.discoverySymbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(muted)
                    }
                }
                Text(memory.storyText)
                    .font(.system(size: 20))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(muted.opacity(0.18)).frame(height: 1)
            HStack {
                Text(memory.foundAt, format: .dateTime.day().month(.wide).year())
                Spacer()
                Text(verbatim: "Pet Island").fontWeight(.semibold)
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(muted)
        }
        .foregroundStyle(ink)
        .padding(24)
        .frame(width: 540)
        .background(Color(red: 0.985, green: 0.975, blue: 0.95))
    }
}

struct PetWalkPostcardScene: View {
    let pet: PetProfile
    let route: PetWalkRoute

    var body: some View {
        GeometryReader { geometry in
            let ground = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.82)
            ZStack {
                DiscoveryLandscape(route: route)
                Ellipse().fill(.black.opacity(0.13))
                    .frame(width: 116, height: 10)
                    .position(ground)
                PetArtwork(species: pet.species, coat: pet.coat, customColor: pet.customColor,
                           breed: pet.resolvedBreed, pose: pet.species == .parrot ? .fly : .idle,
                           animatesMotion: false, accessory: pet.outfit?.headwear)
                    .frame(width: 220, height: 176)
                    // Use the established 220 × 176 canvas, ground at y = 160.
                    .position(x: ground.x, y: ground.y - 72)
                DiscoveryLandscape(route: route, foreground: true)
            }
        }
        .accessibilityHidden(true)
    }
}

struct PetWalkPostcardView: View {
    let memory: PetDiscoveryMemory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var postcard: PetWalkPostcard?
    @State private var renderingFailed = false
    @State private var exportsFile = false
    @State private var saved = false
    @State private var exportFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let postcard {
                        Image(uiImage: postcard.image)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PetDesign.separator, lineWidth: 1))
                            .accessibilityLabel("\(memory.pet.name), \(memory.route.discoveryTitle)")
                            .accessibilityValue(Text("\(memory.shareText)\n") + Text(memory.foundAt, format: .dateTime.day().month().year()))
                            .accessibilityIdentifier("postcard.image")
                        Text(String(localized: "A keepsake from this walk, with your companion just as they were.", table: "WalkPostcards"))
                            .font(.subheadline).foregroundStyle(PetDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ShareLink(item: postcard.file, preview: SharePreview(memory.discovery.discoveryTitle,
                                                                            image: Image(uiImage: postcard.image))) {
                            Label(String(localized: "Share postcard", table: "WalkPostcards"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PetPrimaryButtonStyle())
                        .accessibilityIdentifier("postcard.share")
                        Button { saved = false; exportsFile = true } label: {
                            Label(String(localized: "Save to Files", table: "WalkPostcards"), systemImage: "folder")
                        }
                        .buttonStyle(PetQuietButtonStyle())
                        .accessibilityIdentifier("postcard.save")
                        if saved {
                            Label(String(localized: "Postcard saved.", table: "WalkPostcards"), systemImage: "checkmark.circle")
                                .font(.subheadline).accessibilityIdentifier("postcard.saved")
                        }
                    } else if renderingFailed {
                        ContentUnavailableView {
                            Label(String(localized: "Could not create postcard", table: "WalkPostcards"), systemImage: "photo")
                        } actions: {
                            Button(String(localized: "Try again", table: "WalkPostcards")) { render() }
                                .buttonStyle(PetQuietButtonStyle())
                        }
                    } else {
                        ProgressView(String(localized: "Creating postcard…", table: "WalkPostcards"))
                            .padding(40)
                    }
                }
                .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .petPage()
            .navigationTitle(String(localized: "Walk postcard", table: "WalkPostcards"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled, postcard == nil else { return }
            render()
        }
        .fileExporter(isPresented: $exportsFile, document: postcard?.file, contentType: .png,
                      defaultFilename: postcard?.file.filename) { result in
            switch result {
            case .success: saved = true
            case .failure(let error):
                let error = error as NSError
                if error.domain != NSCocoaErrorDomain || error.code != NSUserCancelledError { exportFailed = true }
            }
        }
        .alert(String(localized: "Could not save postcard", table: "WalkPostcards"), isPresented: $exportFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(String(localized: "Please try again or choose another folder.", table: "WalkPostcards"))
        }
    }

    private func render() {
        do {
            postcard = try PetWalkPostcard.render(memory: memory, locale: locale, timeZone: timeZone)
            renderingFailed = false
        } catch { renderingFailed = true }
    }
}
