import Foundation
import SwiftUI
import CoreGraphics
import ImageIO

@main struct MemoryFeatureChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pacchi-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let priorSound = UserDefaults.standard.object(forKey: "pacchi.sound")
        let priorMemo = UserDefaults.standard.object(forKey: "pacchi.memo")
        defer {
            if let priorSound { UserDefaults.standard.set(priorSound, forKey: "pacchi.sound") } else { UserDefaults.standard.removeObject(forKey: "pacchi.sound") }
            if let priorMemo { UserDefaults.standard.set(priorMemo, forKey: "pacchi.memo") } else { UserDefaults.standard.removeObject(forKey: "pacchi.memo") }
        }
        let store = MemoryStore(directory: directory)
        let nav = PhoneNavigationManager(store: store)
        nav.soundEnabled = false
        nav.select(); nav.move(-1)
        precondition(nav.selection == nav.menu.count - 1, "Menu must wrap through all features")
        nav.number("1"); nav.number("2"); nav.number("2")
        precondition(nav.draft == "b", "Multi-tap must replace the previous letter")
        nav.number("#"); nav.number("2")
        precondition(nav.draft == "ba")
        nav.select()
        precondition(nav.savedMemo == "ba")
        nav.home(); nav.enter(.stickers); nav.select()
        nav.selection = 1; nav.select()
        precondition(nav.screen == .shape)
        nav.selection = 3; nav.select()
        nav.number("2"); nav.select()
        precondition(store.archive.stickers.count == 1)
        let handmade = store.archive.stickers[0]
        precondition(handmade.shape == .bow && handmade.ownerId == nil)
        precondition(store.archive.memories[0].text == "ba")
        nav.select(); nav.select()
        precondition(nav.screen == .placement)
        nav.direction(dx: 1, dy: 0); nav.select(); nav.direction(dx: 1, dy: 0)
        precondition(store.archive.stickers[0].position.x > 0.5 && store.archive.stickers[0].scale > 1)
        let restored = MemoryStore(directory: directory)
        precondition(restored.archive.stickers[0] == store.archive.stickers[0], "Placement must survive restart")
        precondition(restored.archive.memories[0].text == "ba", "Private story must survive restart")

        let remote = MemorySticker(id: "milestone-1", ownerId: "alice", friendId: "bob", title: "FIRST HELLO", type: .firstHello, imageReference: "evil.jpg", linkedMemoryId: "not-authorized", createdAt: Date())
        try store.mergeVerifiedStickers([remote, remote], ownerId: "alice")
        precondition(store.archive.stickers.filter { $0.id == remote.id }.count == 1, "Duplicate events must not duplicate stickers")
        precondition(store.archive.stickers.last?.linkedMemoryId == nil && store.archive.stickers.last?.imageReference == nil)
        precondition(nav.visibleStickers.count == 1, "Signed-out view must not show another account's stickers")
        nav.connectedOwner = "alice"
        precondition(nav.visibleStickers.count == 2)
        try store.deleteSticker(remote.id)
        try store.mergeVerifiedStickers([remote], ownerId: "alice")
        precondition(!store.archive.stickers.contains { $0.id == remote.id }, "Deleted remote sticker must not reappear after sync")
        try store.editSticker(handmade.id) { $0.scale = 100; $0.position.x = -20 }
        precondition(store.archive.stickers[0].scale == 1.7 && store.archive.stickers[0].position.x == 0)
        try store.deleteSticker(handmade.id)
        precondition(store.archive.stickers.isEmpty && store.archive.memories.isEmpty)

        nav.home(); nav.enter(.daily); nav.select(); nav.number("2"); nav.select()
        nav.selection = 2; nav.select()
        precondition(store.archive.moments.count == 1)
        nav.home(); nav.enter(.daily); nav.selection = 2; nav.select()
        precondition(store.archive.moments.count == 1, "Saving the same day must update instead of duplicate")
        precondition(MemoryStore(directory: directory).archive.moments.count == 1)
        nav.home(); nav.enter(.mail); nav.select(); nav.number("2"); nav.select()
        precondition(MemoryStore(directory: directory).archive.mailDraft.message == "a", "Mail draft must persist")
        nav.home(); nav.enter(.contacts); nav.select()
        precondition(nav.screen == .connection && nav.friends.isEmpty, "Disconnected app must not invent contacts")

        // Crop a real image and verify the source pixels are cropped, not just visually masked.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); CGImageDestinationFinalize(destination)
        let reference = try store.importPhoto(data as Data)
        let cropped = try store.crop(reference, zoom: 2, x: 1, y: 0)
        precondition(store.image(cropped)?.width == 20 && store.image(cropped)?.height == 20)
        precondition(store.imageURL("../escape.jpg") == nil)
        do { _ = try store.importPhoto(Data([0, 1, 2])); preconditionFailure("Invalid image should fail") } catch {}
        let broken = directory.appendingPathComponent("broken")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        let brokenData = Data("not json".utf8)
        try brokenData.write(to: broken.appendingPathComponent("memories-v1.json"))
        let brokenStore = MemoryStore(directory: broken)
        do { try brokenStore.update { $0.stickers = [] }; preconditionFailure("Corrupt archive must not be overwritten") } catch {}
        let preservedData = try Data(contentsOf: broken.appendingPathComponent("memories-v1.json"))
        precondition(preservedData == brokenData)
        print("PASS: navigation, handmade stories, persistence, placement bounds, account filtering, idempotent sync/deletion, daily upsert, drafts, disconnected state, image crop, corrupt-file protection")
    }
}
