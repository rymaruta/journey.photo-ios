import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

@MainActor
final class PhotoDetailViewModel: ObservableObject {

    /// いいね数。**分からない間は nil**（一覧に数が無く、読み込みも取れていない）。
    /// 0 は「まだ誰も押していない」と読まれるので、分からない回に出すと嘘になる
    @Published private(set) var likes: Int?
    /// **直前に押した回に**サーバーが答えた数。答えが無かった回は nil。
    /// ホームへ渡すのはこれだけ（`LikeCountStore`——開いたときに読んだ数は渡さない）
    @Published private(set) var lastLikeAnswer: Int?
    @Published private(set) var liked = false
    @Published private(set) var comments: [PhotoComment] = []
    /// コメントの総数。**サーバーから取れたときだけ入る**（取れなければ nil）。
    ///
    /// 以前は `Int = 0` で、読み込み前も圏外も「0」と描いていた。
    /// 0 は「まだ無い」と読まれるので、分からない回に出すと嘘になる。
    @Published private(set) var commentCount: Int?
    /// 直近の読み込みでコメントが引けなかった。
    /// **「まだ無い」と「取れなかった」を画面で分ける**ためのもの
    @Published private(set) var commentsUnavailable = false
    /// 「もう一度試す」でコメントを読み直している間（二度押しで2本投げない）
    ///
    /// **どの1枚を読み直しているかで持つ。** 画面で1つの印にしていると、前の1枚の
    /// 読み直し（圏外で長く待つ）の間、隣へ送った1枚の送信・削除・再試行まで押せなかった
    /// 1つの枠にすると、別の1枚の読み直しで上書きされて守りが外れる（集合で持つ）
    var isReloadingComments: Bool { reloadingComments.contains(photoId) }
    @Published private(set) var reloadingComments: Set<String> = []
    @Published var draftComment = ""
    @Published var errorMessage: String?
    @Published private(set) var isPosting = false
    /// 消している途中のコメント（二度押しで2回送ると、2回目が「見つかりません」を出す）
    @Published private(set) var deletingCommentIds: Set<String> = []
    /// この画面で書いた・消したコメント。**読み込んだ一覧に重ねて採る**
    /// ——投稿の前に読んだ一覧が後から届いて、書いたばかりのコメントが消えたり、
    /// 消したコメントが戻ったりしていた（`CommentMerge`）
    /// **写真ごとに持つ。** 束の隣へ送る（`show`）ので、1本にすると p1 で書いた
    /// コメントが p2 の一覧に「未反映の自分の投稿」として差し込まれていた
    private var postedComments: [String: [PhotoComment]] = [:]
    private var deletedCommentIds: Set<String> = []
    /// いいねを送っている最中。**二度押しで2回投げない。**
    ///
    /// コメントには `isPosting` があったのに、いいねには何も無かった。
    /// 素早く2回叩くと、1回目の応答が返る前に2回目が `liked` の古い値を
    /// 見て走り、**「いいね」と「取り消し」が同時に飛ぶ**。どちらが後に
    /// 返るかで最終的なハートの色が決まるので、押した結果と食い違う。
    @Published private(set) var isLiking = false
    /// 写真ごとの、押したいいねが**受け付けられた**回数。**読み込みの間にその写真で
    /// 増えたら、その読み込みのハートと数は書かない**——開いた
    /// 直後に押すと、先に出ていた読み込みの（押す前の）答えが後から届き、押した
    /// ハートと数を戻していた。写真ごとに持つのは、束の隣へ送った後に前の1枚の
    /// 答えが届いても、今の1枚の読み込みを捨てないため。断られた回は数えない
    /// （サーバーは変わっていないので、読み込みの答えが正しい）
    private var acceptedLikes: [String: Int] = [:]
    /// 今の1枚の数を**サーバーから**得たか（読み込み・押した答え）。
    /// 得るまでは `show` が渡す数（ホームのカードと同じ出どころ・`LiveLikes.base`）で
    /// 入れ直す——init の時点では `LikeCountStore` を読めず、一覧の古い数で始まるため
    private var likesFromServer = false
    /// 今の1枚に**押した回の答え**が届いた時刻（ホームで押した `LikeCountStore` の
    /// 答え・この画面で押した答え）。そこから `LiveLikes.serverStaleness` の間に
    /// 読んだ数と印は、押す前の古い答えでありうるので書かない（`LiveLikes.readSupersedes`）
    private var likeAnsweredAt: Date?
    /// 投稿者の公開プロフィール。**@ユーザー名を出すため**（写真の行は
    /// 表示名しか持っていない）。取れなければ nil——名前だけ出す
    @Published private(set) var owner: UserProfile?

    /// いま画面の上に出ている1枚。**束を左右に送ると替わる**（`show`）
    private(set) var photoId: String
    private let social: SocialService

    /// **画面ができてから入る。** `@StateObject` の初期化時には
    /// `EnvironmentObject`（＝ログイン状態）をまだ読めないので、
    /// `.task` で渡してもらう。init で `false` に固定すると
    /// 「ログインしているのに、いいねが押せない」になる。
    private var isSignedIn = false

    /// - Parameter initialLikes: 一覧から来た写真の数。**読み込みが終わるまで 0 と出さない**
    ///   （圏外で取れなかった回も、一覧の数を出し続ける）
    init(photoId: String, social: SocialService, initialLikes: Int? = nil) {
        self.photoId = photoId
        self.social = social
        self.likes = initialLikes
    }

    func setSignedIn(_ value: Bool) {
        isSignedIn = value
    }

    /// 束の別の1枚へ送った。**数・ハート・コメントをその1枚のものに入れ替える。**
    ///
    /// 🔴 送っても開いた1枚のままだったので、2枚目を見ながら押したいいねや
    /// コメントが1枚目に付いていた。書きかけのコメントも前の1枚のものなので消す
    ///
    /// - Parameter liked: 端末の控え（`FavoritesStore`）が言う「押してある」。
    ///   **読めるまではこれを出す**——白で始めると、圏外で開いたいいね済みの写真が
    ///   白いハートになり、押すと「いいね」を送って（届かず）控えまで消していた
    ///   - answeredAt: 押した回の答えの時刻（`LikeCountStore.Entry.at`）。無ければ nil
    func show(photoId: String, initialLikes: Int?, liked: Bool, answeredAt: Date? = nil) {
        if photoId != self.photoId {
            self.photoId = photoId
            likes = initialLikes
            likesFromServer = false
            likeAnsweredAt = answeredAt
            lastLikeAnswer = nil
            comments = []
            commentCount = nil
            commentsUnavailable = false
            draftComment = ""
            errorMessage = nil
        } else if !likesFromServer, let initialLikes {
            // 🔴 **開いた1枚でも、サーバーの数を得るまでは渡された数に合わせる。**
            // ホームで♥を押して 5→6 になっても、init は一覧の 5 で始まるので、
            // 開いた直後は 5 と出ていた
            likes = initialLikes
        }
        if photoId == self.photoId, let answeredAt,
           likeAnsweredAt.map({ answeredAt > $0 }) ?? true {
            likeAnsweredAt = answeredAt
        }
        self.liked = liked
    }

    /// いいね数とコメントは未認証でも読める。自分が押しているかだけ要ログイン。
    /// 投稿者を読む。**写真の主が分かっているときだけ**
    func loadOwner(_ userId: String?, profiles: ProfileService) async {
        guard let userId, !userId.isEmpty, owner == nil else { return }
        owner = try? await profiles.publicProfile(userId: userId)
    }

    func load() async {
        let id = photoId
        let accepted = acceptedLikes[id, default: 0]
        let readAt = Date()
        async let count = try? social.likeCount(photoId: id)
        async let page = try? social.comments(photoId: id)
        let mine: Bool?
        if isSignedIn {
            mine = try? await social.myLike(photoId: id)
        } else {
            mine = nil
        }
        let loadedCount = await count
        let loaded = await page
        // **読んでいる間に別の1枚へ送ったら捨てる**（前の1枚の数を今の1枚に出さない）
        guard id == photoId else { return }
        // 🔴 **押した答えから間もない読みは、数も印も書かない。** ホームで押して 6 に
        // なった直後に開くと、読み取りは押す前の 5（外したなら押す前の「いいね済み」）を
        // 返すことがあり、出ていた 6 を 5 に戻していた（`LiveLikes.readSupersedes`）
        let likeUntouched = accepted == acceptedLikes[id, default: 0]
            && LiveLikes.readSupersedes(readAt: readAt, answeredAt: likeAnsweredAt)
        if likeUntouched {
            likes = loadedCount ?? likes
            if loadedCount != nil { likesFromServer = true }
        }
        if let loaded { applyComments(loaded, for: id) }
        commentsUnavailable = loaded == nil
        // **引けなかった回に「押していない」と言わない。** 電波が悪いだけで
        // ハートが白に戻ると、押した人は「取り消された」と読む
        // （押し直しても数は増えない＝サーバーは冪等なので、実害は
        //  見え方だけ——だがその見え方がいちばん不安にさせる）
        guard likeUntouched else { return }
        if let mine {
            liked = mine
        } else if !isSignedIn {
            liked = false
        }
    }

    /// コメントだけを読み直す（読み込めなかった回の「もう一度試す」）。
    ///
    /// **`load()` を使い回さない。** あちらはいいねの数と自分のいいねも引き直すので、
    /// いいねを送っている最中に押すと、古い答えが後から着いてハートが戻りうる
    ///
    /// **投稿している間は読み直さない**（逆も）。あとから着いた古いページが、
    /// 先頭に入れた自分のコメントを上書きして消す
    func reloadComments() async {
        guard !isReloadingComments, !isPosting else { return }
        let id = photoId
        reloadingComments.insert(id)
        defer { reloadingComments.remove(id) }
        let page = try? await social.comments(photoId: id)
        // 読んでいる間に別の1枚へ送ったら捨てる（前の1枚のコメントを今の1枚に出さない）
        guard id == photoId else { return }
        if let page { applyComments(page, for: id) }
        commentsUnavailable = page == nil
    }

    /// 読めたコメントのページを移す。**この画面で書いた・消したコメントを重ねる**
    /// （`load()` と `reloadComments()` で同じ——片方だけだと、読み直しで
    /// 書いたばかりのコメントが消えたり、消したコメントが戻ったりする）
    private func applyComments(_ loaded: SocialService.CommentPage, for id: String) {
        // **一覧に載った投稿は、以後サーバーを信じる**（持ち主が消した・
        // 別の端末で消したコメントを、手元の控えから復活させない）
        let seen = Set(loaded.items.map(\.id))
        postedComments[id]?.removeAll { seen.contains($0.id) }
        let merged = CommentMerge.merge(loaded: loaded.items, count: loaded.count,
                                        posted: postedComments[id] ?? [], deleted: deletedCommentIds)
        comments = merged.items
        commentCount = merged.count
    }

    /// **数は自分で足さない。** サーバーが押したあとの数を返すので、
    /// それを使う（二重に押した回や既に押していた回でずれる）。
    ///
    /// - Returns: サーバーの答え（**押した1枚の id 付き**）。届かなかった回は nil。
    ///   答えた回だけ呼び出し側は端末の控えを合わせる——送っている間に束の隣へ
    ///   送っても、押した1枚の控えには書く（書かないとサーバーには入ったのに
    ///   ホームも「いいねした写真」も白いままになる）
    struct LikeAnswer: Equatable {
        let photoId: String
        let liked: Bool
        let likes: Int?
    }

    /// - Parameter gate: 画面をまたいだ送信中の印（`LikeCountStore.beginSending`）。
    ///   **ホームや大きく見る画面で同じ写真を送っている間は送らない**——この画面の
    ///   `isLiking` だけでは、別の画面から飛んでいる逆向きを止められない
    @discardableResult
    func toggleLike(gate: LikeCountStore? = nil) async -> LikeAnswer? {
        // **どの guard より先に消す。** 未ログインで押した回に前の答えが残ると、
        // 呼び出し側がそれを「いま」の答えとしてホームへ渡し直す
        lastLikeAnswer = nil
        guard isSignedIn else {
            errorMessage = L("いいねするにはログインしてください", "Sign in to like photos")
            return nil
        }
        guard !isLiking else { return nil }
        let id = photoId
        // 別の画面で同じ写真を送っている間は、押しても何もしない（知らせも消さない）
        if let gate, !gate.beginSending(id) { return nil }
        defer { gate?.endSending(id) }
        // 前の操作の失敗を残さない（送っている間の二度押しでは消さない）
        errorMessage = nil
        isLiking = true
        defer { isLiking = false }
        let wasLiked = liked
        do {
            let result = wasLiked
                ? try await social.unlike(photoId: id)
                : try await social.like(photoId: id)
            let answer = LikeAnswer(photoId: id, liked: result.liked, likes: result.likes)
            acceptedLikes[id, default: 0] += 1
            // 送っている間に別の1枚へ送ったら、答えは前の1枚のもの——今の1枚の
            // 画面には書かない（控えへは呼び出し側が押した1枚に書く）
            guard id == photoId else { return answer }
            liked = result.liked
            if let likes = result.likes {
                self.likes = likes
                lastLikeAnswer = likes
                likesFromServer = true
            }
            likeAnsweredAt = Date()
            return answer
        } catch {
            // 前の1枚の失敗を、送った先の1枚の画面に出さない
            if id == photoId {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("うまくいきませんでした", "That didn't work")
            }
            return nil
        }
    }

    func postComment() async {
        // 二度押しで同じ文を2件送らない（ボタンが押せなくなるのは描き直しの後）。
        // 先頭で断る——下で知らせを消す前に（二度目の押下で別の失敗の知らせを消さない）
        guard !isPosting else { return }
        let text = draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = nil
        guard isSignedIn else {
            errorMessage = L("コメントするにはログインしてください", "Sign in to comment")
            return
        }
        // 読み直しの答えで、入れた自分のコメントが上書きされない（`reloadComments`）
        guard !isReloadingComments else { return }
        isPosting = true
        defer { isPosting = false }
        let id = photoId
        do {
            let comment = try await social.postComment(photoId: id, text: text)
            // 送った先の1枚に控える（隣へ送った後に届いても、戻ったときに出す）
            postedComments[id, default: []].append(comment)
            // 消したときの 404 の読み方を分けるため、投稿した時刻を控える（`deleteComment`）
            postedAt[comment.id] = now()
            guard id == photoId else { return }
            // **送っている間に読み直した一覧に、もう載っていることがある。**
            // そのときは足さない（同じコメントが2つ・数が1つ多く出ていた）
            if !comments.contains(where: { $0.id == comment.id }) {
                comments.insert(comment, at: 0)
                // **総数が分からない回は分からないまま。** 取れていない数に
                // +1 しても本当の数にならない（一覧には載るので、数だけ無い）
                commentCount = commentCount.map { $0 + 1 }
            }
            // **送った文のときだけ空にする。** 送っている間も欄は打てるので、
            // 続きを書いていたら丸ごと消えていた
            if draftComment.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                draftComment = ""
            }
        } catch {
            // **送った先の1枚でも失敗は出す。** 書きかけは送ったときに `show` が
            // 消しているので、黙ると「入った」と思われたまま文も残らない
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("コメントできませんでした", "Couldn't post the comment")
        }
    }

    /// この画面で投稿したコメントと、その時刻。**消したときの 404 の読み方を分ける**（`deleteComment`）
    private var postedAt: [String: Date] = [:]
    /// 投稿の直後とみなす長さ。サーバーの結果整合の読みが追いつくのは普通1秒以内なので、
    /// これを過ぎた 404 は「まだ見えない」ではなく「もう無い」（持ち主が先に消した など）
    static let justPostedWindow: TimeInterval = 10
    /// 時刻の出どころ（テストで差し替える）
    var now: () -> Date = Date.init

    /// 投稿の直後で、404 が「まだ見えない」だけかもしれないか
    private func isJustPosted(_ id: String) -> Bool {
        guard let at = postedAt[id] else { return false }
        return now().timeIntervalSince(at) < Self.justPostedWindow
    }

    /// コメントを消す。
    ///
    /// **404（もう無い）は消せたのと同じ**——別の端末や写真の持ち主が先に消した回。
    /// 失敗と読むと、もう無いコメントが残り、押すたびにエラーになる。
    /// ただし**この画面で投稿したばかり（`justPostedWindow` 以内）のコメントは除く**: サーバーの最初の読みは
    /// 結果整合なので、投稿の直後は「まだ見えない」だけで 404 が返る（サーバーには残る）。
    /// そこで外すと、他の人には見えたまま自分の画面からだけ消える
    func deleteComment(_ comment: PhotoComment) async {
        // 読み直している間は消さない（あとから着いた古いページで、消したコメントが戻る）。
        // 画面も削除を押せなくしている
        guard !isReloadingComments else { return }
        guard !deletingCommentIds.contains(comment.id) else { return }
        deletingCommentIds.insert(comment.id)
        defer { deletingCommentIds.remove(comment.id) }
        errorMessage = nil
        // **送った先の1枚を控える。** 束を送っている間に消し終わると、
        // 次の1枚のコメントから同じ ID を探して消していた
        let id = photoId
        do {
            try await social.deleteComment(photoId: id, commentId: comment.id)
            // 消えたことは束を送った後でも覚えておく（戻ってきたときに出さない）
            deletedCommentIds.insert(comment.id)
            guard id == photoId else { return }
            comments.removeAll { $0.id == comment.id }
            commentCount = commentCount.map { max(0, $0 - 1) }
        } catch where SocialService.isNotFound(error) && !isJustPosted(comment.id) {
            // もう無い: 消せたのと同じ（束を送った後でも、戻ったときに出さない）
            deletedCommentIds.insert(comment.id)
            guard id == photoId else { return }
            comments.removeAll { $0.id == comment.id }
            commentCount = commentCount.map { max(0, $0 - 1) }
        } catch where SocialService.isNotFound(error) {
            guard id == photoId else { return }
            // 投稿の直後でサーバーにまだ見えていない（「見つかりません」と言わない）
            errorMessage = L("まだ反映されていないため削除できませんでした。少し待ってからもう一度お試しください",
                             "Couldn't delete it yet. Please wait a moment and try again.")
        } catch {
            guard id == photoId else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }
}
