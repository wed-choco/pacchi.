import SwiftUI
import Observation

@MainActor @Observable
final class PhoneNavigationManager {
    enum Screen: Equatable {
        case home, menu, memo, saved, ringtone, settings, help
        case camera, cameraReview, album, photoDetail, photoActions, photoEdit, photoDeleteConfirm
        case stickers, stickerStory, stickerActions, createSource, crop, shape, caption, placement, deleteConfirm
        case contacts, friend, visit, giftPicker, giftText, inbox, giftDetail
        case mail, mailText, mailEnvelope, mailStamp, mailSound, mailPreview, mailInbox, mailReceived
        case daily, dailyText, dailySharePreview, momentHistory, momentStory, sharing, shareSelect, connection, confirmation
    }
    enum PhotoTarget { case sticker, daily }
    let store: MemoryStore
    private(set) var backend: (any FriendshipBackend)?
    let camera = CameraService()
    var screen: Screen = .home {
        didSet {
            if oldValue == .camera && screen != .camera { camera.stop() }
            if oldValue == .photoEdit && screen != .photoEdit { photoEditTask?.cancel(); photoEditGeneration += 1; photoEditBusy = false; editedPhoto = nil }
            if oldValue == .cameraReview && screen != .cameraReview && screen != .confirmation { camera.discardCapture() }
        }
    }
    var selectedPhotoID: String?
    var selectedPhoto: AlbumPhoto? { store.archive.photos.first { $0.id == selectedPhotoID } }
    var editingFilter: RetroPhotoFilter = .original
    var editingStamp = false
    var editedPhoto: RenderedAlbumImage?
    var photoEditBusy = false
    private let photoRenderer = PhotoRenderWorker()
    private var photoEditTask: Task<Void, Never>?
    private var photoEditGeneration = 0
    var selection = 0
    var draft = ""
    var notice = ""
    var revision = 0
    var textPage = 0
    var busy = false
    var photoPickerPresented = false
    var photoTarget: PhotoTarget = .sticker
    var selectedStickerID: String?
    var editorPhoto: String?
    var editorMemory: String?
    var editorCaption = ""
    var editorShape: StickerShape = .heart
    var cropX = 0.5
    var cropY = 0.5
    var cropZoom = 1.0
    var placementMode = 0
    var momentText = ""
    var momentPhoto: String?
    var momentDay = MemoryStore.dayID()
    var momentPrompt = MemoryStore.promptIndex()
    var viewedMomentID: String?
    var friends: [FriendContact] = []
    var gifts: [StickerGift] = []
    var receivedMail: [SpecialMail] = []
    var selectedFriendID: String?
    var selectedGiftID: String?
    var selectedMailID: String?
    var visitedPhone: VisitedPhone?
    var giftAssetIndex = 0
    var giftMessage = ""
    var giftRequestID = UUID().uuidString
    var mailOpened = false
    var receivedMailPhoto: Data?
    var sharingMoment: DailyMoment?
    var confirmationText = ""
    var connectedOwner: String?
    private var sessionRevision = 0
    private var onlineTask: Task<Void, Never>?
    func setBackend(_ backend: (any FriendshipBackend)?) {
        onlineTask?.cancel(); sessionRevision += 1; self.backend = backend
        connectedOwner = nil; friends = []; gifts = []; receivedMail = []; visitedPhone = nil
        selectedFriendID = nil; selectedGiftID = nil; selectedMailID = nil
        receivedMailPhoto = nil; sharingMoment = nil
        busy = false; home()
        if backend != nil { sync() }
    }
    var soundEnabled: Bool { didSet { UserDefaults.standard.set(soundEnabled, forKey: "pacchi.sound") } }
    var savedMemo: String { didSet { UserDefaults.standard.set(savedMemo, forKey: "pacchi.memo") } }
    let menu = ["メモを書く", "保存したメモ", "着信音のおためし", "サウンド設定", "つかいかた", "思い出シール", "友達の電話", "ギフト受信箱", "とくべつな手紙", "今日のひとこま", "電話の共有", "カメラ", "しゃしんアルバム"]
    private var history: [(Screen, Int)] = []
    private var lastKey = ""
    private var lastPress = Date.distantPast
    private var cycle = 0
    private let letters = ["1": ".,!?1", "2": "abc2", "3": "def3", "4": "ghi4", "5": "jkl5", "6": "mno6", "7": "pqrs7", "8": "tuv8", "9": "wxyz9", "0": " 0"]
    init(store: MemoryStore? = nil, backend: (any FriendshipBackend)? = nil) {
        self.store = store ?? MemoryStore(); self.backend = backend
        soundEnabled = UserDefaults.standard.object(forKey: "pacchi.sound") as? Bool ?? true
        savedMemo = UserDefaults.standard.string(forKey: "pacchi.memo") ?? ""
        restoreMoment()
    }
    var selectedSticker: MemorySticker? { store.archive.stickers.first { $0.id == selectedStickerID && ($0.ownerId == nil || $0.ownerId == connectedOwner) } }
    var visibleStickers: [MemorySticker] { store.archive.stickers.filter { $0.ownerId == nil || $0.ownerId == connectedOwner } }
    var selectedFriend: FriendContact? { friends.first { $0.id == selectedFriendID } }
    var selectedGift: StickerGift? { gifts.first { $0.id == selectedGiftID } }
    var selectedMail: SpecialMail? { receivedMail.first { $0.id == selectedMailID } }
    var mailDraft: SpecialMail { store.archive.mailDraft }
    var isTyping: Bool { [.memo, .caption, .mailText, .dailyText, .giftText].contains(screen) }
    var currentText: String {
        get {
            switch screen { case .memo: draft; case .caption: editorCaption; case .mailText: mailDraft.message; case .dailyText: momentText; case .giftText: giftMessage; default: "" }
        }
        set {
            switch screen {
            case .memo: draft = newValue
            case .caption: editorCaption = newValue
            case .giftText: giftMessage = newValue
            case .mailText: perform { try store.update { $0.mailDraft.message = newValue } }
            case .dailyText: momentText = newValue; persistMomentDraft()
            default: break
            }
        }
    }
    func play(_ tone: RetroSoundManager.Tone) { if soundEnabled { RetroSoundManager.shared.play(tone) } }
    func refresh() { revision += 1 }
    func enter(_ destination: Screen) {
        history.append((screen, selection)); screen = destination; selection = 0; textPage = 0; notice = ""; lastKey = ""; refresh()
    }
    func openMenu() { guard !busy else { return }; home(); enter(.menu) }
    func showMessage(_ text: String) { confirmationText = text; enter(.confirmation) }
    @discardableResult func perform(_ operation: () throws -> Void) -> Bool {
        do { try operation(); return true }
        catch { showMessage(error.localizedDescription); play(.error); return false }
    }
    func move(_ delta: Int) { direction(dx: 0, dy: delta) }
    func direction(dx: Int, dy: Int) {
        guard !busy else { return }
        play(screen == .album || screen == .photoDetail ? .albumSelect : .navigation)
        if screen == .home { enter(.menu) }
        else if screen == .camera {
            guard !camera.isCapturing else { return }
            if dx != 0 { camera.filter = camera.filter.next(dx) }
            if dy != 0 { camera.adjustZoom(Double(-dy) * 0.25) }
        } else if screen == .album {
            let count = store.archive.photos.count
            guard count > 0 else { selection = 0; return }
            selection = min(max(0, selection), count - 1)
            selection = min(count - 1, max(0, selection + dx + dy * 3))
        } else if screen == .photoDetail {
            let photos = store.archive.photos
            guard !photos.isEmpty else { return }
            let index = photos.firstIndex(where: { $0.id == selectedPhotoID }) ?? 0
            let next = min(photos.count - 1, max(0, index + (dx == 0 ? dy : dx)))
            selectedPhotoID = photos[safe: next]?.id; selection = next
        } else if screen == .photoEdit {
            if dx != 0 { editingFilter = editingFilter.next(dx) }
            if dy != 0 { editingStamp.toggle() }
            renderPhotoEdit()
        } else if screen == .crop {
            cropX = min(1, max(0, cropX + Double(dx) * 0.05)); cropY = min(1, max(0, cropY + Double(dy) * 0.05))
        } else if screen == .placement {
            adjustPlacement(dx: dx, dy: dy)
        } else if !rows.isEmpty {
            let count = rows.count
            let current = min(max(0, selection), count - 1)
            selection = (current + (dy == 0 ? dx : dy) % count + count) % count
        } else if !isTyping {
            textPage = max(0, min(textPages.count - 1, textPage + (dy == 0 ? dx : dy)))
        } else { lastKey = "" }
        refresh()
    }
    func select() {
        guard !busy else { return }
        play(.select); notice = ""
        let options = rows
        if !options.isEmpty { selection = min(max(0, selection), options.count - 1) }
        switch screen {
        case .home: enter(.menu)
        case .menu:
            let targets: [Screen] = [.memo, .saved, .ringtone, .settings, .help, .stickers, .contacts, .inbox, .mail, .daily, .sharing, .camera, .album]
            if let target = targets[safe: selection] { if target == .daily { restoreMoment() }; enter(target) }
        case .camera:
            if camera.status == .running {
                camera.capture { [weak self] in
                    guard let self, self.screen == .camera else { return }
                    self.play(.shutter); self.enter(.cameraReview)
                }
            } else if !camera.isCapturing { camera.start() }
        case .cameraReview:
            if selection == 0, let shot = camera.captured {
                if perform({ selectedPhotoID = try store.saveCapture(shot) }) {
                    play(.photoSave); screen = .photoDetail; selection = 0; history = [(.home, 0), (.menu, 12), (.album, 0)]
                }
            } else if selection == 1 { goBack() }
        case .album:
            guard let photo = store.archive.photos[safe: selection] else { notice = "カメラで思い出を残そう"; return }
            selectedPhotoID = photo.id; enter(.photoDetail)
        case .photoDetail: if selectedPhoto != nil { enter(.photoActions) }
        case .photoActions: photoAction()
        case .photoEdit:
            guard !photoEditBusy, let id = selectedPhotoID, let rendered = editedPhoto else { notice = "写真を処理しています"; return }
            if perform({ try store.updatePhoto(id, filter: editingFilter, stamp: editingStamp, jpeg: rendered.jpeg) }) { play(.photoSave); goBack() }
        case .photoDeleteConfirm:
            if selection == 1, let id = selectedPhotoID {
                if perform({ try store.deletePhoto(id) }) {
                    selectedPhotoID = nil; screen = .album; selection = min(selection, max(0, store.archive.photos.count - 1)); history = [(.home, 0), (.menu, 12)]
                }
            } else { goBack() }
        case .memo:
            guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { notice = "文字を入力してね"; return }
            savedMemo = draft; enter(.saved)
        case .settings: soundEnabled.toggle()
        case .ringtone: play(.notification)
        case .saved, .help, .confirmation, .connection, .momentStory: goBack()
        case .stickers:
            if selection == 0 { startEditor() }
            else if let sticker = visibleStickers[safe: selection - 1] { selectedStickerID = sticker.id; enter(.stickerStory) }
        case .stickerStory: enter(.stickerActions)
        case .stickerActions: stickerAction()
        case .deleteConfirm:
            if selection == 1, let id = selectedStickerID {
                guard perform({ try store.deleteSticker(id) }) else { return }; screen = .stickers; history = [(.home, 0), (.menu, 5)]; selection = 0
            } else { goBack() }
        case .createSource:
            if selection == 0 { photoTarget = .sticker; photoPickerPresented = true }
            else if selection == 1 {
                guard !savedMemo.isEmpty else { showMessage("先にメモを書いて保存してね。"); return }
                editorMemory = savedMemo; enter(.shape)
            } else {
                let moments = store.archive.moments.filter { !$0.skipped }
                guard let moment = moments.last else { showMessage("先に今日のひとこまを残してね。"); return }
                editorMemory = moment.response; editorPhoto = moment.imageReference; enter(editorPhoto == nil ? .shape : .crop)
            }
        case .crop:
            guard let source = editorPhoto else { return }
            perform {
                let cropped = try store.crop(source, zoom: cropZoom, x: cropX, y: cropY)
                editorPhoto = cropped; store.removeUnusedPhoto(source); enter(.shape)
            }
        case .shape: if let shape = StickerShape.allCases[safe: selection] { editorShape = shape; enter(.caption) }
        case .caption:
            perform {
                selectedStickerID = try store.addHandmade(shape: editorShape, caption: editorCaption, photo: editorPhoto, memory: editorMemory)
                editorPhoto = nil; editorMemory = nil; screen = .stickerStory; selection = 0; history = [(.home, 0), (.menu, 5), (.stickers, 0)]; refresh()
            }
        case .placement: placementMode = (placementMode + 1) % 3
        case .contacts:
            if backend == nil { enter(.connection) }
            else if selection == 0 { sync() }
            else if let friend = friends[safe: selection - 1] { selectedFriendID = friend.id; enter(.friend) }
        case .friend: friendAction()
        case .visit: goBack()
        case .giftPicker:
            guard GiftAsset.collection.indices.contains(selection) else { return }
            giftAssetIndex = selection; giftMessage = ""; giftRequestID = UUID().uuidString; enter(.giftText)
        case .giftText: sendGift()
        case .inbox:
            if backend == nil { enter(.connection) }
            else if selection == 0 { sync() }
            else if let gift = gifts[safe: selection - 1] { selectedGiftID = gift.id; enter(.giftDetail) }
        case .giftDetail: acceptGift()
        case .mail:
            switch selection { case 0: enter(.mailText); case 1: enter(.mailEnvelope); case 2: enter(.mailStamp); case 3: enter(.mailSound); case 4: enter(.mailPreview); case 5: enter(.mailInbox); default:
                if perform({ try store.update { $0.mailDraft = SpecialMail() } }) { showMessage("空の下書きを新しくしました。") } }
        case .mailText: goBack()
        case .mailEnvelope: if perform({ try store.update { $0.mailDraft.envelopeStyle = selection } }) { goBack() }
        case .mailStamp: if perform({ try store.update { $0.mailDraft.stampStyle = selection } }) { goBack() }
        case .mailSound:
            guard perform({ try store.update { $0.mailDraft.sound = selection } }) else { return }; play(selection == 0 ? .notification : .select); goBack()
        case .mailPreview: sendMail()
        case .mailInbox:
            if backend == nil { enter(.connection) }
            else if selection == 0 { sync() }
            else if let mail = receivedMail[safe: selection - 1] { selectedMailID = mail.id; mailOpened = false; receivedMailPhoto = nil; enter(.mailReceived) }
        case .mailReceived:
            if !mailOpened {
                mailOpened = true; play(selectedMail?.sound == 0 ? .notification : .select)
                if let mail = selectedMail, mail.imageReference != nil {
                    runOnline { backend in
                        let data = try await backend.mailPhoto(mailId: mail.id)
                        try Task.checkCancellation(); self.receivedMailPhoto = data
                    }
                }
            } else { goBack() }
        case .daily: dailyAction()
        case .dailySharePreview: sendDailyMoment()
        case .dailyText: if persistMomentDraft() { goBack() }
        case .momentHistory:
            let moments = store.archive.moments.filter { !$0.skipped }.reversed().map { $0 }
            if moments.indices.contains(selection) { viewedMomentID = moments[selection].id; enter(.momentStory) }
        case .sharing:
            if selection == 0 { perform { try store.update { $0.profile.visibility = $0.profile.visibility == .private ? .friends : .private } } }
            else if selection == 1 { enter(.shareSelect) }
            else { publish() }
        case .shareSelect:
            let eligible = visibleStickers.filter { $0.assetId != nil }
            guard eligible.indices.contains(selection) else { return }
            let id = eligible[selection].id
            perform { try store.update { state in
                if state.profile.publicStickerIds.contains(id) { state.profile.publicStickerIds.removeAll { $0 == id } }
                else { state.profile.publicStickerIds.append(id) }
            } }
        }
        refresh()
    }
    private func photoAction() {
        guard let photo = selectedPhoto else { showMessage("写真が見つかりません。"); return }
        switch selection {
        case 0: perform { try store.favoritePhoto(photo.id) }
        case 1:
            editingFilter = photo.filter; editingStamp = photo.dateStamp; editedPhoto = nil
            enter(.photoEdit); renderPhotoEdit()
        case 2:
            perform {
                let copy = try store.copyPhotoForSticker(photo)
                startEditor(); editorPhoto = copy; editorMemory = "写メ " + PhotoProcessing.dateText(photo.capturedAt, timeZone: photo.timeZoneIdentifier)
                enter(.crop)
            }
        case 3: enter(.photoDeleteConfirm)
        default: screen = .album; selection = store.archive.photos.firstIndex(where: { $0.id == photo.id }) ?? 0; history = [(.home, 0), (.menu, 12)]
        }
    }
    func renderPhotoEdit() {
        photoEditTask?.cancel(); photoEditGeneration += 1
        guard let photo = selectedPhoto, let url = store.imageURL(photo.originalReference) else { return }
        let generation = photoEditGeneration, filter = editingFilter, stamp = editingStamp
        photoEditBusy = true; editedPhoto = nil
        photoEditTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rendered = try await photoRenderer.render(url: url, filter: filter, stamp: stamp, date: photo.capturedAt, timeZone: photo.timeZoneIdentifier)
                guard !Task.isCancelled, screen == .photoEdit, generation == photoEditGeneration else { return }
                editedPhoto = rendered; photoEditBusy = false
            } catch {
                guard !Task.isCancelled, generation == photoEditGeneration else { return }
                photoEditBusy = false; showMessage(error.localizedDescription)
            }
        }
    }
    private func stickerAction() {
        guard let id = selectedStickerID, let sticker = selectedSticker else { return }
        switch selection {
        case 0:
            guard perform({ try store.editSticker(id) { $0.placed = true } }) else { return }; placementMode = 0; enter(.placement)
        case 1: perform { try store.editSticker(id) { $0.placed.toggle() } }
        case 2: perform { try store.editSticker(id) { $0.layer = (store.archive.stickers.map(\.layer).max() ?? 0) + 1 } }
        case 3:
            guard let memoryID = sticker.linkedMemoryId, let memory = store.archive.memories.first(where: { $0.id == memoryID }) else {
                showMessage("このシールには端末内の本文がありません。友達の記念シールには非公開の会話を保存しません。"); return
            }
            showMessage(memory.text)
        default: enter(.deleteConfirm)
        }
    }
    func back() {
        guard !busy else { return }; play(.back)
        if isTyping && !currentText.isEmpty { currentText.removeLast(); lastKey = "" }
        else { goBack() }
        refresh()
    }
    private func goBack() {
        if screen == .placement { placementMode = 0 }
        if let previous = history.popLast() { screen = previous.0; selection = previous.1 }
        else { screen = .home; selection = 0 }
        if !rows.isEmpty { selection = min(max(0, selection), rows.count - 1) }
        if screen == .photoEdit { renderPhotoEdit() }
        textPage = 0; lastKey = ""; notice = ""
    }
    func home() {
        guard !busy else { return }
        play(.back); camera.stop(); camera.discardCapture(); sharingMoment = nil; receivedMailPhoto = nil; screen = .home; history = []; selection = 0; notice = ""; refresh()
    }
    func number(_ key: String) {
        guard !busy else { return }
        // Update input before playing audio, so audio device startup cannot break multi-tap timing.
        if isTyping {
            if key == "*" { if !currentText.isEmpty { currentText.removeLast() }; lastKey = "" }
            else if key == "#" { lastKey = ""; notice = "次の文字を入力" }
            else if let characters = letters[key] {
                let chars = Array(characters); let now = Date()
                let limit = screen == .caption ? 24 : (screen == .memo || screen == .giftText ? 60 : 240)
                if key == lastKey && now.timeIntervalSince(lastPress) < 0.8 && !currentText.isEmpty {
                    var text = currentText; text.removeLast(); cycle = (cycle + 1) % chars.count; text.append(chars[cycle]); currentText = text
                } else {
                    guard currentText.count < limit else { notice = "\(limit)文字までです"; play(.error); return }
                    cycle = 0; currentText.append(chars[cycle])
                }
                lastKey = key; lastPress = now; notice = ""
            }
        } else if screen == .camera && key == "#" { if !camera.isCapturing { camera.dateStamp.toggle() } }
        else if screen == .photoDetail && key == "#", let id = selectedPhotoID { perform { try store.favoritePhoto(id) } }
        else if screen == .photoEdit && key == "#" { editingStamp.toggle(); renderPhotoEdit() }
        else if screen == .crop && (key == "2" || key == "8") {
            cropZoom = min(3, max(1, cropZoom + (key == "2" ? 0.2 : -0.2)))
        } else if screen == .placement && key == "#" { placementMode = (placementMode + 1) % 3 }
        else if key == "*" { back(); return }
        else if key == "#" && screen == .menu { selection = min(rows.count - 1, ((selection / 5 + 1) * 5) % rows.count) }
        else if key == "#" && screen == .home { enter(.settings) }
        else if let n = Int(key), !rows.isEmpty {
            let index = n == 0 ? 9 : n - 1
            if rows.indices.contains(index) { selection = index; select(); return } else { play(.error) }
        } else if let n = Int(key), screen == .home, (1...9).contains(n) { enter(.menu); selection = n - 1; select(); return }
        else { play(.error) }
        play(.number); refresh()
    }
    func startEditor() {
        store.removeUnusedPhoto(editorPhoto); editorPhoto = nil; editorMemory = nil; editorCaption = ""; cropX = 0.5; cropY = 0.5; cropZoom = 1; enter(.createSource)
    }
    func receivedPhoto(_ data: Data) {
        perform {
            let ref = try store.importPhoto(data)
            if photoTarget == .sticker { store.removeUnusedPhoto(editorPhoto); editorPhoto = ref; cropX = 0.5; cropY = 0.5; cropZoom = 1; enter(.crop) }
            else { let previous = momentPhoto; momentPhoto = ref; persistMomentDraft(); store.removeUnusedPhoto(previous) }
        }
    }
    private func adjustPlacement(dx: Int, dy: Int) {
        guard let id = selectedStickerID else { return }
        perform { try store.editSticker(id) {
            switch placementMode {
            case 0: $0.position.x += Double(dx) * 0.04; $0.position.y += Double(dy) * 0.04
            case 1: $0.scale += Double(dx - dy) * 0.1
            default: $0.rotation += Double(dx - dy) * 10
            }
        } }
    }
    func transformSticker(_ id: String, position: StickerPosition? = nil, scale: Double? = nil, rotation: Double? = nil) {
        perform { try store.editSticker(id) {
            if let position { $0.position = position }; if let scale { $0.scale = scale }; if let rotation { $0.rotation = rotation }
        } }
    }
    func openSticker(_ id: String) { guard screen != .placement, !busy else { return }; selectedStickerID = id; enter(.stickerStory) }
    func restoreMoment() {
        momentDay = MemoryStore.dayID(); momentPrompt = MemoryStore.promptIndex()
        let moment = store.archive.momentDraft?.id == momentDay ? store.archive.momentDraft : store.archive.moments.first { $0.id == momentDay }
        momentText = moment?.response ?? ""; momentPhoto = moment?.imageReference
    }
    @discardableResult private func persistMomentDraft() -> Bool {
        perform { try store.update { $0.momentDraft = DailyMoment(id: momentDay, promptId: momentPrompt, response: momentText, imageReference: momentPhoto, createdAt: Date()) } }
    }
    private func dailyAction() {
        switch selection {
        case 0: enter(.dailyText)
        case 1: photoTarget = .daily; photoPickerPresented = true
        case 2:
            guard !momentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || momentPhoto != nil else { showMessage("文字か写真をひとつ残してね。スキップもできます。"); return }
            guard perform({ try store.update { state in
                state.moments.removeAll { $0.id == momentDay }
                state.moments.append(DailyMoment(id: momentDay, promptId: momentPrompt, response: momentText, imageReference: momentPhoto, createdAt: Date())); state.momentDraft = nil
            } }) else { return }
            showMessage("今日のひとこまを保存しました。\nまた、気が向いた日に。")
        case 3:
            guard !momentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || momentPhoto != nil else { showMessage("文字か写真をひとつ残してね。"); return }
            sharingMoment = DailyMoment(id: momentDay, promptId: momentPrompt, response: momentText, imageReference: momentPhoto, createdAt: Date())
            enter(.contacts)
        case 4:
            guard perform({ try store.update { state in
                if !state.moments.contains(where: { $0.id == momentDay }) {
                    state.moments.append(DailyMoment(id: momentDay, promptId: momentPrompt, response: "", createdAt: Date(), skipped: true))
                }
            } }) else { return }; home()
        default: enter(.momentHistory)
        }
    }
    private func friendAction() {
        switch selection {
        case 0:
            runOnline { backend in
                guard let id = self.selectedFriendID else { throw MemoryError.missing }
                let visited = try await backend.visit(friendId: id); try Task.checkCancellation(); self.visitedPhone = visited; self.enter(.visit)
            }
        case 1: enter(.giftPicker)
        case 2:
            if sharingMoment != nil { enter(.dailySharePreview) }
            else { guard perform({ try store.update { $0.mailDraft.recipientId = selectedFriendID } }) else { return }; enter(.mail) }
        default:
            runOnline { backend in
                guard let id = self.selectedFriendID else { throw MemoryError.missing }
                try await backend.block(friendId: id)
                try Task.checkCancellation()
                self.friends.removeAll { $0.id == id }; self.visitedPhone = nil; self.screen = .contacts; self.selection = 0
                self.showMessage("ブロックしました。以降の訪問・送受信はできません。")
            }
        }
    }
    private func sendGift() {
        runOnline { backend in
            guard let friendId = self.selectedFriendID, self.friends.contains(where: { $0.id == friendId }) else { throw MemoryError.missing }
            guard let asset = GiftAsset.collection[safe: self.giftAssetIndex] else { throw MemoryError.missing }
            let gift = StickerGift(id: self.giftRequestID, senderId: backend.ownerId, recipientId: friendId, stickerAssetId: asset.id, message: self.giftMessage, status: .pending, createdAt: Date())
            try await backend.sendGift(gift)
            try Task.checkCancellation()
            self.giftRequestID = UUID().uuidString; self.giftMessage = ""; self.showMessage("ギフトを送りました。")
        }
    }
    private func acceptGift() {
        guard let gift = selectedGift, gift.status == .pending else { showMessage("このギフトは受け取り済みです。"); return }
        runOnline { backend in
            try await backend.acceptGift(id: gift.id)
            try await self.reload(backend)
            self.showMessage("受け取りました。思い出シールから本体に貼れます。")
        }
    }
    private func sendDailyMoment() {
        guard let moment = sharingMoment, let recipient = selectedFriendID else { return }
        runOnline { backend in
            let photo = try moment.imageReference.map { try self.store.shareablePhoto($0) }
            try await backend.sendMoment(moment, photo: photo, recipientId: recipient)
            try Task.checkCancellation()
            self.sharingMoment = nil
            self.showMessage("今日のひとこまを選んだ友達へ送りました。手紙の受信箱に届きます。")
        }
    }
    private func sendMail() {
        guard !mailDraft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { showMessage("手紙の本文を書いてね。"); return }
        guard let recipient = mailDraft.recipientId, friends.contains(where: { $0.id == recipient }) else { enter(.contacts); return }
        runOnline { backend in
            var mail = self.mailDraft; mail.senderId = backend.ownerId; mail.recipientId = recipient
            try await backend.sendMail(mail)
            try Task.checkCancellation()
            try self.store.update { $0.mailDraft = SpecialMail() }
            self.showMessage("手紙を送りました。")
        }
    }
    private func publish() {
        runOnline { backend in
            let profile = self.store.archive.profile
            let decorations = self.visibleStickers.filter { profile.publicStickerIds.contains($0.id) && $0.placed }.compactMap { sticker -> SharedDecoration? in
                guard let assetId = sticker.assetId, GiftAsset.collection.contains(where: { $0.id == assetId }) else { return nil }
                return SharedDecoration(id: sticker.id, assetId: assetId, position: sticker.position, rotation: sticker.rotation, scale: sticker.scale)
            }
            try await backend.publish(profile: profile, decorations: decorations)
            try Task.checkCancellation()
            self.showMessage(profile.visibility == .private ? "共有を非公開にしました。" : "選んだ飾りだけを友達に共有しました。写真・本文・思い出は共有しません。")
        }
    }
    func sync() { runOnline { try await self.reload($0) } }
    private func reload(_ backend: any FriendshipBackend) async throws {
        let snapshot = try await backend.snapshot()
        try Task.checkCancellation()
        guard snapshot.ownerId == backend.ownerId else { throw MemoryError.invalidResponse }
        let oldPending = Set(gifts.filter { $0.status == .pending }.map(\.id))
        let oldMail = Set(receivedMail.map(\.id))
        connectedOwner = backend.ownerId
        try store.mergeVerifiedStickers(snapshot.stickers, ownerId: backend.ownerId)
        friends = snapshot.friends; gifts = snapshot.gifts; receivedMail = snapshot.mail
        if snapshot.gifts.contains(where: { $0.status == .pending && !oldPending.contains($0.id) }) || snapshot.mail.contains(where: { !oldMail.contains($0.id) }) { play(.notification) }
        notice = "更新しました"
    }
    private func runOnline(_ action: @escaping @MainActor (any FriendshipBackend) async throws -> Void) {
        guard let backend else { enter(.connection); return }
        busy = true; notice = "接続中…"
        let version = sessionRevision
        onlineTask = Task { @MainActor in
            defer { if version == sessionRevision { busy = false; refresh() } }
            do {
                try Task.checkCancellation()
                try await action(backend)
            } catch {
                guard version == sessionRevision, !Task.isCancelled else { return }
                showMessage(error.localizedDescription); play(.error)
            }
        }
    }
    var leftLabel: String {
        if busy { return "接続中" }
        switch screen {
        case .camera: return camera.isCapturing ? "撮影中…" : "SHOT ♡"
        case .cameraReview: return "決定"
        case .album: return "ひらく"
        case .photoDetail: return "操作 / # ♡"
        case .photoEdit: return photoEditBusy ? "処理中…" : "保存"
        case .home: return "メニュー"
        case .memo, .caption: return "保存"
        case .crop: return "切り抜く"
        case .placement: return ["移動→サイズ", "サイズ→回転", "回転→移動"][safe: placementMode] ?? "操作"
        case .stickerStory: return "操作"
        case .giftText, .mailPreview, .dailySharePreview: return "送信"
        case .mailReceived: return mailOpened ? "戻る" : "開封"
        case .giftDetail: return "受け取る"
        case .ringtone: return "再生"
        case .settings: return "切替"
        case .dailyText, .mailText: return "完了"
        default: return "決定"
        }
    }
}
