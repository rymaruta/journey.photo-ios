import Foundation
import Combine

/// 「この1枚をカバーにしますか？」を差し出す頃合いと、断られた覚え（#304・板 51 CoverOffer・51b CoverOfferLiked・2026-10-18）。
///
/// - **初めての投稿の直後に一度だけ**（`notePosted`）。カバーを持っている人には出さない。出す順は**通知の説明より前**
///   （`RootView` は通知の説明をこれが決め終わるまで待たせる・`isDeciding`）
/// - **いいねが集まった1枚**（`CoverOfferRules.likedThreshold` 件）を、次にアプリを開いた頃合いで一度だけ。写真ごとに1回まで。
///   カバーを持っている人にも出す（いまのカバーに選んだ写真なら出さない）。出す順は**いちばん後ろ**
/// - 「あとで」: 初めての投稿の差し出しを閉じる。いいねが集まったときにもう一度聞く
/// - 「今のままにする」: その写真ではもう聞かない
/// - 「もう聞かないで」: どちらの差し出しも二度と出さない
/// - 引いて閉じたのは「あとで」と同じ（板 51 の付箋）
///
/// 覚えは端末に uid ごとに置く（サーバーには置かない。端末を替えると一度は聞き直すことがある——2026-10-18 判断:
/// 断られた覚えのためにサーバーの行を増やさない）
@MainActor
final class CoverOfferStore: ObservableObject {

    static let shared = CoverOfferStore()

    /// 差し出す中身
    struct Offer: Identifiable, Equatable {
        enum Kind: Equatable {
            case firstPost
            /// いいねが集まった（件数）
            case liked(Int)
        }
        let kind: Kind
        let photoId: String
        let imageURL: URL?
        /// 写真の題（いいねの差し出しの本文に出す。無題なら空）
        let title: String
        /// いまカバーを持っているか（51b の「入れ替わります」の一行）
        let hasCover: Bool
        /// 硬貨の行を出すか（旅のトランクが使えて、カバーがまだ無い人）
        let showsCoins: Bool
        var id: String { "\(photoId)-\(kind)" }
    }

    /// 初めての投稿を確かめる合図の回数（`RootView` が見る）
    @Published private(set) var postRequests = 0
    /// 差し出しを出してよい中身が入った回数
    @Published private(set) var requests = 0
    /// 初めての投稿の差し出しを決めている途中（通知の説明・評価・届いた画面はこれを待つ）
    @Published private(set) var isDeciding = false
    private(set) var pending: Offer?
    /// 合図のときに上がった写真の ID
    private(set) var postedIds: Set<String> = []

    private let defaults: UserDefaults
    private let isPreview: () -> Bool
    /// いまの持ち主（差し出し・合図はこの人のもの。替わったら下ろす・`noteUser`）
    private(set) var owner: String?

    init(defaults: UserDefaults = .standard,
         isPreview: @escaping () -> Bool = { PreviewSession.userId != nil }) {
        self.defaults = defaults
        self.isPreview = isPreview
    }

    nonisolated static func firstKey(_ userId: String) -> String { "coverOffer.first.\(userId)" }
    nonisolated static func neverKey(_ userId: String) -> String { "coverOffer.never.\(userId)" }
    nonisolated static func askedKey(_ userId: String) -> String { "coverOffer.asked.\(userId)" }
    nonisolated static func coverKey(_ userId: String) -> String { "coverOffer.cover.\(userId)" }

    /// 「もう聞かないで」を選んだ
    func isNever(_ userId: String) -> Bool { defaults.bool(forKey: Self.neverKey(userId)) }
    /// 初めての投稿の差し出しを出した（または確かめ終えた）
    func firstDone(_ userId: String) -> Bool { defaults.bool(forKey: Self.firstKey(userId)) }
    /// いいねの差し出しで聞いた写真
    func asked(_ userId: String) -> Set<String> { Set(defaults.stringArray(forKey: Self.askedKey(userId)) ?? []) }
    /// アプリから最後にカバーにした写真（いいねの差し出しで同じ写真を出さない）
    func currentCover(_ userId: String) -> String? { defaults.string(forKey: Self.coverKey(userId)) }

    /// 全部上がった投稿（`UploadViewModel`）。**まだ確かめていない人でだけ**合図する。
    /// 通知の説明（`PushPrimerStore.notePosted`）より**先に**呼ぶ——ここで「決めている途中」を立てる
    func notePosted(userId: String?, photoIds: [String]) {
        guard !isPreview(), let userId, !userId.isEmpty, !photoIds.isEmpty,
              !firstDone(userId), !isNever(userId) else { return }
        noteUser(userId)
        postedIds = Set(photoIds)
        isDeciding = true
        postRequests += 1
    }

    /// 初めての投稿の差し出しを決め終えた。出すなら中身を渡す（出さない回は nil）。
    /// **確かめた時点で「初めて」の印を立てる**——2枚目からは初めてではないので、出さなかった回も聞き直さない
    func finishFirstPost(userId: String?, offer: Offer?, checked: Bool) {
        // 下ろすのは同じ人の決め終わりだけ（前の人の決め終わりで今の人の「決めている途中」を下ろさない。
        // 人が替わったときは `noteUser` が下ろしてある）
        defer { if userId == owner { isDeciding = false } }
        guard let userId else { return }
        if checked { defaults.set(true, forKey: Self.firstKey(userId)) }
        // 決める間に人が替わった回は、いまの人に出さない
        guard let offer, owner == userId else { return }
        pending = offer
        requests += 1
    }

    /// いいねが集まった1枚を出す待ちへ入れる（`RootView` が起動のときに確かめた）
    func offerLiked(_ offer: Offer, userId: String) {
        noteUser(userId)
        guard !isNever(userId), pending == nil else { return }
        pending = offer
        requests += 1
    }

    var hasPending: Bool { pending != nil }

    func consume() -> Offer? {
        defer { pending = nil }
        return pending
    }

    /// 出した（いいねの差し出しは、その写真ではもう聞かない）
    func noteShown(_ offer: Offer, userId: String?) {
        guard let userId else { return }
        if case .liked = offer.kind { remember(asked: offer.photoId, userId: userId) }
    }

    /// 「もう聞かないで」
    func chooseNever(userId: String?) {
        guard let userId else { return }
        defaults.set(true, forKey: Self.neverKey(userId))
    }

    /// カバーにした（アプリのどこからでも。いいねの差し出しで同じ写真を出さない）
    func noteCoverSet(photoId: String?, userId: String?) {
        guard let userId else { return }
        if let photoId { defaults.set(photoId, forKey: Self.coverKey(userId)) } else { defaults.removeObject(forKey: Self.coverKey(userId)) }
    }

    /// 入っている人が替わった（ログアウトを含む）。前の人の差し出し・合図・決めている途中を下ろす
    /// （`ProfileReward.noteUser` と同じ形。残すと通知の説明・評価・届いた画面が `coverOfferBusy` で止まったままになる）
    func noteUser(_ userId: String?) {
        guard userId != owner else { return }
        owner = userId
        pending = nil
        postedIds = []
        isDeciding = false
    }

    /// 画面写真の見本（`-JPPreviewCoverOffer`）
    func deliverPreview(_ offer: Offer) {
        pending = offer
        requests += 1
    }

    private func remember(asked photoId: String, userId: String) {
        var list = defaults.stringArray(forKey: Self.askedKey(userId)) ?? []
        guard !list.contains(photoId) else { return }
        list.append(photoId)
        // 古いものから落とす（1人の写真の数より十分大きい）
        defaults.set(Array(list.suffix(500)), forKey: Self.askedKey(userId))
    }

    /// 退会のとき（`AccountLocalData.remove`）
    nonisolated static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        for key in [firstKey(userId), neverKey(userId), askedKey(userId), coverKey(userId)] {
            defaults.removeObject(forKey: key)
        }
    }
}
