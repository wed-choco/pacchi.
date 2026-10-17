import Foundation
import SwiftUI
import CoreImage
import CoreGraphics
import ImageIO

@main struct CameraAlbumChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pacchi-album-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sound = UserDefaults.standard.object(forKey: "pacchi.sound")
        defer { if let sound { UserDefaults.standard.set(sound, forKey: "pacchi.sound") } else { UserDefaults.standard.removeObject(forKey: "pacchi.sound") } }

        var legacy = PhoneArchive()
        let sticker = MemorySticker(id: "legacy-sticker", title: "old memory", type: .handmade, createdAt: Date())
        legacy.stickers = [sticker]
        legacy.memories = [PrivateMemory(id: "old", text: "keep this", createdAt: Date())]
        legacy.moments = [DailyMoment(id: "2026-10-17", promptId: 2, response: "keep this moment", createdAt: Date())]
        legacy.mailDraft.message = "keep this letter"
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        oldJSON["version"] = 1; oldJSON.removeValue(forKey: "photos")
        let oldData = try JSONSerialization.data(withJSONObject: oldJSON)
        let file = root.appendingPathComponent("memories-v1.json")
        try oldData.write(to: file)
        let store = MemoryStore(directory: root)
        precondition(store.loadError == nil && store.archive.version == 2 && store.archive.photos.isEmpty)
        precondition(store.archive.stickers == [sticker] && store.archive.memories[0].text == "keep this")
        precondition(store.archive.mailDraft.message == "keep this letter" && store.archive.moments[0].response == "keep this moment")
        let backup = try Data(contentsOf: root.appendingPathComponent("memories-before-album.json"))
        precondition(backup == oldData, "Exact v1 bytes must be backed up")
        let stillOld = try Data(contentsOf: file)
        precondition(stillOld == oldData, "Reading v1 must not rewrite it")
        let minimal = try JSONDecoder().decode(PhoneArchive.self, from: Data("{\"version\":1}".utf8))
        precondition(minimal.photos.isEmpty && minimal.stickers.isEmpty)

        let context = CGContext(data: nil, width: 160, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 160, height: 200))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 20, y: 30, width: 60, height: 70))
        let image = context.makeImage()!
        let tagged = NSMutableData()
        let taggedDestination = CGImageDestinationCreateWithData(tagged, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(taggedDestination, image, [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 35.0, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 139.0, kCGImagePropertyGPSLongitudeRef: "E"
        ]] as CFDictionary)
        precondition(CGImageDestinationFinalize(taggedDestination))
        let taggedSource = CGImageSourceCreateWithData(tagged as CFData, nil)!
        let taggedProperties = CGImageSourceCopyPropertiesAtIndex(taggedSource, 0, nil) as? [CFString: Any]
        precondition(taggedProperties?[kCGImagePropertyGPSDictionary] != nil)
        let sanitized = try PhotoProcessing.jpeg(PhotoProcessing.normalized(tagged as Data))
        let sanitizedSource = CGImageSourceCreateWithData(sanitized as CFData, nil)!
        let sanitizedProperties = CGImageSourceCopyPropertiesAtIndex(sanitizedSource, 0, nil) as? [CFString: Any]
        precondition(sanitizedProperties?[kCGImagePropertyGPSDictionary] == nil, "Camera normalization must discard source GPS")
        let original = try PhotoProcessing.jpeg(image)
        let date = ISO8601DateFormatter().date(from: "2026-10-17T15:30:00Z")!
        precondition(PhotoProcessing.dateText(date, timeZone: "Asia/Tokyo") == "2026.10.18")
        precondition(RetroPhotoFilter.original.next(-1) == .softPink)
        let (processed, pinkJPEG) = try PhotoProcessing.process(image, filter: .softPink, stamp: true, date: date, timeZone: "Asia/Tokyo")
        precondition(processed.width == image.width && processed.height == image.height)
        precondition(pinkJPEG != original)
        let shot = CapturedPhoto(original: image, processed: processed, originalJPEG: original, processedJPEG: pinkJPEG,
            capturedAt: date, filter: .softPink, dateStamp: true, timeZoneIdentifier: "Asia/Tokyo")
        let id = try store.saveCapture(shot)
        let saved = store.archive.photos[0]
        precondition(saved.id == id && saved.originalReference != saved.processedReference)
        let originalURL = store.imageURL(saved.originalReference)!
        let initialOriginal = try Data(contentsOf: originalURL)
        precondition(initialOriginal == original)
        try store.favoritePhoto(id)
        let restarted = MemoryStore(directory: root)
        precondition(restarted.archive.photos[0].favorite && restarted.archive.stickers == [sticker])
        precondition(restarted.archive.mailDraft.message == "keep this letter")
        let (_, heiseiJPEG) = try PhotoProcessing.process(image, filter: .heisei, stamp: false, date: date, timeZone: "Asia/Tokyo")
        try store.updatePhoto(id, filter: .heisei, stamp: false, jpeg: heiseiJPEG)
        precondition(store.archive.photos[0].originalReference == saved.originalReference)
        let unchangedOriginal = try Data(contentsOf: originalURL)
        precondition(unchangedOriginal == original)
        precondition(!FileManager.default.fileExists(atPath: store.imageURL(saved.processedReference)!.path))
        precondition(store.image(store.archive.photos[0].processedReference, maximum: 64)!.width <= 64)
        let source = CGImageSourceCreateWithData(heiseiJPEG as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        precondition(properties?[kCGImagePropertyGPSDictionary] == nil)
        let second = try store.saveCapture(shot)
        precondition(store.archive.photos.first?.id == second, "Newest save must be first")

        let nav = PhoneNavigationManager(store: store); nav.soundEnabled = false
        nav.enter(.album); nav.selection = Int.max; nav.direction(dx: 1, dy: 0)
        precondition(nav.selection == 1)
        nav.select(); precondition(nav.screen == .photoDetail)
        nav.direction(dx: -1, dy: 0); precondition(nav.selectedPhotoID == second)
        nav.select(); nav.selection = 1; nav.select()
        precondition(nav.screen == .photoEdit && nav.photoEditBusy)
        for _ in 0..<500 {
            if !nav.photoEditBusy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(!nav.photoEditBusy && nav.editedPhoto != nil)
        nav.direction(dx: 1, dy: 0)
        for _ in 0..<500 {
            if !nav.photoEditBusy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let chosenFilter = nav.editingFilter
        nav.select()
        precondition(nav.screen == .photoActions && nav.editedPhoto == nil)
        precondition(nav.selectedPhoto?.filter == chosenFilter)
        nav.selection = 2; nav.select()
        precondition(nav.screen == .crop && nav.editorPhoto != nil)
        let copy = nav.editorPhoto!
        precondition(copy != store.archive.photos[0].processedReference)
        nav.select(); nav.select(); nav.select()
        precondition(nav.screen == .stickerStory)
        let madeSticker = nav.selectedSticker!
        let stickerURL = store.imageURL(madeSticker.imageReference)!
        try store.deletePhoto(second)
        precondition(FileManager.default.fileExists(atPath: stickerURL.path), "Deleting album original must not break sticker")
        try store.deletePhoto(id)
        precondition(!FileManager.default.fileExists(atPath: originalURL.path))
        precondition(store.archive.photos.isEmpty)
        nav.home(); nav.enter(.album); nav.selection = -100; nav.select()
        precondition(nav.screen == .album)
        nav.home(); nav.enter(.shape); nav.selection = 999; nav.select()
        precondition(nav.screen == .caption, "Stale shape index must be clamped")
        nav.placementMode = -999; nav.screen = .placement; _ = nav.title; _ = nav.leftLabel
        nav.momentPrompt = -1; nav.screen = .dailyText; _ = nav.title
        nav.home(); nav.enter(.camera); nav.camera.start()
        #if !os(iOS) || targetEnvironment(simulator)
        if case .unavailable = nav.camera.status {} else { preconditionFailure("Non-device camera must explain its limitation") }
        #endif
        nav.home(); precondition(nav.camera.status == .idle)
        let future = root.appendingPathComponent("future")
        try FileManager.default.createDirectory(at: future, withIntermediateDirectories: true)
        let futureData = Data("{\"version\":999}".utf8)
        try futureData.write(to: future.appendingPathComponent("memories-v1.json"))
        let futureStore = MemoryStore(directory: future)
        precondition(futureStore.loadError != nil)
        do { try futureStore.update { $0.photos = [] }; preconditionFailure() } catch {}
        print("PASS: v1 backup/migration, missing-key decoding, existing memories/mail/daily preserved, photo save/reload/order/favorite, re-filter original preservation, thumbnail bounds, GPS-free encoding, copied sticker independence, file deletion, stale/negative selection safety, camera unsupported/stop, future-version protection")
    }
}
