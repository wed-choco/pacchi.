import SwiftUI
import PhotosUI

struct ContentView: View {
    var backend: (any FriendshipBackend)? = nil
    var body: some View { RetroPhoneView(backend: backend) }
}

enum PhonePalette {
    static let pink = Color(red: 244/255, green: 184/255, blue: 202/255)
    static let edge = Color(red: 183/255, green: 110/255, blue: 139/255)
    static let ink = Color(red: 62/255, green: 73/255, blue: 66/255)
    static let lcd = Color(red: 201/255, green: 210/255, blue: 188/255)
}

struct RetroPhoneView: View {
    @State private var navigation: PhoneNavigationManager
    let backend: (any FriendshipBackend)?
    init(store: MemoryStore? = nil, backend: (any FriendshipBackend)? = nil) {
        self.backend = backend
        _navigation = State(initialValue: PhoneNavigationManager(store: store, backend: backend))
    }
    var body: some View {
        GeometryReader { proxy in
            let scale = min((proxy.size.width - 40) / 300, (proxy.size.height - 32) / 680, 1.25)
            ZStack {
                Color(red: 0.98, green: 0.95, blue: 0.93).ignoresSafeArea()
                VStack(spacing: 0) {
                    PhoneBodyView(navigation: navigation)
                }
                .frame(width: 300, height: 680)
                .scaleEffect(max(0.1, scale))
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .preferredColorScheme(.light)
        .task {
            navigation.setBackend(backend)
            if let error = navigation.store.loadError { navigation.showMessage(error) }
        }
        .onChange(of: backend?.ownerId) { _, _ in navigation.setBackend(backend) }
        .onDisappear { navigation.setBackend(nil) }
    }
}

struct PhoneBodyView: View {
    let navigation: PhoneNavigationManager
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [PhonePalette.edge, PhonePalette.pink, PhonePalette.edge], startPoint: .leading, endPoint: .trailing))
                .frame(width: 19, height: 64).offset(x: 105, y: 4)
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(0..<7) { _ in Capsule().fill(PhonePalette.edge.opacity(0.8)).frame(width: 3, height: 7) }
                }.frame(height: 18).padding(.top, 10)
                HStack {
                    Text("pacchi.").font(.system(size: 20, weight: .semibold, design: .rounded)).italic()
                    Spacer()
                    Text("P-02").font(.system(size: 9, weight: .medium, design: .monospaced))
                }.foregroundStyle(PhonePalette.edge).padding(.horizontal, 30).padding(.bottom, 8)
                LCDScreenView(navigation: navigation)
                    .frame(width: 234, height: 184)
                    .clipped()
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(PhonePalette.edge))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.45), lineWidth: 1))
                Text("D I G I T A L   •   P O C K E T").font(.system(size: 7, weight: .semibold)).foregroundStyle(PhonePalette.edge).padding(.top, 7)
                NavigationPadView(navigation: navigation).padding(.top, 8)
                PhysicalKeypadView(navigation: navigation).padding(.top, 10)
                HStack(spacing: 4) {
                    ForEach(0..<5) { _ in Circle().fill(PhonePalette.edge.opacity(0.7)).frame(width: 3, height: 3) }
                }.padding(.top, 9)
                Text("made of little memories").font(.system(size: 8, design: .rounded)).foregroundStyle(PhonePalette.edge).padding(.top, 6)
                Spacer(minLength: 0)
            }
            .frame(width: 300, height: 626)
            .background {
                RoundedRectangle(cornerRadius: 46)
                    .fill(LinearGradient(stops: [.init(color: Color(red: 1, green: 0.85, blue: 0.89), location: 0), .init(color: PhonePalette.pink, location: 0.25), .init(color: PhonePalette.pink, location: 0.8), .init(color: PhonePalette.edge.opacity(0.75), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 43).stroke(.white.opacity(0.55), lineWidth: 2).padding(4))
                    .overlay(RoundedRectangle(cornerRadius: 46).stroke(PhonePalette.edge, lineWidth: 1))
                    .shadow(color: PhonePalette.edge.opacity(0.28), radius: 16, x: 0, y: 15)
            }
            .overlay(alignment: .bottom) {
                StickerCasingLayer(navigation: navigation).frame(width: 260, height: 64).padding(.bottom, 12)
            }
            .offset(y: 42)
        }
    }
}

struct LCDScreenView: View {
    let navigation: PhoneNavigationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshing = false
    @State private var photoItem: PhotosPickerItem?
    @Bindable private var navigationBinding: PhoneNavigationManager

    init(navigation: PhoneNavigationManager) {
        self.navigation = navigation
        self.navigationBinding = navigation
    }
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<4) { i in Rectangle().frame(width: 3, height: CGFloat(3 + i * 3)) }
                }.accessibilityLabel("電波 良好")
                Text("PACCHI")
                Spacer()
                if !navigation.soundEnabled { Image(systemName: "speaker.slash.fill") }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                }
                Image(systemName: "battery.100").accessibilityLabel("バッテリー")
            }.font(LCDTypography.font(size: 9, weight: .bold))
            Rectangle().frame(height: 1).opacity(0.5)
            Group {
                switch navigation.screen {
                case .camera, .cameraReview, .album, .photoDetail, .photoEdit: CameraAlbumLCDView(navigation: navigation)
                case .home: home
                case .menu: FeatureLCDView(navigation: navigation)
                case .memo:
                    detail(title: "メモを書く  \(navigation.draft.count)/60", text: navigation.draft + "▌", footer: navigation.notice.isEmpty ? "ABC入力 / # 次の文字\n* 削除  ·  OK 保存" : navigation.notice)
                case .saved:
                    detail(title: "保存したメモ", text: navigation.savedMemo.isEmpty ? "まだメモがありません。\nメニューから書いてね。" : navigation.savedMemo, footer: "本体に保存されます")
                case .ringtone:
                    detail(title: "♪  着信音のおためし", text: "ピッ、ピピッ。\nあの頃の、呼び出し音。", footer: navigation.soundEnabled ? "OKで再生" : "サウンド設定は OFF です")
                case .settings:
                    detail(title: "サウンド設定", text: navigation.soundEnabled ? "♪ サウンド：ON" : "♪ サウンド：OFF", footer: "OKで ON / OFF\nマナーモードに従います")
                default: FeatureLCDView(navigation: navigation)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().frame(height: 1).opacity(0.5)
            HStack { Text(navigation.notice.isEmpty ? navigation.leftLabel : navigation.notice); Spacer(); Text(navigation.isTyping ? "削除/戻る" : "戻る") }
                .lineLimit(1).minimumScaleFactor(0.7)
                .font(LCDTypography.font(size: 10, weight: .bold))
        }
        .font(LCDTypography.font(size: 11, weight: .medium))
        .foregroundStyle(PhonePalette.ink)
        .padding(10)
        .background(PhonePalette.lcd)
        .overlay {
            Canvas { context, size in
                for x in stride(from: 0.0, to: size.width, by: 3) {
                    for y in stride(from: 0.0, to: size.height, by: 3) {
                        context.fill(Path(CGRect(x: x, y: y, width: 0.5, height: 0.5)), with: .color(PhonePalette.ink.opacity(0.13)))
                    }
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        .clipped()
        .photosPicker(isPresented: $navigationBinding.photoPickerPresented, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw MemoryError.invalidImage }
                    navigation.receivedPhoto(data)
                } catch { navigation.showMessage("写真を読み込めませんでした。もう一度選んでね。") }
                photoItem = nil
            }
        }
        .opacity(refreshing ? 0.65 : 1)
        .task(id: navigation.revision) {
            guard !reduceMotion else { return }
            refreshing = true
            try? await Task.sleep(for: .milliseconds(65))
            refreshing = false
        }
    }
    private var home: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 2) {
                    Text(context.date, format: .dateTime.month(.twoDigits).day(.twoDigits).weekday(.abbreviated)).font(LCDTypography.font(size: 10))
                    Text(context.date, format: .dateTime.hour().minute()).font(LCDTypography.font(size: 26, weight: .regular))
                }
            }
            PixelHeart().frame(width: 29, height: 25)
            Text("きょうも、ちいさなときめき。").font(LCDTypography.font(size: 10))
            Text("•  pacchi.  •").font(LCDTypography.font(size: 10, weight: .bold))
        }
    }
    private func detail(title: String, text: String, footer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).bold()
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(footer).font(LCDTypography.font(size: 9))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PixelHeart: View {
    private let rows = ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"]
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / 7, size.height / 6)
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "1" {
                    context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)), with: .color(PhonePalette.ink))
                }
            }
        }.accessibilityLabel("ハート")
    }
}

struct NavigationPadView: View {
    let navigation: PhoneNavigationManager
    var body: some View {
        HStack(spacing: 15) {
            VStack(spacing: 12) {
                key("•••", label: "左ソフトキー、\(navigation.leftLabel)", action: navigation.select)
                key("phone.fill", symbol: true, color: Color(red: 0.34, green: 0.53, blue: 0.43), label: "通話、メニューを開く") { navigation.openMenu() }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 29).fill(PhonePalette.edge.opacity(0.65)).frame(width: 88, height: 88)
                RoundedRectangle(cornerRadius: 27).fill(Color(red: 1, green: 0.88, blue: 0.91)).frame(width: 84, height: 84)
                VStack(spacing: 0) {
                    arrow("chevron.up", label: "上", dx: 0, dy: -1)
                    HStack(spacing: 0) {
                        arrow("chevron.left", label: "左", dx: -1, dy: 0)
                        Button(action: navigation.select) { Text("OK").font(.system(size: 12, weight: .bold, design: .rounded)).frame(width: 32, height: 32) }
                            .buttonStyle(PhysicalButtonStyle()).accessibilityLabel("決定")
                        arrow("chevron.right", label: "右", dx: 1, dy: 0)
                    }
                    arrow("chevron.down", label: "下", dx: 0, dy: 1)
                }
            }
            VStack(spacing: 12) {
                key("•••", label: "右ソフトキー、削除または戻る", action: navigation.back)
                key("phone.down.fill", symbol: true, color: PhonePalette.edge, label: "終話、待受に戻る", action: navigation.home)
            }
        }
    }
    private func arrow(_ symbol: String, label: String, dx: Int, dy: Int) -> some View {
        Button { navigation.direction(dx: dx, dy: dy) } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(PhonePalette.edge).frame(width: 24, height: 24)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
    private func key(_ title: String, symbol: Bool = false, color: Color = PhonePalette.edge, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group { if symbol { Image(systemName: title) } else { Text(title) } }
                .font(.system(size: 14, weight: .bold)).foregroundStyle(color).frame(width: 47, height: 31)
        }.buttonStyle(PhysicalButtonStyle()).accessibilityLabel(label)
    }
}

struct PhysicalKeypadView: View {
    let navigation: PhoneNavigationManager
    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
    private let labels = ["1": "♡", "2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL", "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ", "*": "BACK", "0": "SPACE", "#": "NEXT"]
    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        Button { navigation.number(key) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(key).font(.system(size: 22, weight: .medium, design: .rounded))
                                Text(labels[key] ?? "").font(.system(size: 7, weight: .semibold, design: .rounded))
                            }.frame(width: 68, height: 29)
                        }
                        .buttonStyle(PhysicalButtonStyle())
                        .accessibilityLabel("\(key) \(labels[key] ?? "")")
                    }
                }
            }
        }
    }
}

private struct PhysicalButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(PhonePalette.edge)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.init(red: 1, green: 0.96, blue: 0.94), .init(red: 0.98, green: 0.81, blue: 0.85)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.7), lineWidth: 1).padding(1))
                    .shadow(color: PhonePalette.edge.opacity(0.8), radius: configuration.isPressed ? 0 : 1, x: 0, y: configuration.isPressed ? 0 : 3)
            }
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

#Preview { ContentView() }
