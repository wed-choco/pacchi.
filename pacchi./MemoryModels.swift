import Foundation

struct StickerPosition: Codable, Equatable {
    var x = 0.5
    var y = 0.5
}

enum StickerShape: String, Codable, CaseIterable {
    case heart, star, circle, bow, rectangle
    var label: String {
        switch self { case .heart: "ハート"; case .star: "ほし"; case .circle: "まる"; case .bow: "リボン"; case .rectangle: "しかく" }
    }
}

enum MemoryStickerType: String, Codable {
    case handmade, firstHello, firstPhoto, anniversary, birthday, gift
    var title: String {
        switch self {
        case .handmade: "MY LITTLE MEMORY"
        case .firstHello: "FIRST HELLO"
        case .firstPhoto: "FIRST PHOTO"
        case .anniversary: "FRIENDSHIP DAY"
        case .birthday: "HAPPY BIRTHDAY"
        case .gift: "A LITTLE GIFT"
        }
    }
    var story: String {
        switch self {
        case .handmade: "自分でつくった、小さな思い出。"
        case .firstHello: "はじめてメッセージを交わした日。"
        case .firstPhoto: "はじめて写真を分けあった日。"
        case .anniversary: "友達になった、大切な記念日。"
        case .birthday: "教えてくれたお誕生日をお祝い。"
        case .gift: "友達から届いた、小さな贈りもの。"
        }
    }
}

struct MemorySticker: Identifiable, Codable, Equatable {
    var id: String
    // nil means device-local, never an invented Firebase identity.
    var ownerId: String?
    var friendId: String?
    var title: String
    var type: MemoryStickerType
    var imageReference: String?
    var linkedMemoryId: String?
    var createdAt: Date
    var position = StickerPosition()
    var rotation = 0.0
    var scale = 1.0
    var shape: StickerShape = .heart
    var placed = false
    var layer = 0
    var assetId: String?
}

struct PrivateMemory: Identifiable, Codable {
    var id: String
    var text: String
    var createdAt: Date
}

struct StickerGift: Identifiable, Codable {
    enum Status: String, Codable { case pending, accepted, declined }
    var id: String
    var senderId: String
    var recipientId: String
    var stickerAssetId: String
    var message: String
    var status: Status
    var createdAt: Date
}

struct PhoneProfile: Codable {
    enum Visibility: String, Codable { case `private`, friends }
    var ownerId: String?
    var phoneColor = "#F4B8CA"
    var publicStickerIds: [String] = []
    var visibility: Visibility = .private
    var updatedAt = Date()
}

struct SpecialMail: Identifiable, Codable {
    var id = UUID().uuidString
    var senderId: String?
    var recipientId: String?
    var envelopeStyle = 0
    var stampStyle = 0
    var sound = 0
    var message = ""
    var createdAt = Date()
    // Server scheduling is intentionally not offered until a trusted scheduler exists.
    var scheduledDeliveryAt: Date?
    var imageReference: String?
    var delivered = false
    var opened = false
}

struct DailyMoment: Identifiable, Codable {
    var id: String
    var ownerId: String?
    var promptId: Int
    var response: String
    var imageReference: String?
    var createdAt: Date
    var skipped = false
}

struct PhoneArchive: Codable {
    var version = 2
    var stickers: [MemorySticker] = []
    var memories: [PrivateMemory] = []
    var profile = PhoneProfile()
    var mailDraft = SpecialMail()
    var moments: [DailyMoment] = []
    var momentDraft: DailyMoment?
    var deletedStickerIDs: [String]? = []
    var photos: [AlbumPhoto] = []

    init() {}
    enum CodingKeys: String, CodingKey {
        case version, stickers, memories, profile, mailDraft, moments, momentDraft, deletedStickerIDs, photos
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        stickers = try c.decodeIfPresent([MemorySticker].self, forKey: .stickers) ?? []
        memories = try c.decodeIfPresent([PrivateMemory].self, forKey: .memories) ?? []
        profile = try c.decodeIfPresent(PhoneProfile.self, forKey: .profile) ?? PhoneProfile()
        mailDraft = try c.decodeIfPresent(SpecialMail.self, forKey: .mailDraft) ?? SpecialMail()
        moments = try c.decodeIfPresent([DailyMoment].self, forKey: .moments) ?? []
        momentDraft = try c.decodeIfPresent(DailyMoment.self, forKey: .momentDraft)
        deletedStickerIDs = try c.decodeIfPresent([String].self, forKey: .deletedStickerIDs) ?? []
        photos = try c.decodeIfPresent([AlbumPhoto].self, forKey: .photos) ?? []
    }
}

struct FriendContact: Identifiable, Codable {
    var id: String
    var name: String
}

// A visit receives only allowlisted decorative assets, never local photos or memory links.
struct SharedDecoration: Identifiable, Codable {
    var id: String
    var assetId: String
    var position: StickerPosition
    var rotation: Double
    var scale: Double
}
struct VisitedPhone: Codable {
    var ownerId: String
    var phoneColor: String
    var stickers: [SharedDecoration]
}
struct FriendshipSnapshot: Codable {
    var ownerId: String
    var friends: [FriendContact]
    var stickers: [MemorySticker]
    var gifts: [StickerGift]
    var mail: [SpecialMail]
}

struct GiftAsset: Identifiable {
    let id: String
    let name: String
    let shape: StickerShape
    static let collection = [
        GiftAsset(id: "pixel-heart", name: "ときめきハート", shape: .heart),
        GiftAsset(id: "pixel-star", name: "おまもりスター", shape: .star),
        GiftAsset(id: "pixel-bow", name: "おそろいリボン", shape: .bow)
    ]
}
