import SwiftUI
import ImageIO

extension PhoneNavigationManager {
    var rows: [String] {
        switch screen {
        case .cameraReview: return ["保存", "撮り直し"]
        case .photoActions: return [selectedPhoto?.favorite == true ? "♡ お気に入りを解除" : "♡ お気に入りにする", "フィルター・日付を変更", "この写真でシールをつくる", "この写真を削除", "アルバムへ戻る"]
        case .photoDeleteConfirm: return ["やめる", "削除する（元に戻せません）"]
        case .menu: return menu
        case .stickers: return ["＋ シールをつくる"] + visibleStickers.map(\.title)
        case .stickerActions: return ["位置・サイズ・回転", selectedSticker?.placed == true ? "本体からはがす" : "本体に貼る", "いちばん手前に", "ひもづく思い出を見る", "シールを削除"]
        case .deleteConfirm: return ["やめる", "削除する（元に戻せません）"]
        case .createSource: return ["写真を選ぶ", "保存したメモから", "最新のひとこまから"]
        case .shape: return StickerShape.allCases.map(\.label)
        case .contacts: return backend == nil ? ["接続について"] : ["友達を更新"] + friends.map(\.name)
        case .friend: return ["電話を訪問", "ギフトを贈る", sharingMoment == nil ? "手紙を書く" : "ひとこまをこの友達へ", "この友達をブロック"]
        case .giftPicker: return GiftAsset.collection.map(\.name)
        case .inbox: return backend == nil ? ["接続について"] : ["受信箱を更新"] + gifts.map { ($0.status == .pending ? "◇ " : "✓ ") + ($0.message.isEmpty ? "小さなギフト" : $0.message) }
        case .mail: return ["本文を書く", "封筒を選ぶ", "切手を選ぶ", "お知らせ音", "プレビュー・送信", "届いた手紙", "下書きを新しくする"]
        case .mailEnvelope: return ["ラブレター", "水玉の封筒", "航空便"]
        case .mailStamp: return ["ハート", "ほし", "リボン"]
        case .mailSound: return ["ピッ、ピピッ", "小さなチャイム"]
        case .mailInbox: return backend == nil ? ["接続について"] : ["受信箱を更新"] + receivedMail.map { "✉ " + String($0.message.prefix(14)) }
        case .daily: return ["ひとことを書く", momentPhoto == nil ? "写真を添える" : "写真を入れかえる", "自分だけに保存", "友達へ手紙で共有", "今日はスキップ", "これまでのひとこま"]
        case .momentHistory: return store.archive.moments.filter { !$0.skipped }.reversed().map { $0.id }
        case .sharing: return [store.archive.profile.visibility == .private ? "設定案：非公開" : "設定案：承認した友達", "共有する飾りを選ぶ", "この設定で共有を更新"]
        case .shareSelect: return visibleStickers.filter { $0.assetId != nil }.map { (store.archive.profile.publicStickerIds.contains($0.id) ? "✓ " : "□ ") + $0.title }
        default: return []
        }
    }
    var title: String {
        switch screen {
        case .camera: "CAMERA"
        case .cameraReview: "写メの確認"
        case .album: "しゃしんアルバム"
        case .photoDetail: "写メ"
        case .photoActions: "写メの操作"
        case .photoEdit: "写メの加工"
        case .photoDeleteConfirm: "この写メを削除する？"
        case .home: "待受画面"
        case .menu: "メニュー"
        case .memo: "メモを書く"
        case .saved: "保存したメモ"
        case .ringtone: "着信音"
        case .settings: "サウンド設定"
        case .help: "つかいかた"
        case .stickers: "♡ 思い出シール"
        case .stickerStory: selectedSticker?.title ?? "思い出"
        case .stickerActions: "シールの操作"
        case .createSource: "思い出を選ぼう"
        case .crop: "切り抜き  \(Int(cropZoom * 100))%"
        case .shape: "シールのかたち"
        case .caption: "ひとこと（24文字まで）"
        case .placement: ["↑↓←→ 位置", "↑→ 大きく / ↓← 小さく", "↑→ 右回転 / ↓← 左回転"][safe: placementMode] ?? "シールの操作"
        case .deleteConfirm: "削除してもいい？"
        case .contacts: "友達の電話"
        case .friend: selectedFriend?.name ?? "友達"
        case .visit: "\(selectedFriend?.name ?? "友達") の電話"
        case .giftPicker: "贈りものを選ぼう"
        case .giftText: "ギフトにひとこと（任意）"
        case .inbox: "◇ ギフト受信箱"
        case .giftDetail: "友達からの贈りもの"
        case .mail: "✉ とくべつな手紙"
        case .mailText: "手紙を書く（240文字まで）"
        case .mailEnvelope: "封筒を選ぼう"
        case .mailStamp: "切手を選ぼう"
        case .mailSound: "手紙のお知らせ音"
        case .mailPreview: "手紙のプレビュー"
        case .mailInbox: "✉ 届いた手紙"
        case .mailReceived: mailOpened ? "開封した手紙" : "手紙が届きました"
        case .daily: "今日のひとこま"
        case .dailyText: MemoryStore.prompts[safe: momentPrompt] ?? "今日のひとこま"
        case .dailySharePreview: "ひとこまの送信確認"
        case .momentHistory: "ひとこまのアルバム"
        case .momentStory: viewedMomentID ?? "ひとこま"
        case .sharing: "電話の共有（設定案）"
        case .shareSelect: "共有する飾り（任意）"
        case .connection: "友達機能の接続"
        case .confirmation: "pacchi. お知らせ"
        }
    }
    var detailText: String {
        switch screen {
        case .stickerStory:
            guard let s = selectedSticker else { return "シールが見つかりません。" }
            let date = s.createdAt.formatted(date: .numeric, time: .omitted)
            return "\(s.type.story)\n\(date)\n\(s.friendId == nil ? "自分だけの思い出" : "友達との思い出")"
        case .dailySharePreview:
            guard let moment = sharingMoment else { return "送信するひとこまがありません。" }
            return "宛先：\(selectedFriend?.name ?? "友達")\n\(moment.response)\n\(moment.imageReference == nil ? "写真なし" : "写真1枚を添付")\nOKでこの友達だけに送信。"
        case .placement: return "シールは本体の下側に配置できます。OKか#で操作を切替。右キーで完了。ドラッグ・ピンチ・回転にも対応。"
        case .contacts: return backend == nil ? "まだ接続していません。認証と友達の設定が必要です。" : "承認済みの友達はいません。既存の友達機能で追加してください。"
        case .giftDetail:
            guard let g = selectedGift else { return "ギフトが見つかりません。" }
            return "\(GiftAsset.collection.first { $0.id == g.stickerAssetId }?.name ?? "ギフト")\n\(g.message.isEmpty ? "小さな贈りものが届きました。" : g.message)\n\(g.status == .pending ? "OKで受け取る" : "受け取り済み")"
        case .inbox: return backend == nil ? "接続するとギフトを受け取れます。" : "新しいギフトはありません。"
        case .mailInbox: return backend == nil ? "接続すると友達の手紙が届きます。" : "届いた手紙はありません。"
        case .shareSelect: return "共有できる飾りはまだありません。友達から受け取った公式ギフトを選べます。写真・メモ・記念日の詳細は共有しません。"
        case .connection: return "このプロジェクトにはFirebase認証・友達機能が未接続です。端末内のシール・手紙の下書き・ひとこまは使えます。送信・訪問は接続後に利用できます。設定手順はBACKEND_SETUP.mdに記載しています。"
        case .confirmation: return confirmationText
        case .momentHistory: return "まだひとこまはありません。気が向いた日に残してね。"
        case .momentStory:
            guard let m = store.archive.moments.first(where: { $0.id == viewedMomentID }) else { return "見つかりません。" }
            return "\(MemoryStore.prompts[safe: m.promptId] ?? "今日のひとこま")\n\(m.response.isEmpty ? "写真を残しました。" : m.response)"
        case .mailPreview: return mailDraft.message.isEmpty ? "まだ本文がありません。" : mailDraft.message
        case .mailReceived: return mailOpened ? (selectedMail?.message ?? "") : "あなたに、とくべつな手紙。OKで封を開けてね。"
        case .help: return "十字キーで選んでOKで決定。右キーで戻る。終話キーは待受へ。メニューは上下で全\(menu.count)項目、#で次ページ。数字キーで文字入力、#で文字確定、*で削除。シールは操作メニューから位置・サイズ・回転を変更できます。"
        default: return ""
        }
    }
    var textPages: [String] {
        let text = isTyping ? currentText + "▌" : detailText
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let chars = Array(line)
            if chars.isEmpty { lines.append("") }
            for start in stride(from: 0, to: chars.count, by: 18) { lines.append(String(chars[start..<min(start + 18, chars.count)])) }
        }
        if lines.isEmpty { return [""] }
        let momentHasPhoto = screen == .momentStory && store.archive.moments.first(where: { $0.id == viewedMomentID })?.imageReference != nil
        let pageSize = momentHasPhoto ? 3 : (screen == .mailReceived && selectedMail?.imageReference != nil ? 4 : (screen == .mailPreview ? 4 : 5))
        return stride(from: 0, to: lines.count, by: pageSize).map { lines[$0..<min($0 + pageSize, lines.count)].joined(separator: "\n") }
    }
}

struct FeatureLCDView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let navigation: PhoneNavigationManager
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(navigation.title).font(LCDTypography.font(size: 10, weight: .bold)).lineLimit(1)
            if navigation.screen == .daily {
                Text(MemoryStore.prompts[safe: navigation.momentPrompt] ?? "今日のひとこま").font(LCDTypography.font(size: 9)).lineLimit(1)
            }
            let options = navigation.rows
            if !options.isEmpty { list(options) }
            else {
                switch navigation.screen {
                case .crop: crop
                case .visit: visit
                case .mailPreview: mailPreview
                case .mailReceived: receivedLetter
                case .placement:
                    Text(navigation.detailText).font(LCDTypography.font(size: 10)).lineLimit(6)
                    Text("\((navigation.selectedSticker?.scale ?? 1).formatted(.number.precision(.fractionLength(1))))× / \(Int(navigation.selectedSticker?.rotation ?? 0))°").font(LCDTypography.font(size: 9))
                default: text
                }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func list(_ options: [String]) -> some View {
        let selected = min(max(0, navigation.selection), max(0, options.count - 1))
        let start = selected / 5 * 5
        let visible = Array(options.enumerated().dropFirst(start).prefix(5))
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(visible, id: \.offset) { index, title in
                Text("\(index + 1) \(title)")
                    .font(LCDTypography.font(size: 10, weight: .medium)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 3).frame(height: 14)
                    .foregroundStyle(index == selected ? PhonePalette.lcd : PhonePalette.ink)
                    .background(index == selected ? PhonePalette.ink : .clear)
            }
            if options.count > 5 {
                Text("↑↓  \(selected / 5 + 1)/\((options.count + 4) / 5)").font(LCDTypography.font(size: 8))
            }
            if [.contacts, .inbox, .mailInbox].contains(navigation.screen) && options.count <= 1 {
                Text(navigation.detailText).font(LCDTypography.font(size: 9)).lineLimit(3)
            }
        }
    }
    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            if navigation.screen == .stickerStory, let sticker = navigation.selectedSticker {
                HStack(spacing: 5) {
                    StickerArtwork(sticker: sticker, store: navigation.store, monochrome: true).frame(width: 22, height: 20)
                    Text(sticker.createdAt, format: .dateTime.year().month().day()).font(LCDTypography.font(size: 8))
                }
            }
            let pages = navigation.textPages
            let page = navigation.isTyping ? pages.count - 1 : min(navigation.textPage, pages.count - 1)
            Text(pages[safe: max(0, page)] ?? "").font(LCDTypography.font(size: 10, weight: .medium)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
            if navigation.isTyping {
                Text("ABC連打 / #確定 / *削除").font(LCDTypography.font(size: 8))
            } else if pages.count > 1 {
                Text("←→  \(page + 1)/\(pages.count)").font(LCDTypography.font(size: 8))
            }
            if navigation.screen == .momentStory,
               let moment = navigation.store.archive.moments.first(where: { $0.id == navigation.viewedMomentID }),
               let photo = navigation.store.image(moment.imageReference) {
                Image(decorative: photo, scale: 1).resizable().scaledToFit().frame(height: 35).saturation(0)
            }
        }
    }
    private var crop: some View {
        VStack(spacing: 3) {
            if let image = navigation.store.image(navigation.editorPhoto) {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    let factor = max(side / CGFloat(image.width), side / CGFloat(image.height)) * navigation.cropZoom
                    let w = CGFloat(image.width) * factor, h = CGFloat(image.height) * factor
                    Image(decorative: image, scale: 1).resizable().frame(width: w, height: h)
                        .offset(x: -(w - side) * navigation.cropX, y: -(h - side) * navigation.cropY)
                        .frame(width: side, height: side, alignment: .topLeading).clipped().saturation(0)
                }.frame(width: 72, height: 72).border(PhonePalette.ink, width: 1)
            }
            Text("十字キー:位置  2/8:拡大縮小").font(LCDTypography.font(size: 8))
        }.frame(maxWidth: .infinity)
    }
    private var visit: some View {
        VStack(spacing: 3) {
            if let phone = navigation.visitedPhone {
                MiniVisitedPhone(phone: phone).frame(width: 57, height: 89)
                Text("選ばれた飾りだけを表示中").font(LCDTypography.font(size: 8))
            } else { Text("共有されていません。") }
        }.frame(maxWidth: .infinity)
    }
    private var mailPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            RetroEnvelope(style: navigation.mailDraft.envelopeStyle, stamp: navigation.mailDraft.stampStyle, opened: false).frame(width: 45, height: 25)
            Text(navigation.textPages[safe: max(0, navigation.textPage)] ?? "").font(LCDTypography.font(size: 10)).lineLimit(4)
            Text(navigation.mailDraft.recipientId == nil ? "未送信 / OKで宛先を選択" : "未送信 / OKで送信").font(LCDTypography.font(size: 8))
        }
    }
    private var receivedLetter: some View {
        VStack(spacing: 3) {
            if !navigation.mailOpened {
                RetroEnvelope(style: navigation.selectedMail?.envelopeStyle ?? 0, stamp: navigation.selectedMail?.stampStyle ?? 0, opened: false).frame(width: 83, height: 55)
                Text("OKで開封").font(LCDTypography.font(size: 9))
            } else {
                text.transition(.opacity.combined(with: .move(edge: .top)))
                if let data = navigation.receivedMailPhoto,
                   let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().frame(height: 30).saturation(0)
                }
            }
        }.frame(maxWidth: .infinity).animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: navigation.mailOpened)
    }
}
