import SwiftUI

// Phase 1: shared visual language and navigation, independent of the legacy LCD tools.
enum PacchiStyle {
    static let pink = Color(red: 248/255, green: 200/255, blue: 220/255)
    static let soft = Color(red: 1, green: 228/255, blue: 236/255)
    static let cream = Color(red: 1, green: 249/255, blue: 245/255)
    static let lavender = Color(red: 232/255, green: 221/255, blue: 245/255)
    static let ink = Color(red: 81/255, green: 67/255, blue: 76/255)
    static let rose = Color(red: 0.65, green: 0.29, blue: 0.44)
}

enum PacchiDestination: String, CaseIterable, Identifiable {
    case messages = "Messages", memories = "Memories", camera = "Camera", decorate = "Decorate", friends = "Friends"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .messages: "envelope.fill"
        case .memories: "heart.text.clipboard.fill"
        case .camera: "camera.fill"
        case .decorate: "wand.and.stars"
        case .friends: "person.2.fill"
        }
    }
}

struct PacchiHomeView: View {
    @State private var model = PacchiHomeModel()
    @AppStorage("pacchi.home.sound") private var sound = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TabView {
            home.tabItem { Label("My Phone", systemImage: "flipphone") }
            NavigationStack { phasePage(.friends) }.tabItem { Label("Friends", systemImage: "person.2") }
            NavigationStack { phasePage(.memories) }.tabItem { Label("Memories", systemImage: "heart") }
            NavigationStack {
                Form {
                    Section("Your little world") {
                        Label("Pacchi. owner", systemImage: "heart.circle")
                        Text("Your friendships, your little world. ♡")
                    }
                    Section("Little details") { Toggle("Keypad sounds", isOn: $sound) }
                    Section { Text("Offline • Your photos and memories stay on this device.") }
                }.navigationTitle("Profile").scrollContentBackground(.hidden).background(PacchiStyle.cream)
            }.tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(PacchiStyle.rose)
        .foregroundStyle(PacchiStyle.ink)
        .preferredColorScheme(.light)
        .sheet(item: $model.destination) { destination in
            NavigationStack {
                phasePage(destination)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.destination = nil } } }
            }
        }
    }
    private var home: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 15) {
                    HStack {
                        Text("pacchi.").font(.system(size: 37, weight: .heavy, design: .rounded)).tracking(-2)
                        Spacer()
                        Text("MY LITTLE WORLD").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                        Image(systemName: "sparkle").foregroundStyle(PacchiStyle.rose)
                    }
                    HStack {
                        Text("A little closer, every day. ♡").font(.system(.subheadline, design: .rounded))
                        Spacer()
                        Text("01 / MY PHONE").font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundStyle(PacchiStyle.rose)
                    flipPhone
                        .scaleEffect(min(1, (geometry.size.width - 56) / 290))
                        .frame(width: min(290, geometry.size.width - 56), height: 538 * min(1, (geometry.size.width - 56) / 290))
                        .padding(.vertical, 12)
                    Text("Tap the screen to enter your world")
                        .font(.system(.footnote, design: .rounded))
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                        Text("Collect moments. Make it yours.")
                    }.font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(PacchiStyle.rose)
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .background {
                ZStack {
                    PacchiStyle.cream
                    Circle().fill(PacchiStyle.soft).frame(width: 340, height: 340).blur(radius: 32).offset(x: 110, y: -40)
                    Circle().fill(PacchiStyle.lavender.opacity(0.5)).frame(width: 240, height: 240).blur(radius: 45).offset(x: -120, y: 170)
                }.ignoresSafeArea()
            }
        }
    }
    private var flipPhone: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Capsule().fill(PacchiStyle.rose.opacity(0.4)).frame(width: 44, height: 4).padding(.top, 13)
                HStack { Text("pacchi.").italic(); Spacer(); Text("P ♡ 01").font(.system(size: 8, design: .monospaced)) }
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(PacchiStyle.rose).padding(.horizontal, 24)
                screen.padding(.horizontal, 20)
                Text("♡   FRIENDSHIP CLUB   ♡").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(2).padding(.bottom, 12)
            }
            .frame(height: 266)
            .background(shell)
            .rotation3DEffect(.degrees(model.menuOpen ? 0 : -7), axis: (x: 1, y: 0, z: 0), anchor: .bottom)
            HStack(spacing: 4) {
                Capsule().frame(width: 30)
                Capsule().fill(LinearGradient(colors: [PacchiStyle.rose.opacity(0.5), .white, PacchiStyle.pink], startPoint: .top, endPoint: .bottom))
                Capsule().frame(width: 30)
            }.foregroundStyle(PacchiStyle.pink).frame(height: 15).padding(.horizontal, 18)
            VStack(spacing: 9) {
                HStack(spacing: 20) {
                    phoneButton("mail", symbol: "envelope") { model.destination = .messages }
                    Button { toggleMenu() } label: {
                        Text("OK").font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 55, height: 45).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
                            .padding(7).overlay(RoundedRectangle(cornerRadius: 24).stroke(PacchiStyle.rose.opacity(0.3), lineWidth: 3))
                    }.accessibilityLabel("Open phone menu")
                    phoneButton("back", symbol: "arrow.uturn.backward") { model.menuOpen = false; model.selectedKey = "" }
                }.padding(.top, 13)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 7) {
                    ForEach(Array(["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"].enumerated()), id: \.offset) { index, key in
                        Button {
                            model.press(key, sound: sound)
                            if model.menuOpen, index < PacchiDestination.allCases.count { model.destination = PacchiDestination.allCases[index] }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(key).font(.system(size: 18, weight: .medium, design: .rounded))
                                Text(["♡", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ", "", "+", ""][index]).font(.system(size: 6, weight: .bold))
                            }.frame(maxWidth: .infinity).frame(height: 31)
                                .background(LinearGradient(colors: [.white.opacity(0.95), PacchiStyle.soft], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 1))
                                .shadow(color: PacchiStyle.rose.opacity(0.22), radius: 1, y: 2)
                        }.accessibilityLabel("Key \(key)")
                    }
                }.padding(.horizontal, 22)
                Text(model.selectedKey.isEmpty ? "made of little memories" : "♡  \(model.selectedKey)  ♡")
                    .font(.system(size: 8, design: .monospaced)).padding(.bottom, 10)
            }.frame(height: 257).background(shell)
        }
        .foregroundStyle(PacchiStyle.rose)
        .shadow(color: PacchiStyle.rose.opacity(0.17), radius: 14, x: 4, y: 16)
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Capsule().stroke(PacchiStyle.rose.opacity(0.4), lineWidth: 2).frame(width: 15, height: 66)
                Text("♡").font(.system(size: 38)).foregroundStyle(PacchiStyle.rose).rotationEffect(.degrees(-12))
            }.offset(x: 20, y: 45).accessibilityHidden(true)
        }
        .buttonStyle(PacchiKeyStyle())
    }
    private var shell: some View {
        RoundedRectangle(cornerRadius: 32)
            .fill(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: PacchiStyle.pink, location: 0.17), .init(color: PacchiStyle.soft, location: 0.52), .init(color: PacchiStyle.pink, location: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.8), lineWidth: 2).padding(4))
            .overlay(RoundedRectangle(cornerRadius: 32).stroke(PacchiStyle.rose.opacity(0.3), lineWidth: 1))
    }
    private var screen: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text("OFFLINE"); Spacer(); Image(systemName: "battery.100percent")
            }.font(.system(size: 8, weight: .bold, design: .monospaced))
            if model.menuOpen {
                VStack(spacing: 3) {
                    ForEach(Array(PacchiDestination.allCases.enumerated()), id: \.element.id) { index, item in
                        Button { model.destination = item } label: {
                            HStack { Text("0\(index + 1)").font(.system(size: 8, design: .monospaced)); Image(systemName: item.symbol).frame(width: 15); Text(item.rawValue); Spacer(); Image(systemName: "chevron.right").font(.system(size: 7)) }
                                .font(.system(size: 11, weight: .medium, design: .rounded)).padding(.vertical, 4).padding(.horizontal, 8)
                                .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }.transition(.opacity)
            } else {
                Button { toggleMenu() } label: {
                    VStack(spacing: 2) {
                        Text("20:00").font(.system(size: 34, weight: .light, design: .rounded)).hidden().overlay {
                            TimelineView(.everyMinute) { context in Text(context.date, format: .dateTime.hour().minute()).font(.system(size: 34, weight: .light, design: .rounded)) }
                        }
                        Text("your little world").font(.system(size: 10, design: .monospaced))
                        Text("ʚ ♡ ɞ").font(.system(size: 32)).padding(.vertical, 5)
                        Text("press to open ♡").font(.system(size: 9, weight: .medium, design: .monospaced))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.accessibilityLabel("Open phone menu")
            }
        }
        .padding(10).frame(height: 185)
        .background(LinearGradient(colors: [PacchiStyle.lavender, PacchiStyle.cream, PacchiStyle.soft], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(5).background(PacchiStyle.ink.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
    }
    private func phoneButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15)).frame(width: 54, height: 32).background(.white.opacity(0.65), in: Capsule()) }.accessibilityLabel(title)
    }
    private func toggleMenu() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) { model.menuOpen.toggle() }
    }
    private func phasePage(_ destination: PacchiDestination) -> some View {
        VStack(spacing: 24) {
            Image(systemName: destination.symbol).font(.system(size: 48)).foregroundStyle(PacchiStyle.rose)
            Text(destination.rawValue).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(detail(destination)).multilineTextAlignment(.center).foregroundStyle(PacchiStyle.ink)
            if destination != .friends {
                NavigationLink("Open existing phone tools ♡") { ContentView() }
                    .buttonStyle(.borderedProminent)
            }
            Text("PHASE 1 • LOCAL ONLY").font(.system(size: 10, design: .monospaced)).foregroundStyle(PacchiStyle.rose)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(PacchiStyle.cream).navigationTitle(destination.rawValue).navigationBarTitleDisplayMode(.inline)
    }
    private func detail(_ destination: PacchiDestination) -> String {
        switch destination {
        case .messages: "A place for little letters. Existing local drafts are available in the phone tools. Friend conversations will arrive in Phase 3."
        case .memories: "Your collection of little moments. Open the existing phone tools to see your locally saved stickers and stories."
        case .camera: "Keep a moment close. Photo import, retro filters and your local album are available in the existing phone tools."
        case .decorate: "A phone as unique as you. Existing sticker tools are available below; the new decoration experience comes in Phase 2."
        case .friends: "Your friendship club starts here. Sample friend profiles and phone visits are planned for the next phases. No messages or gifts are sent from this preview."
        }
    }
}

private struct PacchiKeyStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
    }
}

#Preview { PacchiHomeView() }
