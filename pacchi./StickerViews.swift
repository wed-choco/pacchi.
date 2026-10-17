import SwiftUI

struct StickerSilhouette: Shape {
    let kind: StickerShape
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint]
        switch kind {
        case .circle: return Path(ellipseIn: rect)
        case .rectangle: return Path(roundedRect: rect, cornerRadius: rect.width * 0.08)
        case .heart:
            points = [(0.05,0.18),(0.18,0.05),(0.35,0.05),(0.5,0.2),(0.65,0.05),(0.82,0.05),(0.95,0.18),(0.95,0.43),(0.5,0.95),(0.05,0.43)].map { CGPoint(x: rect.minX + $0.0 * rect.width, y: rect.minY + $0.1 * rect.height) }
        case .bow:
            points = [(0.03,0.12),(0.43,0.35),(0.57,0.35),(0.97,0.12),(0.97,0.88),(0.57,0.65),(0.43,0.65),(0.03,0.88)].map { CGPoint(x: rect.minX + $0.0 * rect.width, y: rect.minY + $0.1 * rect.height) }
        case .star:
            points = (0..<10).map { i in
                let angle = Double(i) * .pi / 5 - .pi / 2
                let radius = i.isMultiple(of: 2) ? 0.5 : 0.23
                return CGPoint(x: rect.midX + cos(angle) * radius * rect.width, y: rect.midY + sin(angle) * radius * rect.height)
            }
        }
        path.addLines(points); path.closeSubpath(); return path
    }
}

struct StickerArtwork: View {
    let sticker: MemorySticker
    let store: MemoryStore
    var monochrome = false
    var body: some View {
        GeometryReader { proxy in
            let shape = StickerSilhouette(kind: sticker.shape)
            ZStack {
                shape.fill(monochrome ? PhonePalette.lcd : Color(red: 1, green: 0.96, blue: 0.86))
                if let image = store.image(sticker.imageReference) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipShape(shape)
                } else {
                    PixelMotif(type: sticker.type, asset: sticker.assetId)
                        .padding(proxy.size.width * 0.22)
                        .foregroundStyle(monochrome ? PhonePalette.ink : PhonePalette.edge)
                }
                shape.stroke(monochrome ? PhonePalette.ink : .white, style: StrokeStyle(lineWidth: 2, dash: [2, 1]))
            }.saturation(monochrome ? 0 : 1)
        }
        .accessibilityLabel(sticker.title)
    }
}

struct PixelMotif: View {
    var type: MemoryStickerType = .handmade
    var asset: String?
    var body: some View {
        Canvas { context, size in
            let rows: [String]
            switch type {
            case .firstHello: rows = ["1111111", "1101011", "1011101", "1111111", "1111111"]
            case .firstPhoto: rows = ["0011100", "1111111", "1101011", "1101011", "1111111"]
            case .anniversary: rows = ["0100010", "1111111", "1000001", "1010101", "1001001", "1111111"]
            case .birthday: rows = ["0010100", "0010100", "0111110", "0101010", "1111111", "1111111"]
            default:
                if asset == "pixel-star" { rows = ["0001000", "0011100", "1111111", "0111110", "0011100", "0100010"] }
                else if asset == "pixel-bow" { rows = ["1100011", "1110111", "0111110", "1110111", "1100011"] }
                else { rows = ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"] }
            }
            let unit = min(size.width / 7, size.height / CGFloat(rows.count))
            for (y, row) in rows.enumerated() {
                for (x, value) in row.enumerated() where value == "1" {
                    let rect = CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)
                    context.fill(Path(rect), with: .foreground)
                }
            }
        }.accessibilityHidden(true)
    }
}

struct StickerCasingLayer: View {
    let navigation: PhoneNavigationManager
    var body: some View {
        GeometryReader { proxy in
            ForEach(navigation.visibleStickers.filter(\.placed).sorted { $0.layer == $1.layer ? $0.id < $1.id : $0.layer < $1.layer }) { sticker in
                PlacedSticker(sticker: sticker, navigation: navigation, area: proxy.size)
                    .zIndex(Double(sticker.layer))
            }
        }
    }
}

private struct PlacedSticker: View {
    let sticker: MemorySticker
    let navigation: PhoneNavigationManager
    let area: CGSize
    @GestureState private var translation = CGSize.zero
    @GestureState private var magnification = 1.0
    @GestureState private var angle = Angle.zero
    private var editing: Bool { navigation.screen == .placement && navigation.selectedStickerID == sticker.id }
    var body: some View {
        StickerArtwork(sticker: sticker, store: navigation.store)
            .frame(width: 32, height: 32)
            .overlay { if editing { Rectangle().stroke(PhonePalette.edge, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).padding(-3) } }
            .scaleEffect(sticker.scale * magnification)
            .rotationEffect(.degrees(sticker.rotation) + angle)
            .position(x: 30 + sticker.position.x * max(1, area.width - 60) + translation.width,
                      y: 24 + sticker.position.y * max(1, area.height - 48) + translation.height)
            .onTapGesture { navigation.openSticker(sticker.id) }
            .gesture(DragGesture().updating($translation) { value, state, _ in if editing { state = value.translation } }
                .onEnded { value in
                    guard editing else { return }
                    navigation.transformSticker(sticker.id, position: StickerPosition(x: sticker.position.x + value.translation.width / max(1, area.width - 60), y: sticker.position.y + value.translation.height / max(1, area.height - 48)))
                })
            .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in if editing { state = value.magnification } }
                .onEnded { if editing { navigation.transformSticker(sticker.id, scale: sticker.scale * $0.magnification) } })
            .simultaneousGesture(RotateGesture().updating($angle) { value, state, _ in if editing { state = value.rotation } }
                .onEnded { if editing { navigation.transformSticker(sticker.id, rotation: sticker.rotation + $0.rotation.degrees) } })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { navigation.openSticker(sticker.id) }
    }
}

struct RetroEnvelope: View {
    let style: Int
    let stamp: Int
    let opened: Bool
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Rectangle().stroke(PhonePalette.ink, style: StrokeStyle(lineWidth: 2, dash: style == 2 ? [5, 3] : []))
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: proxy.size.width / 2, y: opened ? -proxy.size.height * 0.4 : proxy.size.height * 0.6))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                }.stroke(PhonePalette.ink, lineWidth: 1)
                if style == 1 {
                    HStack { ForEach(0..<4) { _ in Circle().frame(width: 2, height: 2); Spacer(minLength: 1) } }.padding(6).offset(y: proxy.size.height * 0.65)
                }
                StickerSilhouette(kind: [.heart, .star, .bow][max(0, min(2, stamp))]).fill(PhonePalette.ink).frame(width: 9, height: 9).padding(4)
            }
        }.accessibilityLabel("レトロな封筒")
    }
}

struct MiniVisitedPhone: View {
    let phone: VisitedPhone
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 10).stroke(PhonePalette.ink, lineWidth: 2)
                Rectangle().fill(PhonePalette.ink.opacity(0.18)).frame(width: proxy.size.width * 0.7, height: 25).offset(y: -16)
                VStack(spacing: 3) { ForEach(0..<4) { _ in Text("•  •  •") } }.font(.system(size: 7, design: .monospaced)).offset(y: 15)
                ForEach(phone.stickers) { sticker in
                    PixelMotif(asset: sticker.assetId).frame(width: 9, height: 9)
                        .rotationEffect(.degrees(sticker.rotation)).scaleEffect(sticker.scale)
                        .position(x: 10 + sticker.position.x * (proxy.size.width - 20), y: proxy.size.height - 11 + sticker.position.y * 4)
                }
            }
        }.accessibilityLabel("友達の共有した電話と飾り")
    }
}
