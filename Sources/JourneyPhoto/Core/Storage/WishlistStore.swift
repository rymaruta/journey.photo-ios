import Foundation
import Combine

/// 「行きたい場所」（モック5・モック2）。
///
/// 🔴 **鍵は `/location/<スラッグ>` のスラッグ**（`LocationSlug`）。
/// サーバーの「行きたい場所」（`spots#<uid>`）に入っているのと**同じ文字列**で、
/// Web の一覧とも突き合わさる。
///
/// **台帳の撮影スポットは `SPOT-<slug>`**（`SavedSpotKey`・Web の
/// `savedSpotKey.ts` と同じ）。同じ入れ物に入るが、頭で見分けるので
/// 撮影地の鍵とは混ざらない。マイページの一覧は両方を並べる
/// （スポットの側は `OfficialWishlist.rows` が索引と突き合わせる）。
///
/// **ログイン中はサーバーが本体**（`SavedSpotService`・`GET|POST /user/spots`・
/// `DELETE /user/spots/{slug}`）。ここは `SavedPhotosStore` と同じ役目の**控え**で、
/// 押した瞬間に画面を変え、圏外でも一覧を出す。同期の仕掛けも同じもの
/// （`LocalEdits` の印・`replace(with:for:since:)`・持ち主の照合）を使い、
/// 送る・戻す・合わせる手順は `WishlistSync` が持つ。
///
/// ⚠️ 以前ここに「api-user に『行きたい』の口は無い」と書いてあったが、**誤り**
/// ——サーバーには前から在り、Web（`useSavedSpots`）は使っていた。アプリだけが
/// 端末に閉じていたので、アプリで押した場所は Web にも機種変の後にも出なかった。
///
/// **未ログインの間は端末だけ**（共有の鍵）。ログインした回にその人へ引き継ぎ、
/// 次の同期でサーバーへ送る（`use(userId:)`・`replace`）。
/// **他人の「行きたい」数は出さない**（サーバーも本人の一覧しか返さない）。
///
/// 鍵はアカウントごとに分ける（`FavoritesStore` と同じ理由——同じ端末で
/// 人が変わったときに前の人の印を吸い込まないため）。
@MainActor
final class WishlistStore: ObservableObject {

    @Published private(set) var spotIds: Set<String> = []

    private let defaults: UserDefaults
    private var userId: String?
    /// 手元で押した分（同期の入れ替えで消さないため・`LocalEdits`）
    private var edits = LocalEdits()
    /// **まだサーバーに送っていない鍵**（ログイン中の人の分だけ・端末に残す）。
    ///
    /// 🔴 **nil は「この人ではまだ一度も同期していない」。** 空（送るものが無い）と
    /// 分ける。この仕組みより前に端末だけに入れた「行きたい」は、ここが nil の
    /// 人の控えに残っている——最初の同期でサーバーに無い分を**全部**送る
    /// （送らずにサーバーの一覧で入れ替えると、端末にしか無かった場所が消える）。
    /// 2回目からは入れ替える（Web で外した場所を端末の控えで生き返らせない）。
    ///
    /// ここに入るのは、未ログインの間に押して引き継いだ分・最初の同期で見つけた分・
    /// 送れない形の鍵（`SavedSpotService.canSend`）。ログイン中に押した分は
    /// その場で送る（`WishlistSync`）ので入れない
    private var unsent: Set<String>?
    /// いま送っている鍵（連打で足す・外すが並んで飛ばないように）
    private var sending: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let sharedKey = "journey-photo-wishlist"
    /// **別の鍵に置く**（中身の一覧と混ぜると、旧版のアプリが読んだときに鍵が増えて見える）
    private static let unsentKey = "journey-photo-wishlist-unsent"

    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return Self.sharedKey }
        return "\(Self.sharedKey):\(userId)"
    }

    private func unsentKey(for userId: String) -> String {
        "\(Self.unsentKey):\(userId)"
    }

    private var signedInUser: String? {
        guard let userId, !userId.isEmpty else { return nil }
        return userId
    }

    private func saveUnsent() {
        guard let user = signedInUser else { return }
        if let unsent {
            defaults.set(Array(unsent), forKey: unsentKey(for: user))
        } else {
            defaults.removeObject(forKey: unsentKey(for: user))
        }
    }

    /// 使う人を切り替える。
    ///
    /// 🔴 **ログインしていない間に押したぶんは、ログインした人へ引き継ぐ。**
    /// 未ログインの印は共有の鍵（`sharedKey`）に入るので、以前はログインした瞬間に
    /// その人の鍵へ切り替わるだけで、**押したばかりの「行きたい」が消えて見えた**。
    /// 未ログイン→ログインの回だけ、共有の鍵のぶんをその人の鍵へ足して共有の鍵を消す
    /// （消さないと、次にログインした別の人にも同じぶんが入る）。
    ///
    /// 🔴 **ログイン中の人から別の人へ替わる回は混ぜない**（`FavoritesStore` と同じ
    /// 理由——同じ端末で人が変わったときに前の人の印を吸い込まない）
    ///
    /// 🔴 **引き継いだ分は「未送信」に入れる。** 入れないと、次の同期の入れ替えで
    /// サーバーの一覧に負けて消える（ログインした瞬間は見えて、少し後に消える）
    func use(userId: String?) {
        let wasSignedOut = self.userId?.isEmpty ?? true
        self.userId = userId
        edits.reset(owner: userId)
        var ids = Set(defaults.stringArray(forKey: key(for: userId)) ?? [])
        if let user = signedInUser {
            unsent = defaults.stringArray(forKey: unsentKey(for: user)).map(Set.init)
        } else {
            unsent = nil
        }
        if wasSignedOut, signedInUser != nil {
            let anonymous = Set(defaults.stringArray(forKey: Self.sharedKey) ?? [])
            if !anonymous.isEmpty {
                ids.formUnion(anonymous)
                defaults.set(Array(ids), forKey: key(for: userId))
                defaults.removeObject(forKey: Self.sharedKey)
                // nil（まだ同期していない）なら、最初の同期が控えを丸ごと見るので足さない
                if unsent != nil {
                    unsent?.formUnion(anonymous)
                    saveUnsent()
                }
            }
        }
        spotIds = ids
    }

    /// いまの控えの持ち主。**送る前に取り、戻すときに `set(_:wanted:for:)` に渡す**
    var owner: String? { userId }

    /// 同期で一覧を取りに行く**前に**取る。`replace(with:for:since:)` に渡す
    var syncMark: LocalEdits.Mark { edits.mark }

    func contains(_ spotId: String) -> Bool { spotIds.contains(spotId) }

    /// 押すたびに入れ替える。**押した後の状態**を返す。**控えだけ**を変える——
    /// 画面は `WishlistSync.toggle`（ログイン中はサーバーへ送る）を呼ぶ
    ///
    /// 🔴 **空の鍵は何もせず false。** `set` は空の鍵を捨てるのに、ここが
    /// 「入った」と返していたので、画面は「追加しました」と知らせて何も残らなかった
    @discardableResult
    func toggle(_ spotId: String) -> Bool {
        guard !spotId.isEmpty else { return false }
        let wanted = !contains(spotId)
        set(spotId, wanted: wanted)
        return wanted
    }

    /// 手元の控えだけを変える。**サーバーへ送るのは `WishlistSync`**（画面はあちらを呼ぶ）
    func set(_ spotId: String, wanted: Bool) {
        guard !spotId.isEmpty else { return }
        if wanted {
            spotIds.insert(spotId)
        } else {
            spotIds.remove(spotId)
        }
        edits.note(spotId, on: wanted)
        defaults.set(Array(spotIds), forKey: key(for: userId))
        guard signedInUser != nil else { return }
        if !wanted {
            // 🔴 **外したものを後から送らない**（未送信のまま外した場所が、次の同期で生き返る）
            if unsent?.remove(spotId) != nil { saveUnsent() }
        } else if !SavedSpotService.canSend(spotId), unsent != nil {
            // 送れない形は端末にだけ残す（次の同期の入れ替えで消さない）
            unsent?.insert(spotId)
            saveUnsent()
        }
    }

    /// 答えを待った後に書く（失敗の巻き戻し）。**待っている間に人が替わっていたら書かない**
    /// （`SavedPhotosStore.set(_:saved:for:)` と同じ理由）
    func set(_ spotId: String, wanted: Bool, for owner: String?) {
        guard owner == userId else { return }
        set(spotId, wanted: wanted)
    }

    /// 送っている最中か（`WishlistSync` が連打を止めるのに使う）
    func isSending(_ spotId: String) -> Bool { sending.contains(spotId) }
    func beginSending(_ spotId: String) { sending.insert(spotId) }
    func endSending(_ spotId: String) { sending.remove(spotId) }

    /// まだ送っていない鍵か（送る直前に見る——**待っている間に外した分を送らない**）
    func isUnsent(_ spotId: String, for owner: String?) -> Bool {
        owner == userId && spotIds.contains(spotId) && (unsent?.contains(spotId) ?? false)
    }

    /// 送れた。未送信から外す（人が替わっていたら何もしない）
    func markSent(_ spotId: String, for owner: String?) {
        guard owner == userId, unsent?.remove(spotId) != nil else { return }
        saveUnsent()
    }

    /// サーバーの一覧に合わせる。**取れた回だけ呼ぶこと**
    /// ——取れなかった回に空で上書きすると、控えごと消える
    ///
    /// 手順は `SavedPhotosStore.replace(with:for:since:)` と同じ（持ち主と印の照合・
    /// 印の後に押した分を重ねる）。違うのは**まだ送っていない分を残す**ところ:
    ///
    ///  - 最初の同期（`unsent` が nil）では、控えのうちサーバーに無いものを全部
    ///  - 2回目からは、引き継いだ・送り損ねた・送れない形の分だけ
    ///
    /// を控えに残して**未送信**にする。返すのは、その中で送れる鍵（`WishlistSync` が送る）。
    /// **待っている間に外したものは含めない**（控えに無いものは未送信にしない）
    ///
    /// - Parameters:
    ///   - owner: 取りに行ったときの人。**返ってくる間に人が替わっていたら書かない**
    ///   - mark: 取りに行く前の `syncMark`。**その後に押した分は残す**。別の人の印なら書かない
    @discardableResult
    func replace(with slugs: [String], for owner: String?, since mark: LocalEdits.Mark? = nil) -> [String] {
        guard owner == userId, signedInUser != nil else { return [] }
        let server = Set(slugs)
        var next = server
        if let mark {
            guard let merged = edits.merged(next, since: mark) else { return [] }
            next = merged
        }
        let candidates = (unsent ?? spotIds).intersection(spotIds)
        let missing = candidates.subtracting(server)
        next.formUnion(missing)
        spotIds = next
        unsent = missing
        defaults.set(Array(spotIds), forKey: key(for: userId))
        saveUnsent()
        return missing.filter(SavedSpotService.canSend).sorted()
    }

    /// 退会した人の控えを消す（`AccountLocalData`）。**未送信の印も**
    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
        defaults.removeObject(forKey: unsentKey(for: userId))
    }
}
