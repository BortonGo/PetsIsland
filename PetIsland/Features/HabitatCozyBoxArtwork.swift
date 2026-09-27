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
