import Foundation

/// 保存した写真（`SavedPhotosView`）・いいねした写真（`FavoritesView`）の画面が持つ
/// 引き当ての材料と、**読み込みの答えをいつ入れるか**の決まり（H-2・2026-10-07 判断）。
///
/// 自分の写真（`mine`）は `.task(id:)` と引き下げでしか読んでいなかったので、
/// 自分の写真を消して戻っても一覧に残った。**戻るたびに読み直す**（`appear`）。
/// 前回の直し（4a0bb0b）は読み直しを足しただけで、2つの回帰を出した:
///
/// 1. 圏外で戻ると、サーバーのいいね一覧が取れず、**ほかの端末でいいねした写真が
///    一覧から消えた**。→ 取れなかった回は、**同じ人なら前の一覧を残す**
///    （人が替わったら残さない——前の人のいいねを次の人に見せない）
/// 2. 読み直しの途中に詳細を開くと、答えが届いた瞬間に一覧が差し替わり、
///    **押した元が消えて詳細が閉じた**。→ 答えは**画面に出ている間だけ入れる**。
///    出ていない間に届いた答えは取っておき、戻ったとき（`appear`）に入れる
///    （`HomeTopCardView` の `pendingQuiz` と同じ形）
///
/// 2つの画面で同じ決まりを使う（保存した写真はサーバーのいいね一覧を持たないだけ）。
/// 画面を持たない値にしてあるのは、Linux のテストで確かめるため。
struct LikedPhotosScreen {

    /// 1回の読み込みの答え
    struct Fetch {
        /// 読み始めたときの人（未ログインは nil）
        var user: String?
        /// 公開一覧。取れなければ nil
        var feed: [Photo]?
        /// 自分の写真。未ログイン・取れなければ nil
        var mine: [Photo]?
        /// サーバーのいいね一覧（`FavoritesView` だけ）。聞かなかった・取れなければ nil
        var serverIds: [String]? = nil
        /// サーバーのいいね一覧を聞いて、取れなかった（取り消しは含めない）
        var serverFailed = false
    }

    /// 引き当ての材料（画面に入れたもの）
    struct Materials {
        var feed: [Photo] = []
        var mine: [Photo] = []
        /// サーバーのいいね一覧。控えは書き換えず、絞るときに和を取る（`FavoritesStore.listedIds`）
        var serverIds: [String]?
        /// `mine`・`serverIds` が誰のものか
        var owner: String?
        /// 引き当て先を一度でも読み終えたか（「まだ」と「0件」を混ぜない）
        var loaded = false
        /// 最後の読み込みで引き当て先が取れなかったか（「読み込めませんでした」はこの回だけ）
        var poolsFailed = false
        /// サーバーのいいね一覧が取れず、**端末の控えだけ**で出している
        var partial = false

        func absorbing(_ fetch: Fetch) -> Materials {
            var next = self
            let signedIn = fetch.user != nil
            // 前の人のぶんを残してよいのは、同じ人のときだけ
            let sameOwner = loaded && owner == fetch.user
            // 公開一覧は人によらない。取れなかった回は前のまま
            next.feed = fetch.feed ?? feed
            // ログアウトしたら前の人の写真を残さない
            next.mine = signedIn ? (fetch.mine ?? (sameOwner ? mine : [])) : []
            // 🔴 **取れなかった回は、同じ人なら前の一覧を残す**（回帰1）。
            // 消すと、圏外で戻っただけでほかの端末のいいねが一覧から消える。
            // 人が替わった直後に取れなかった回は残さない（前の人のいいねが見える）
            next.serverIds = signedIn ? (fetch.serverIds ?? (sameOwner ? serverIds : nil)) : nil
            // 前の一覧を残せた回は「端末のぶんだけ」とは言わない（事実と違う）
            next.partial = fetch.serverFailed && next.serverIds == nil
            next.poolsFailed = fetch.feed == nil || (signedIn && fetch.mine == nil)
            next.owner = fetch.user
            next.loaded = true
            return next
        }

        /// ID を写真に引き当てる（`LikedPhotos.resolve`）。`visible` はブロック・通報・
        /// 消した印で公開一覧を絞るもの（`ModerationStore.visible`）
        func resolve(_ ids: Set<String>, visible: ([Photo]) -> [Photo]) -> [Photo] {
            LikedPhotos.resolve(ids, in: [visible(feed), mine])
        }
    }

    /// 画面に入れた材料
    private(set) var shown = Materials()
    /// 画面に出ていない間に届いた答え（戻ったときに入れる）
    private(set) var staged: Materials?
    /// 画面がいま出ているか（`onAppear`〜`onDisappear`）
    private(set) var isShown = false
    /// 戻ってきた回数。読み込みの `.task(id:)` の鍵に入れる——`onAppear` で別の
    /// `Task` を立てると、`.task` と2本同時に取りに行く（`HomeTopCardView` と同じ形）
    private(set) var returns = 0
    private var didAppear = false
    /// 読み終えた鍵（`key(auth:)`）。**同じ鍵での再実行は空振りさせる**（`needsLoad`）。
    /// 戻ったとき SwiftUI が `.task` を元の鍵で走り直す場合でも、`appear` で鍵が進むので、
    /// 読み込みは新しい鍵の1本だけになる（`HomeTopCardView` の `loadedKey` と同じ形・
    /// 走り直す・走り直さないのどちらでも1本。2026-10-07 判断）
    private(set) var loadedKey: String?

    /// 読み込みの `.task(id:)` の鍵（ログインの状態と、戻ってきた回数）
    func key(auth: String) -> String { "\(auth)#\(returns)" }

    /// この鍵で読む必要があるか（読み終えた鍵なら空振り）。引き下げ・再試行は聞かずに読む
    func needsLoad(_ key: String) -> Bool { key != loadedKey }

    /// 読み込みの答えが届いた。**画面に出ていればその場で入れて true**（絞り直す）。
    /// 出ていなければ取っておく（詳細を開いている——差し替えると詳細が閉じる）
    /// - Parameter key: 読み始めたときの鍵。届いた（取り消されなかった）回だけ「読み終えた」と覚える
    mutating func receive(_ fetch: Fetch, key: String? = nil) -> Bool {
        if let key { loadedKey = key }
        // 取っておいた答えの上に重ねる（前の答えで取れた一覧を、後の失敗で消さない）
        let next = (staged ?? shown).absorbing(fetch)
        if isShown {
            shown = next
            staged = nil
            return true
        }
        staged = next
        return false
    }

    /// 画面が前に出た。取っておいた答えを入れ、**戻ってきた回なら読み直す**
    /// （`returns` が進む＝`.task(id:)` が走る）。初回は `.task(id:)` がもう読んでいる
    ///
    /// ⚠️ 戻るスワイプを途中でやめた回（`onAppear` が来て、出ないまま詳細に戻る）にも
    /// 取っておいた答えが入る。**確かめていない・前からの `refilter` と同じ穴**（2026-10-07 判断）
    mutating func appear() {
        isShown = true
        if let staged {
            shown = staged
            self.staged = nil
        }
        if didAppear { returns &+= 1 }
        didAppear = true
    }

    mutating func disappear() {
        isShown = false
    }
}
