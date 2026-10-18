import Foundation

/// **「この写真を見て撮影」**（`inspiredBy`・2026-10-14 owner「写真から、次の旅が始まるSNS」）。
///
/// 人の写真を見てその場所へ行って撮った人が、投稿で元の写真を付ける。サーバーの決まりは
/// photo-gallery の `docs/inspired-by.md`（`api-user/src/inspired.ts`）:
///
/// - 投稿（`POST /upload/save`）に `inspiredBy: "<元の写真の id>"`。**見られない元の写真は黙って付かない**
///   （投稿は成功）——付いたかは応答の `photo.inspiredBy` で分かる
/// - 編集（`PUT /photos/{id}`）で `inspiredBy: null` を送ると外れる
/// - 写真の行は ID だけを持つ。中身は `GET /user/inspired/{id}`（認証）で、**読むときにも見られるか確かめた**ものだけ
///
/// 画面の部品は Linux で動かせないので、判断はここに値で試せる形で集める。**通信しない。**
enum InspiredBy {

    // MARK: - 送る ID

    /// サーバーが受ける形（英数とハイフン・1〜64文字・`inspired.ts` の `sanitizeInspiredBy`）。
    /// 合わない値は送らない（送ると 400 で投稿ごと止まる）
    static let maxIdLength = 64

    static func normalizedId(_ raw: String?) -> String? {
        let id = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.utf8.count <= maxIdLength,
              id.utf8.allSatisfy({ byte in
                  (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A)
                      || (byte >= 0x61 && byte <= 0x7A) || byte == 0x2D
              }) else { return nil }
        return id
    }

    /// 写真に元の写真が付いているか（編集で「外す」を出すか）。**形を問わない**——
    /// 見知らぬ形の値でも、外せないまま残さない
    static func isAttached(_ photo: Photo) -> Bool {
        !(photo.inspiredBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 投稿で選んだ元の写真

    /// 投稿の画面で選んだ元の写真。**表示に要る最小だけ**を持つ（下書きにも残す・`UploadDraftStore.Draft`）。
    /// 下書きから戻したとき、手元の一覧を読み直さなくても欄に出せるように
    struct Pick: Codable, Equatable {
        var id: String
        /// 題（無ければ空）
        var title: String
        /// 欄に出す小さな画像（256px → 512px → 本体の順で軽いもの）
        var thumbURL: String?
        /// 作者の名前（一覧の行が持っていれば）
        var authorName: String?
        /// 撮影地（読み上げ・題の無い写真の言い換え）
        var location: String?

        init(id: String, title: String, thumbURL: String?, authorName: String?, location: String?) {
            self.id = id
            self.title = title
            self.thumbURL = thumbURL
            self.authorName = authorName
            self.location = location
        }

        init(photo: Photo) {
            let thumb = [photo.thumbSm, photo.src256, photo.thumbSrc].compactMap { $0 }
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? photo.src
            self.init(id: photo.id, title: photo.displayTitle, thumbURL: thumb,
                      authorName: photo.displayName.flatMap { $0.isEmpty ? nil : $0 },
                      location: photo.location)
        }

        /// 欄の右に出す一言（題 → 撮影地 → 「写真」）
        var label: String {
            if !title.isEmpty { return title }
            let place = LocationMatch.display(location)
            if !place.isEmpty { return place }
            return L("写真", "Photo")
        }
    }

    /// 投稿の1枚に付ける ID（形の合うものだけ）
    static func idToSend(_ pick: Pick?) -> String? {
        normalizedId(pick?.id)
    }

    /// **元の写真を載せる1枚**（2026-10-14 の確かめ）。投稿のうち1枚だけに付け、その1枚を覚える。
    ///
    /// 🔴 サーバーは**付いた写真1枚ごとに**元の作者へ通知を1回送る（`notifyInspiredOnce`）。
    /// 3枚の全部に付けると同じ人に3回届く。以前は「付け終えたか」の真偽値だけで、保存の答えが
    /// 来なかった（時間切れ・500＝届いたか分からない）1枚のあと、2枚目にも載せていた——
    /// 1枚目が実は通っていれば通知が2回届く。
    ///
    /// - 載せる1枚は、最初に送り始めた写真に決める
    /// - その1枚が**届いたか分からない**間は、後ろの写真には載せない。やり直しもその1枚に載せる
    /// - 別の写真に引き継ぐのは、**確実に届いていない**とき（鍵・本体の PUT の失敗、アルバムが無い）と、
    ///   その1枚を帯から外したときだけ
    struct Carrier<ID: Hashable>: Equatable {
        /// 載せる1枚（まだ決めていなければ nil）
        private(set) var photo: ID?
        /// その1枚の保存が通った（以後どの写真にも載せない）
        private(set) var attached = false

        init() {}

        /// この写真の保存に載せる ID。まだ1枚に決めていなければ、この写真に決める
        mutating func idToSend(for item: ID, pick: Pick?) -> String? {
            guard !attached, let id = InspiredBy.idToSend(pick) else { return nil }
            if photo == nil { photo = item }
            return photo == item ? id : nil
        }

        /// 保存が通った（「保存済み」の 409 も、前の送信で載せていれば通ったものとする）
        mutating func saved(_ item: ID) {
            if photo == item { attached = true }
        }

        /// 確実に届いていない（鍵・PUT の失敗・アルバムが無い）。次の写真に引き継ぐ
        mutating func notDelivered(_ item: ID) {
            if photo == item && !attached { photo = nil }
        }

        /// 帯から外した。届いたか分からない写真でも、外したなら次の写真に引き継ぐ
        mutating func removed(_ item: ID) {
            notDelivered(item)
        }

        /// 下書きに元の写真を残してよいか。**付け終えた・載せた1枚が届いたか分からない**なら残さない
        /// （開き直して別の写真に付き、通知が2回届く）
        func keepsInDraft(unsure: Set<ID>) -> Bool {
            guard !attached else { return false }
            guard let photo else { return true }
            return !unsure.contains(photo)
        }
    }

    /// 送ったのに付かなかったか（元の写真が非公開・削除・ブロックになった）。
    /// 応答に写真が無い回（古いサーバー・形が違う）は分からないので「付かなかった」と言わない
    static func wasDropped(sent: String?, saved: Photo?) -> Bool {
        guard let sent = normalizedId(sent), let saved else { return false }
        return normalizedId(saved.inspiredBy) != sent
    }

    /// 付かなかったときの知らせ（投稿自体は成功）
    static var droppedNote: String {
        L("投稿しました。元の写真は付けられませんでした（非公開になったか、削除された可能性があります）",
          "Posted, but the original photo couldn't be attached (it may have been made private or deleted).")
    }

    // MARK: - 写真の詳細の行

    /// `GET /user/inspired/{id}` の `inspiredBy`
    struct Source: Decodable, Equatable {
        let id: String
        let title: LocalizedText?
        let src: String
        let thumbSrc: String?
        let location: String?
        let userId: String?
        let displayName: String?
        let username: String?

        var displayTitle: String { PhotoTitle.display(title?.resolved()) }

        /// 行の小さな画像。**空の文字は無いのと同じ**（`Photo.pinImageURL` と同じ）
        var thumbURL: URL? {
            let candidate = [thumbSrc].compactMap { $0 }
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? src
            return URL(string: candidate)
        }

        /// 作者の呼び名（表示名 → @名）。どちらも無ければ nil（名前を作らない）
        var authorName: String? {
            if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
            if let handle = username?.trimmingCharacters(in: .whitespacesAndNewlines), !handle.isEmpty { return "@\(handle)" }
            return nil
        }
    }

    /// 応答の形。`{ inspiredBy: null }` は「付いていない・もう見られない」
    struct Response: Decodable {
        let inspiredBy: Source?
    }

    /// 読み終えた結果。**どの写真の、どの元の写真で読んだか**を持つ（写真を送った直後に前の写真の行を
    /// 出さないため・`PhotoTrip.Loaded` と同じ考え）
    struct Loaded: Equatable {
        /// 読んだときの人（**人が替わったら使わない**——ブロックの関係は人ごとに違う）
        let userId: String
        let photoId: String
        let sourceId: String
        /// 出してよい元の写真。null・404 なら nil（何も出さない）
        let source: Source?
    }

    /// 今の写真に対する段階
    enum Stage: Equatable {
        /// 元の写真が付いていない・ログインしていない（読みに行かない）
        case none
        /// 付いているが、まだこの写真の分を読み終えていない（前の写真の分しか無いときも）
        case loading
        /// この写真の分を読み終えた
        case ready(Source?)

        /// 出す元の写真（この写真の分を読み終えて、出せるものがあるときだけ）
        var source: Source? {
            if case .ready(let source) = self { return source }
            return nil
        }
    }

    /// 写真と手元の読み込み結果から段階を決める。**読んだ人・写真・元の写真が違えば使わない**。
    /// 口は認証が要るので、ログインしていなければ読まない（出さない）
    static func stage(photoId: String, inspiredBy: String?, userId: String?, loaded: Loaded?) -> Stage {
        guard let userId, !userId.isEmpty, let sourceId = normalizedId(inspiredBy) else { return .none }
        guard let loaded, loaded.userId == userId, loaded.photoId == photoId, loaded.sourceId == sourceId else {
            return .loading
        }
        return .ready(loaded.source)
    }

    /// 読みに行く鍵（`.task(id:)`）。**人も入れる**（入り直したら読み直す）。
    /// 付いていない・ログインしていない写真は空（読みに行かない）
    static func loadKey(photoId: String, inspiredBy: String?, userId: String?) -> String {
        guard let userId, !userId.isEmpty, let sourceId = normalizedId(inspiredBy) else { return "" }
        return "\(userId)|\(photoId)>\(sourceId)"
    }

    /// 元の写真を開くときの1枚。**公開一覧に居ればその行**（撮影情報・説明まで揃う）、
    /// 居なければ要約から作る（建て直しの前など）。要約から作れなければ nil（押せない行にしない＝行を出さない）
    static func photoToOpen(_ source: Source, feed: [Photo]?) -> (photo: Photo, fromPublicFeed: Bool)? {
        if let listed = feed?.first(where: { $0.id == source.id }) { return (listed, true) }
        guard let photo = photo(from: source) else { return nil }
        return (photo, false)
    }

    /// 要約を写真の形にする（題は `{ja, en}` もそのまま）
    static func photo(from source: Source) -> Photo? {
        var row: [String: Any] = ["id": source.id, "src": source.src]
        if let thumb = source.thumbSrc { row["thumbSrc"] = thumb }
        if let location = source.location { row["location"] = location }
        if let userId = source.userId { row["userId"] = userId }
        if let name = source.displayName { row["displayName"] = name }
        switch source.title {
        case .plain(let text): row["title"] = text
        case .byLocale(let map): row["title"] = map
        case nil: break
        }
        guard let data = try? JSONSerialization.data(withJSONObject: row) else { return nil }
        return try? JSONDecoder.api.decode(Photo.self, from: data)
    }

    /// 行の読み上げ（「この写真を見て撮影: 題、作者」）
    static func spokenLabel(_ source: Source) -> String {
        var parts: [String] = []
        let title = source.displayTitle
        if !title.isEmpty {
            parts.append(title)
        } else {
            let place = LocationMatch.display(source.location)
            if !place.isEmpty { parts.append(place) }
        }
        if let author = source.authorName { parts.append(author) }
        let detail = parts.joined(separator: L("、", ", "))
        return detail.isEmpty
            ? L("この写真を見て撮影", "Inspired by this photo")
            : L("この写真を見て撮影: \(detail)", "Inspired by: \(detail)")
    }

    // MARK: - 画面写真の見本（`PreviewSession.showsInspiredSample`・Debug のみ）

    /// 見本のときに写真の元の写真の ID として使う印（本物の ID の形には当たらない綴りにしない——
    /// `normalizedId` を通る形にして、段階の決まりを本物と同じ道で通す）
    static let previewSourceId = "preview-inspired-sample"

    /// 見本の元の写真: 公開一覧のうち、付けられる写真で `excluding`（いま開いている写真）でない最初の1枚
    static func previewSample(feed: [Photo]?, excluding photoId: String?) -> Photo? {
        feed?.first { canAttach($0) && $0.id != photoId }
    }

    /// 写真を `GET /user/inspired` の要約の形にする（見本だけ・口を呼ばない）
    static func previewSource(_ photo: Photo) -> Source {
        Source(id: photo.id, title: photo.title, src: photo.src, thumbSrc: photo.thumbSrc,
               location: photo.location, userId: photo.userId ?? photo.uploadedBy,
               displayName: photo.displayName, username: nil)
    }

    // MARK: - 元の写真を選ぶ（投稿の画面）

    /// 選ぶ先の棚
    enum Shelf: String, CaseIterable, Identifiable {
        /// 保存（しおり）した写真
        case saved
        /// 行きたい場所の写真（写真の詳細の「行きたい」から入れた場所を含む）
        case wishlist

        var id: String { rawValue }

        var label: String {
            switch self {
            case .saved: return L("保存した写真", "Saved")
            case .wishlist: return L("行きたい場所", "Want to go")
            }
        }

        var emptyMessage: String {
            switch self {
            case .saved:
                return L("保存した写真はまだありません。写真の詳細のしおりで保存できます",
                         "No saved photos yet. Tap the bookmark on a photo to save it.")
            case .wishlist:
                return L("行きたい場所の写真はまだありません。写真の詳細の「行きたい」で場所を入れると、ここに並びます",
                         "No photos from places you want to go yet. Tap “Want to go” on a photo to add its place.")
            }
        }
    }

    /// 付けられる写真か。**公開で全員に見せている写真だけ**——それ以外はサーバーが黙って付けない
    /// （`readVisibleSource`）ので、選ばせない。下書き・絞った写真は自分の写真でも出さない
    static func canAttach(_ photo: Photo) -> Bool {
        normalizedId(photo.id) != nil && PhotoTrip.isPublic(photo)
            && !photo.src.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 棚に並べる数の上限（端末の控えから作る一覧なので、選ぶのに困らない数で切る）
    static let shelfLimit = 90

    /// 保存（しおり）した写真。手元の束（公開一覧 → 自分の写真）から引き当てる（`LikedPhotos.resolve`）
    static func savedCandidates(ids: Set<String>, feed: [Photo]?, mine: [Photo]?) -> [Photo] {
        let found = LikedPhotos.resolve(ids, in: [feed ?? [], mine ?? []])
        return Array(found.filter(canAttach).prefix(shelfLimit))
    }

    /// 行きたい場所の写真。公開一覧のうち、撮影地のスラッグか台帳のスポット（`SPOT-<slug>`）が
    /// 「行きたい」に入っている写真（鍵の決まりは `PhotoTrip.Destination.wishKey` と同じ）。
    ///
    /// **いま書いている撮影地と同じ場所の写真を先に**（その場所で撮って投稿している人がいちばん探す）。
    /// そのあとは新しい順
    static func wishCandidates(keys: Set<String>, feed: [Photo]?, index: [OfficialSpot]?,
                               currentLocation: String? = nil) -> [Photo] {
        guard !keys.isEmpty, let feed else { return [] }
        let slugBySpotId = Dictionary((index ?? []).map { ($0.spotId, $0.slug) }, uniquingKeysWith: { first, _ in first })
        let here = LocationSlug.make(currentLocation)
        var seen = Set<String>()
        var matched: [Photo] = []
        var first: [Photo] = []
        for photo in GallerySort.new.apply(feed) where canAttach(photo) && seen.insert(photo.id).inserted {
            let place = LocationSlug.make(photo.location)
            var photoKeys: [String] = []
            if !place.isEmpty { photoKeys.append(place) }
            if let spotId = PhotoTrip.normalizedSpotId(photo.spotId), let slug = slugBySpotId[spotId],
               !slug.trimmingCharacters(in: .whitespaces).isEmpty {
                photoKeys.append(SavedSpotKey.official(slug))
            }
            guard photoKeys.contains(where: keys.contains) else { continue }
            if !here.isEmpty && place == here { first.append(photo) } else { matched.append(photo) }
        }
        return Array((first + matched).prefix(shelfLimit))
    }
}
