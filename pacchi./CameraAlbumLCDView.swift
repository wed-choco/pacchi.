import SwiftUI

struct CameraAlbumLCDView: View {
    let navigation: PhoneNavigationManager
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 3) {
            switch navigation.screen {
            case .camera: camera
            case .cameraReview: review
            case .album: album
            case .photoDetail: detail
            case .photoEdit: edit
            default: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(LCDTypography.font(size: 9))
        .task(id: navigation.screen) {
            if navigation.screen == .camera && scenePhase == .active { navigation.camera.start() }
            else { navigation.camera.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && navigation.screen == .camera { navigation.camera.start() }
            else { navigation.camera.stop() }
        }
        .onDisappear { navigation.camera.stop() }
    }
    private var camera: some View {
        VStack(spacing: 3) {
            HStack {
                Text("CAMERA").bold(); Spacer()
                Text(navigation.camera.filter.label)
                Text("\(navigation.camera.zoom, specifier: "%.1f")×")
            }
            if let image = navigation.camera.preview {
                Image(decorative: image, scale: 1).resizable().scaledToFit().frame(height: 75).clipped()
                    .accessibilityLabel("背面カメラのライブ映像")
            } else {
                Text(cameraMessage).font(LCDTypography.font(size: 9)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 65).fixedSize(horizontal: false, vertical: true)
            }
            Text(navigation.camera.errorMessage ?? "←→ FILTER / ↑↓ ZOOM / # DATE \(navigation.camera.dateStamp ? "ON" : "OFF")")
                .font(LCDTypography.font(size: 7)).lineLimit(2)
        }
    }
    private var cameraMessage: String {
        switch navigation.camera.status {
        case .unavailable(let message): message
        case .requesting: "カメラの許可を確認中…"
        case .capturing: "撮影しています…"
        case .idle:
            #if targetEnvironment(simulator)
            "Simulatorではカメラを使えません。iPhone実機で撮影してね。"
            #elseif !os(iOS)
            "撮影はiPhone実機で使えます。保存済みのアルバムはこの環境でも見られます。"
            #else
            "カメラは休止中です。アプリを前面に戻すと再開します。"
            #endif
        default: "カメラを準備しています…"
        }
    }
    private var review: some View {
        VStack(spacing: 2) {
            HStack { Text("写メが撮れたよ ♡").bold(); Spacer(); Text(navigation.camera.captured?.filter.label ?? "") }
            if let shot = navigation.camera.captured {
                Image(decorative: shot.processed, scale: 1).resizable().scaledToFit().frame(height: 65)
            } else { Text("写真がありません。戻って撮り直してね。") }
            HStack(spacing: 6) {
                ForEach(Array(["保存", "撮り直し"].enumerated()), id: \.offset) { index, title in
                    Text(title).padding(.horizontal, 8).padding(.vertical, 2)
                        .foregroundStyle(navigation.selection == index ? PhonePalette.lcd : PhonePalette.ink)
                        .background(navigation.selection == index ? PhonePalette.ink : .clear)
                }
            }
        }
    }
    private var album: some View {
        let photos = navigation.store.archive.photos
        let selected = min(max(0, navigation.selection), max(0, photos.count - 1))
        let start = selected / 9 * 9
        let page = Array(photos.dropFirst(start).prefix(9))
        return VStack(spacing: 3) {
            HStack { Text("しゃしんアルバム").bold(); Spacer(); Text("\(photos.count)枚") }
            if photos.isEmpty {
                Spacer(minLength: 0)
                Text("□  ♡  □").font(LCDTypography.font(size: 20))
                Text("まだ、写メがありません。")
                Text("カメラでちいさな思い出を。").font(LCDTypography.font(size: 8))
                Spacer(minLength: 0)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(Array(page.enumerated()), id: \.element.id) { offset, photo in
                        ZStack(alignment: .bottomTrailing) {
                            if let image = navigation.store.image(photo.processedReference, maximum: 128) {
                                Image(decorative: image, scale: 1).resizable().scaledToFill().frame(height: 25).clipped()
                            } else { Text("読込不可").frame(height: 25) }
                            if photo.favorite { Text("♡").font(LCDTypography.font(size: 9)).padding(.horizontal, 2).background(PhonePalette.lcd) }
                        }
                        .frame(height: 25).clipped()
                        .overlay(Rectangle().stroke(selected == start + offset ? PhonePalette.ink : PhonePalette.ink.opacity(0.2), lineWidth: selected == start + offset ? 2 : 0.5))
                        .accessibilityLabel("写真\(start + offset + 1)\(photo.favorite ? " お気に入り" : "")")
                    }
                }
                Text("↑↓←→  \(selected + 1)/\(photos.count)  OK ひらく").font(LCDTypography.font(size: 7))
            }
        }
    }
    private var detail: some View {
        VStack(spacing: 3) {
            if let photo = navigation.selectedPhoto {
                HStack { Text(photo.favorite ? "PHOTO ♡" : "PHOTO").bold(); Spacer(); Text(photo.filter.label) }
                if let image = navigation.store.image(photo.processedReference, maximum: 640) {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().frame(height: 76)
                } else { Text("画像ファイルが見つかりません。").frame(height: 65) }
                Text(photo.capturedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(LCDTypography.font(size: 7)).lineLimit(1)
            } else { Text("写真が見つかりません。\n戻ってアルバムから選んでね。") }
        }
    }
    private var edit: some View {
        VStack(spacing: 3) {
            HStack { Text("写メの加工").bold(); Spacer(); Text(navigation.editingFilter.label) }
            if let rendered = navigation.editedPhoto {
                Image(decorative: rendered.image, scale: 1).resizable().scaledToFit().frame(height: 72)
            } else { Text(navigation.photoEditBusy ? "写真を処理しています…" : "処理できませんでした。戻って再試行してね。").frame(height: 72) }
            Text("←→ FILTER / ↑↓・# DATE \(navigation.editingStamp ? "ON" : "OFF")").font(LCDTypography.font(size: 7))
        }
    }
}
