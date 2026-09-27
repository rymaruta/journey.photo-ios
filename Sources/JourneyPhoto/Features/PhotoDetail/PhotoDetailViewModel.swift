import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

@MainActor
final class PhotoDetailViewModel: ObservableObject {

    /// いいねの数。**分からないうちは nil**（描かない）。
    ///
    /// 以前は `Int = 0` で、圏外で開くと本当は数のある写真に「0」と出ていた。
    /// 最初は画面が知っている数（一覧の数／押した回の答え）を `seed` で入れ、
    /// サーバーから読めたら置き換える
    @Published private(set) var likes: Int?
    /// **直前に押した回に**サーバーが答えた数。答えが無かった回は nil。
    /// ホームへ渡すのはこれだけ（`LikeCountStore`——開いたときに読んだ数は渡さない）
    @Published private(set) var lastLikeAnswer: Int?
    /// 自分が押しているか。**最初は端末の控え（`FavoritesStore`）**を `seed` で入れる。
    ///
    /// 🔴 以前は `false` 始まりで控えを見ず、圏外で開くといいね済みの
    /// ハートが白く出た。そこで押すと「いいね」を送り、届かないと
    /// 画面側が控えを `false` で上書きして**本物のいいねが端末から消えていた**
    @Published private(set) var liked = false
    /// `liked` がサーバーの答え（読んだ・押した）か。答えを控えで上書きしない
    private var likedFromServer = false
    @Published private(set) var comments: [PhotoComment] = []
    /// コメントの総数。**サーバーから取れたときだけ入る**（取れなければ nil）。
    ///
    /// 以前は `Int = 0` で、読み込み前も圏外も「0」と描いていた。
    /// 0 は「まだ無い」と読まれるので、分からない回に出すと嘘になる。
    @Published private(set) var commentCount: Int?
    /// 直近の読み込みでコメントが引けなかった。
    /// **「まだ無い」と「取れなかった」を画面で分ける**ためのもの
    @Published private(set) var commentsUnavailable = false
    @Published var draftComment = ""
    @Published var errorMessage: String?
    @Published private(set) var isPosting = false
    /// いいねを送っている最中。**二度押しで2回投げない。**
    ///
    /// コメントには `isPosting` があったのに、いいねには何も無かった。
    /// 素早く2回叩くと、1回目の応答が返る前に2回目が `liked` の古い値を
    /// 見て走り、**「いいね」と「取り消し」が同時に飛ぶ**。どちらが後に
    /// 返るかで最終的なハートの色が決まるので、押した結果と食い違う。
    @Published private(set) var isLiking = false
    /// 投稿者の公開プロフィール。**@ユーザー名を出すため**（写真の行は
    /// 表示名しか持っていない）。取れなければ nil——名前だけ出す
    @Published private(set) var owner: UserProfile?

    private let photoId: String
    private let social: SocialService

    /// 見ている人。**画面ができてから入る。** `@StateObject` の初期化時には
    /// `EnvironmentObject`（＝ログイン状態）をまだ読めないので、
    /// `.task` で渡してもらう。init で未ログインに固定すると
    /// 「ログインしているのに、いいねが押せない」になる。
    private var viewerId: String?
    private var isSignedIn: Bool { viewerId != nil }

    init(photoId: String, social: SocialService) {
        self.photoId = photoId
        self.social = social
    }

    func setViewer(_ userId: String?) {
        // 🔴 **人が替わったら、サーバーの答えはもう今の人のものではない。**
        // 残すと次の人の控え（`seed`）が無視され、前の人のハートが灯ったまま
        // 残る（読み込みが落ちた回はずっと）。
        // **ログインの有無ではなく人で比べる**——A から B へ直接替わる回
        // （ログイン中のまま別の人）を見落とさない
        if userId != viewerId { likedFromServer = false }
        viewerId = userId
    }

    /// 画面が知っている値で埋める（端末の控え・一覧の数）。
    ///
    /// **サーバーの答えがあればそちらを残す**——控えや一覧の数は古いことがある
    func seed(liked: Bool, likes: Int?) {
        if !likedFromServer { self.liked = liked }
        if self.likes == nil { self.likes = likes }
    }

    /// いいね数とコメントは未認証でも読める。自分が押しているかだけ要ログイン。
    /// 投稿者を読む。**写真の主が分かっているときだけ**
    func loadOwner(_ userId: String?, profiles: ProfileService) async {
        guard let userId, !userId.isEmpty, owner == nil else { return }
        owner = try? await profiles.publicProfile(userId: userId)
    }

    func load() async {
        async let count = try? social.likeCount(photoId: photoId)
        async let page = try? social.comments(photoId: photoId)
        let mine: Bool?
        if isSignedIn {
            mine = try? await social.myLike(photoId: photoId)
        } else {
            mine = nil
        }
        likes = await count ?? likes
        let loaded = await page
        if let loaded {
            comments = loaded.items
            commentCount = loaded.count
        }
        commentsUnavailable = loaded == nil
        // **引けなかった回に「押していない」と言わない。** 電波が悪いだけで
        // ハートが白に戻ると、押した人は「取り消された」と読む
        // （押し直しても数は増えない＝サーバーは冪等なので、実害は
        //  見え方だけ——だがその見え方がいちばん不安にさせる）
        if let mine {
            liked = mine
            likedFromServer = true
        } else if !isSignedIn {
            liked = false
        }
    }

    /// 大きく見る画面でのダブルタップ。**いいね済みなら何もしない**
    /// （`DoubleTapLike`——解除はしない）。
    ///
    /// 画面は押した時点の見え方で「いいね」を選ぶが、送るまでの間に読み込みが
    /// 戻って押し済みに替わることがある。`toggleLike` をそのまま呼ぶと、
    /// その回はいいねを**取り消して**いた
    /// - Returns: サーバーが答えたか（`toggleLike` と同じ）
    @discardableResult
    func likeFromDoubleTap() async -> Bool {
        guard DoubleTapLike.action(isZoomed: false, alreadyLiked: liked, signedIn: isSignedIn) == .like else {
            return false
        }
        return await toggleLike()
    }

    /// **数は自分で足さない。** サーバーが押したあとの数を返すので、
    /// それを使う（二重に押した回や既に押していた回でずれる）。
    ///
    /// - Returns: サーバーが答えたか。**端末の控えに写すのは答えた回だけ**
    ///   （届かなかった回に写すと、押す前の見え方で本物のいいねを消しうる）
    @discardableResult
    func toggleLike() async -> Bool {
        // **どの guard より先に消す。** 未ログインで押した回に前の答えが残ると、
        // 呼び出し側がそれを「いま」の答えとしてホームへ渡し直す
        lastLikeAnswer = nil
        guard isSignedIn else {
            errorMessage = L("いいねするにはログインしてください", "Sign in to like photos")
            return false
        }
        guard !isLiking else { return false }
        isLiking = true
        defer { isLiking = false }
        let wasLiked = liked
        do {
            let result = wasLiked
                ? try await social.unlike(photoId: photoId)
                : try await social.like(photoId: photoId)
            liked = result.liked
            likedFromServer = true
            if let likes = result.likes {
                self.likes = likes
                lastLikeAnswer = likes
            }
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("うまくいきませんでした", "That didn't work")
            return false
        }
    }

    func postComment() async {
        let text = draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard isSignedIn else {
            errorMessage = L("コメントするにはログインしてください", "Sign in to comment")
            return
        }
        isPosting = true
        defer { isPosting = false }
        do {
            let comment = try await social.postComment(photoId: photoId, text: text)
            comments.insert(comment, at: 0)
            // **総数が分からない回は分からないまま。** 取れていない数に
            // +1 しても本当の数にならない（一覧には載るので、数だけ無い）
            commentCount = commentCount.map { $0 + 1 }
            draftComment = ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("コメントできませんでした", "Couldn't post the comment")
        }
    }

    func deleteComment(_ comment: PhotoComment) async {
        do {
            try await social.deleteComment(photoId: photoId, commentId: comment.id)
            comments.removeAll { $0.id == comment.id }
            commentCount = commentCount.map { max(0, $0 - 1) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }
}
