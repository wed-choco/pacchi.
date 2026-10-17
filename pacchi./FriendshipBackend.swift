import Foundation

/// Adapt the app's existing authenticated session; this module never creates users or friendships.
@MainActor
protocol FriendshipBackend {
    var ownerId: String { get }
    func snapshot() async throws -> FriendshipSnapshot
    func visit(friendId: String) async throws -> VisitedPhone
    func publish(profile: PhoneProfile, decorations: [SharedDecoration]) async throws
    func sendGift(_ gift: StickerGift) async throws
    func acceptGift(id: String) async throws
    func sendMail(_ mail: SpecialMail) async throws
    func sendMoment(_ moment: DailyMoment, photo: Data?, recipientId: String) async throws
    func mailPhoto(mailId: String) async throws -> Data
    func block(friendId: String) async throws
}

/// Implements Firebase's authenticated callable wire protocol without adding an SDK dependency.
/// Supply fresh Firebase ID / App Check tokens from the host app, not from local preferences.
struct FirebaseSessionCredential {
    let ownerId: String
    let idToken: String
}

@MainActor
final class FirebaseFriendshipBackend: FriendshipBackend {
    let ownerId: String
    private let baseURL: URL
    private let credential: () async throws -> FirebaseSessionCredential
    private let appCheckToken: () async throws -> String
    init(ownerId: String, baseURL: URL, credential: @escaping () async throws -> FirebaseSessionCredential,
         appCheckToken: @escaping () async throws -> String) {
        self.ownerId = ownerId; self.baseURL = baseURL; self.credential = credential; self.appCheckToken = appCheckToken
    }
    private func call<Input: Encodable, Output: Decodable>(_ name: String, _ input: Input) async throws -> Output {
        guard baseURL.scheme == "https" else { throw MemoryError.invalidResponse }
        let session = try await credential()
        guard session.ownerId == ownerId else { throw MemoryError.service("ログイン状態が変わりました。開き直してください。") }
        var request = URLRequest(url: baseURL.appendingPathComponent(name))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.idToken)", forHTTPHeaderField: "Authorization")
        request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(CallableRequest(data: input))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MemoryError.invalidResponse }
        if http.statusCode != 200 {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let status = (error?["error"] as? [String: Any])?["status"] as? String
            switch status {
            case "UNAUTHENTICATED": throw MemoryError.service("ログインし直してからお試しください。")
            case "PERMISSION_DENIED": throw MemoryError.service("この操作は許可されていません。友達の承認・公開範囲・ブロックを確認してください。")
            case "FAILED_PRECONDITION": throw MemoryError.service("接続先の設定がまだ完了していません。")
            case "ALREADY_EXISTS": throw MemoryError.service("送信内容が変更されています。下書きを確認してください。")
            default: throw MemoryError.invalidResponse
            }
        }
        try Task.checkCancellation()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw MemoryError.invalidResponse }
            return date
        }
        return try decoder.decode(CallableResponse<Output>.self, from: data).result
    }
    func snapshot() async throws -> FriendshipSnapshot { try await call("pacchiSnapshot", Empty()) }
    func visit(friendId: String) async throws -> VisitedPhone { try await call("pacchiVisit", FriendID(friendId: friendId)) }
    func publish(profile: PhoneProfile, decorations: [SharedDecoration]) async throws {
        let _: Empty = try await call("pacchiPublish", Publish(profile: profile, decorations: decorations))
    }
    func sendGift(_ gift: StickerGift) async throws { let _: Empty = try await call("pacchiSendGift", gift) }
    func acceptGift(id: String) async throws { let _: Empty = try await call("pacchiAcceptGift", Identifier(id: id)) }
    func sendMail(_ mail: SpecialMail) async throws { let _: Empty = try await call("pacchiSendMail", mail) }
    func block(friendId: String) async throws { let _: Empty = try await call("pacchiBlock", FriendID(friendId: friendId)) }
    func sendMoment(_ moment: DailyMoment, photo: Data?, recipientId: String) async throws {
        let _: Empty = try await call("pacchiSendMoment", MomentRequest(dayId: moment.id, recipientId: recipientId, promptId: moment.promptId, response: moment.response, imageBase64: photo?.base64EncodedString()))
    }
    func mailPhoto(mailId: String) async throws -> Data {
        let result: PhotoResponse = try await call("pacchiMailPhoto", Identifier(id: mailId))
        guard let data = Data(base64Encoded: result.imageBase64), data.count <= 200_000 else { throw MemoryError.invalidImage }
        return data
    }
    private struct MomentRequest: Encodable { let dayId: String; let recipientId: String; let promptId: Int; let response: String; let imageBase64: String? }
    private struct PhotoResponse: Decodable { let imageBase64: String }
    private struct Empty: Codable {}
    private struct FriendID: Encodable { let friendId: String }
    private struct Identifier: Encodable { let id: String }
    private struct Publish: Encodable { let profile: PhoneProfile; let decorations: [SharedDecoration] }
    private struct CallableRequest<T: Encodable>: Encodable { let data: T }
    private struct CallableResponse<T: Decodable>: Decodable { let result: T }
}
