import SwiftUI

/// Two registered layers let an existing cat sprite sit inside the box.
/// Both layers must share the same frame; the enclosure owns positioning and interaction.
struct HabitatCozyBoxArtwork: View {
    enum Layer {
        case back
        case front
    }

    static let aspectRatio: CGFloat = 1.4
    /// The cardboard rests at y = 94; the last six units contain its soft pixel shadow.
    static let groundAnchor = UnitPoint(x: 0.5, y: 0.94)
    /// A useful target for the cat's middle, measured in the shared artwork canvas.
    static let openingCenter = UnitPoint(x: 0.5, y: 0.46)

    let layer: Layer

    var body: some View {
        Canvas { context, size in
            var drawing = context
            drawing.scaleBy(x: size.width / 140, y: size.height / 100)
            switch layer {
            case .back: Self.drawBack(in: drawing)
            case .front: Self.drawFront(in: drawing)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func drawBack(in context: GraphicsContext) {
        // The rear flap stays behind ears and tails. Its stair-step silhouette is
        // deliberately drawn as filled pixels rather than an antialiased stroke.
        polygon([
            (28, 14), (31, 14), (31, 10), (37, 10), (37, 8),
            (103, 8), (103, 10), (109, 10), (109, 14), (113, 14),
            (113, 23), (117, 23), (117, 30), (122, 30), (122, 41),
            (20, 41), (20, 32), (24, 32), (24, 24), (28, 24)
        ], color: Palette.outline, in: context)
        polygon([
            (32, 17), (35, 17), (35, 14), (39, 14), (39, 12),
            (101, 12), (101, 14), (106, 14), (106, 18), (109, 18),
            (109, 26), (113, 26), (113, 34), (116, 34), (116, 37),
            (26, 37), (26, 33), (29, 33), (29, 26), (32, 26)
        ], color: Palette.cardboard, in: context)
        rect(39, 12, 62, 3, color: Palette.highlight, in: context)
        rect(35, 15, 4, 3, color: Palette.highlight, in: context)
        rect(106, 23, 3, 11, color: Palette.edge, in: context)
        rect(34, 32, 75, 4, color: Palette.fold, in: context)
        rect(41, 19, 8, 2, color: Palette.grain, in: context)
        rect(82, 25, 13, 2, color: Palette.grain, in: context)

        // The dark interior is a single quiet shape; no extra animal outline is
        // painted into it, so every breed keeps its own approved silhouette.
        polygon([
            (24, 32), (116, 32), (116, 35), (124, 35), (124, 40),
            (128, 40), (128, 65), (123, 65), (123, 71), (18, 71),
            (18, 65), (12, 65), (12, 41), (17, 41), (17, 36), (24, 36)
        ], color: Palette.outline, in: context)
        polygon([
            (26, 36), (114, 36), (114, 39), (121, 39), (121, 44),
            (124, 44), (124, 63), (120, 63), (120, 67), (22, 67),
            (22, 62), (16, 62), (16, 44), (21, 44), (21, 39), (26, 39)
        ], color: Palette.interior, in: context)
        rect(28, 36, 85, 4, color: Palette.innerRim, in: context)
        rect(24, 57, 93, 10, color: Palette.innerFloor, in: context)
        rect(20, 47, 4, 15, color: Palette.fold, in: context)
        rect(117, 45, 4, 17, color: Palette.fold, in: context)
    }

    private static func drawFront(in context: GraphicsContext) {
        // A stepped shadow grounds the box without a blurry halo around the art.
        rect(24, 94, 94, 3, color: .black.opacity(0.11), in: context)
        rect(31, 97, 80, 2, color: .black.opacity(0.06), in: context)

        // The left and right flaps open toward the viewer, framing the cat.
        polygon([
            (15, 38), (24, 38), (24, 42), (30, 42), (30, 46),
            (34, 46), (34, 55), (30, 55), (30, 61), (24, 61),
            (24, 66), (17, 66), (17, 62), (10, 62), (10, 58),
            (5, 58), (5, 51), (2, 51), (2, 44), (9, 44), (9, 41), (15, 41)
        ], color: Palette.outline, in: context)
        polygon([
            (17, 42), (21, 42), (21, 46), (27, 46), (27, 49),
            (30, 49), (30, 54), (26, 54), (26, 59), (21, 59),
            (21, 61), (18, 61), (18, 58), (12, 58), (12, 54),
            (9, 54), (9, 48), (13, 48), (13, 45), (17, 45)
        ], color: Palette.highlight, in: context)
        rect(17, 48, 4, 7, color: Palette.cardboard, in: context)
        rect(21, 54, 4, 5, color: Palette.cardboard, in: context)

        polygon([
            (116, 38), (124, 38), (124, 42), (131, 42), (131, 46),
            (137, 46), (137, 55), (132, 55), (132, 60), (125, 60),
            (125, 65), (119, 65), (119, 61), (112, 61), (112, 55),
            (106, 55), (106, 46), (111, 46), (111, 42), (116, 42)
        ], color: Palette.outline, in: context)
        polygon([
            (118, 43), (122, 43), (122, 46), (128, 46), (128, 49),
            (132, 49), (132, 52), (128, 52), (128, 56), (122, 56),
            (122, 60), (120, 60), (120, 57), (115, 57), (115, 52),
            (111, 52), (111, 49), (116, 49), (116, 46), (118, 46)
        ], color: Palette.cardboard, in: context)
        rect(120, 46, 3, 9, color: Palette.highlight, in: context)
        rect(115, 50, 3, 4, color: Palette.highlight, in: context)

        // The front wall covers only the lower body. Keeping this edge flat
        // avoids introducing any apparent bounce when the cat changes pose.
        polygon([
            (25, 56), (116, 56), (116, 60), (123, 60), (123, 64),
            (126, 64), (126, 87), (123, 87), (123, 92), (118, 92),
            (118, 94), (23, 94), (23, 92), (17, 92), (17, 86),
            (14, 86), (14, 64), (18, 64), (18, 60), (25, 60)
        ], color: Palette.outline, in: context)
        polygon([
            (28, 60), (113, 60), (113, 64), (119, 64), (119, 68),
            (122, 68), (122, 84), (119, 84), (119, 88), (115, 88),
            (115, 91), (26, 91), (26, 88), (21, 88), (21, 83),
            (18, 83), (18, 67), (23, 67), (23, 64), (28, 64)
        ], color: Palette.cardboard, in: context)
        rect(29, 61, 82, 4, color: Palette.highlight, in: context)
        rect(27, 66, 3, 20, color: Palette.highlight, in: context)
        rect(21, 71, 4, 13, color: Palette.edge, in: context)
        rect(115, 68, 4, 19, color: Palette.edge, in: context)
        rect(29, 87, 85, 4, color: Palette.edge, in: context)
        rect(35, 74, 9, 2, color: Palette.grain, in: context)
        rect(94, 70, 8, 2, color: Palette.grain, in: context)
        rect(90, 82, 12, 2, color: Palette.grain, in: context)

        // A little paper heart makes it a home, not a delivery parcel.
        rect(56, 69, 26, 19, color: Palette.fold, in: context)
        rect(55, 68, 26, 18, color: Palette.paper, in: context)
        rect(57, 68, 22, 2, color: Palette.paperHighlight, in: context)
        polygon([
            (61, 73), (63, 73), (63, 71), (66, 71), (66, 73),
            (69, 73), (69, 71), (72, 71), (72, 73), (75, 73),
            (75, 77), (73, 77), (73, 79), (71, 79), (71, 81),
            (69, 81), (69, 83), (67, 83), (67, 81), (65, 81),
            (65, 79), (63, 79), (63, 77), (61, 77)
        ], color: Palette.heart, in: context)
        rect(63, 73, 3, 2, color: Palette.heartHighlight, in: context)
    }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
                             color: Color, in context: GraphicsContext) {
        context.fill(Path(CGRect(x: x, y: y, width: width, height: height)),
                     with: .color(color), style: FillStyle(antialiased: false))
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)], color: Color, in context: GraphicsContext) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        path.closeSubpath()
        context.fill(path, with: .color(color), style: FillStyle(antialiased: false))
    }

    private enum Palette {
        static let outline = color(0x533B30)
        static let cardboard = color(0xCAA071)
        static let highlight = color(0xEAC799)
        static let edge = color(0xAD8056)
        static let fold = color(0x987149)
        static let grain = color(0xBA8E61)
        static let interior = color(0x614637)
        static let innerRim = color(0x92704E)
        static let innerFloor = color(0x79573D)
        static let paper = color(0xF0DEBC)
        static let paperHighlight = color(0xF9EBD0)
        static let heart = color(0xAA6E61)
        static let heartHighlight = color(0xCD9580)

        private static func color(_ value: UInt32) -> Color {
            Color(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
        }
    }
}

/// Small pixel shapes use the same palette, hard edges and layered drawing as
/// the original box. Animal artwork is always rendered separately and unchanged.
struct HabitatItemArtwork: View {
    enum Layer { case back, front, complete }
    let item: HabitatItemKind
    let layer: Layer
    var activity: Double = 0
    var active = false

    var body: some View {
        Canvas { context, size in
            var c = context
            c.scaleBy(x: size.width / 100, y: size.height / 100)
            let back = layer != .front
            let front = layer != .back
            let ink = color(0x594A46)
            switch item {
            case .cozyBox: break
            case .softBed:
                if back {
                    pixels([(8, 35), (17, 35), (17, 20), (83, 20), (83, 35), (92, 35), (92, 79), (84, 79), (84, 94), (16, 94), (16, 79), (8, 79)], ink, c)
                    rect(13, 38, 74, 38, color(0xBA8A87), c)
                    rect(20, 27, 60, 14, color(0xDDB0A5), c)
                    rect(19, 46, 62, 25, color(0xF0D3B6), c)
                    rect(25, 49, 49, 6, color(0xFFE6CA), c)
                    rect(20, 78, 60, 9, color(0xA87877), c)
                    rect(43, 80, 14, 8, color(0xF0D3B6), c)
                }
            case .leafNest:
                if back {
                    pixels([(7, 47), (17, 47), (17, 30), (29, 30), (29, 19), (70, 19), (70, 30), (84, 30), (84, 46), (94, 46), (94, 80), (82, 80), (82, 94), (20, 94), (20, 83), (7, 83)], ink, c)
                    rect(18, 38, 66, 43, color(0x896146), c)
                    rect(28, 32, 44, 31, color(0x59443A), c)
                }
                if front {
                    for i in 0..<7 {
                        let x = Double(8 + i * 12)
                        let y = Double(67 + (i % 2) * 10)
                        leaf(x, y, i % 2 == 0 ? color(0xCD9861) : color(0x9F7650), c)
                    }
                    if active {
                        for i in 0..<3 {
                            let t = (activity * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                            leaf(14 + Double(i) * 30, 52 - sin(t * .pi) * 25, color(0xD2AA71), c)
                        }
                    }
                }
            case .birdPerch:
                if back {
                    rect(14, 1, 72, 6, ink, c)
                    rect(19, 7, 5, 78, color(0xA58A68), c)
                    rect(76, 7, 5, 78, color(0xA58A68), c)
                    rect(20, 9, 2, 72, color(0xDEBD87), c)
                    rect(77, 9, 2, 72, color(0xDEBD87), c)
                }
                if front {
                    let sway = active ? sin(activity * 1.4) * 2 : 0
                    rect(12 + sway, 86, 76, 8, ink, c)
                    rect(17 + sway, 87, 66, 4, color(0xCBA170), c)
                    rect(45 + sway, 94, 10, 4, color(0x8D6847), c)
                }
            case .splashBath:
                if back {
                    pixels([(9, 35), (20, 35), (20, 19), (79, 19), (79, 35), (91, 35), (91, 76), (82, 76), (82, 94), (18, 94), (18, 76), (9, 76)], ink, c)
                    rect(14, 39, 72, 31, color(0x84BBC6), c)
                    rect(23, 26, 53, 13, color(0xB8D9D8), c)
                    rect(24, 40, 53, 19, color(0x6FA4B7), c)
                }
                if front {
                    rect(16, 68, 69, 13, color(0x9BC9CD), c)
                    rect(23, 81, 54, 7, color(0x71A2B0), c)
                    rect(23, 63, 51, 6, color(0xD0E4DB), c)
                    if active {
                        for i in 0..<3 {
                            let t = (activity * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                            rect(18 + Double(i) * 28, 54 - sin(t * .pi) * 25, 4, 8, color(0xCCE6E9), c)
                        }
                        rect(34 + sin(activity * 2) * 8, 65, 19, 3, color(0xF0F3E2), c)
                    }
                }
            case .warmStone:
                if back {
                    pixels([(4, 66), (13, 66), (13, 40), (28, 40), (28, 22), (70, 22), (70, 37), (85, 37), (85, 60), (96, 60), (96, 83), (86, 83), (86, 94), (13, 94), (13, 84), (4, 84)], ink, c)
                    rect(18, 48, 64, 32, color(0xBBA48B), c)
                    rect(30, 29, 37, 21, color(0xDDC8A8), c)
                    rect(28, 50, 47, 8, color(0xD1BA9D), c)
                    rect(15, 81, 70, 6, color(0x947E70), c)
                    rect(68, 62, 12, 6, color(0xA38D79), c)
                }
            case .playBall:
                if back {
                    let dx = active ? sin(activity * 2) * 9 : 0
                    pixels([(27 + dx, 5), (70 + dx, 5), (70 + dx, 14), (85 + dx, 14), (85 + dx, 28), (94 + dx, 28), (94 + dx, 69), (85 + dx, 69), (85 + dx, 84), (71 + dx, 84), (71 + dx, 94), (28 + dx, 94), (28 + dx, 84), (14 + dx, 84), (14 + dx, 70), (5 + dx, 70), (5 + dx, 28), (14 + dx, 28), (14 + dx, 14), (27 + dx, 14)], ink, c)
                    rect(23 + dx, 20, 53, 60, color(0xB38B83), c)
                    rect(15 + dx, 32, 70, 33, color(0xC8A396), c)
                    rect(39 + dx, 13, 19, 74, color(0xE9D3AD), c)
                    rect(23 + dx, 33, 13, 7, color(0xF2DAC4), c)
                }
            }
        }
        .aspectRatio(item.artworkAspectRatio, contentMode: .fit)
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color, _ c: GraphicsContext) {
        c.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color), style: FillStyle(antialiased: false))
    }
    private func pixels(_ points: [(Double, Double)], _ color: Color, _ c: GraphicsContext) {
        var p = Path()
        guard let first = points.first else { return }
        p.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.0, y: point.1)) }
        p.closeSubpath()
        c.fill(p, with: .color(color), style: FillStyle(antialiased: false))
    }
    private func leaf(_ x: Double, _ y: Double, _ color: Color, _ c: GraphicsContext) {
        pixels([(x, y + 6), (x + 4, y + 6), (x + 4, y), (x + 11, y), (x + 11, y + 4), (x + 15, y + 4), (x + 15, y + 12), (x + 9, y + 12), (x + 9, y + 16), (x + 2, y + 16), (x + 2, y + 11), (x, y + 11)], color, c)
    }
}
