import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

@MainActor
final class PhotoDetailViewModel: ObservableObject {

    @Published private(set) var likes: Int = 0
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
    @Published var draftComment = ""
    @Published var errorMessage: String?
    @Published private(set) var isPosting = false
    /// 消している途中のコメント（二度押しで2回送ると、2回目が「見つかりません」を出す）
    @Published private(set) var deletingCommentIds: Set<String> = []
    /// この画面で書いた・消したコメント。**読み込んだ一覧に重ねて採る**
    /// ——投稿の前に読んだ一覧が後から届いて、書いたばかりのコメントが消えたり、
    /// 消したコメントが戻ったりしていた（`CommentMerge`）
    private var postedComments: [PhotoComment] = []
    private var deletedCommentIds: Set<String> = []
    /// いいねを送っている最中。**二度押しで2回投げない。**
    ///
    /// コメントには `isPosting` があったのに、いいねには何も無かった。
    /// 素早く2回叩くと、1回目の応答が返る前に2回目が `liked` の古い値を
    /// 見て走り、**「いいね」と「取り消し」が同時に飛ぶ**。どちらが後に
    /// 返るかで最終的なハートの色が決まるので、押した結果と食い違う。
    @Published private(set) var isLiking = false
    /// いいねを送り始めた・答えを受け取った回数。**読み込みの間に動いたら、
    /// その読み込みの数とハートは書かない**——開いた直後に押すと、先に出ていた
    /// 読み込みの（押す前の）答えが後から届き、押したハートと数を戻していた
    private var likeWrites = 0
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
        self.likes = initialLikes ?? 0
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
    func show(photoId: String, initialLikes: Int?, liked: Bool) {
        if photoId != self.photoId {
            self.photoId = photoId
            likes = initialLikes ?? 0
            lastLikeAnswer = nil
            comments = []
            commentCount = nil
            commentsUnavailable = false
            draftComment = ""
            errorMessage = nil
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
        let writes = likeWrites
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
        let likeUntouched = writes == likeWrites
        if likeUntouched { likes = loadedCount ?? likes }
        if let loaded {
            // **一覧に載った投稿は、以後サーバーを信じる**（持ち主が消した・
            // 別の端末で消したコメントを、手元の控えから復活させない）
            let seen = Set(loaded.items.map(\.id))
            postedComments.removeAll { seen.contains($0.id) }
            let merged = CommentMerge.merge(loaded: loaded.items, count: loaded.count,
                                            posted: postedComments, deleted: deletedCommentIds)
            comments = merged.items
            commentCount = merged.count
        }
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

    @discardableResult
    func toggleLike() async -> LikeAnswer? {
        // **どの guard より先に消す。** 未ログインで押した回に前の答えが残ると、
        // 呼び出し側がそれを「いま」の答えとしてホームへ渡し直す
        lastLikeAnswer = nil
        guard isSignedIn else {
            errorMessage = L("いいねするにはログインしてください", "Sign in to like photos")
            return nil
        }
        guard !isLiking else { return nil }
        isLiking = true
        likeWrites += 1
        defer {
            isLiking = false
            likeWrites += 1
        }
        let wasLiked = liked
        let id = photoId
        do {
            let result = wasLiked
                ? try await social.unlike(photoId: id)
                : try await social.like(photoId: id)
            let answer = LikeAnswer(photoId: id, liked: result.liked, likes: result.likes)
            // 送っている間に別の1枚へ送ったら、答えは前の1枚のもの——今の1枚の
            // 画面には書かない（控えへは呼び出し側が押した1枚に書く）
            guard id == photoId else { return answer }
            liked = result.liked
            if let likes = result.likes {
                self.likes = likes
                lastLikeAnswer = likes
            }
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
        let text = draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard isSignedIn else {
            errorMessage = L("コメントするにはログインしてください", "Sign in to comment")
            return
        }
        isPosting = true
        defer { isPosting = false }
        let id = photoId
        do {
            let comment = try await social.postComment(photoId: id, text: text)
            guard id == photoId else { return }
            comments.insert(comment, at: 0)
            // **総数が分からない回は分からないまま。** 取れていない数に
            // +1 しても本当の数にならない（一覧には載るので、数だけ無い）
            commentCount = commentCount.map { $0 + 1 }
            postedComments.append(comment)
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

    func deleteComment(_ comment: PhotoComment) async {
        guard !deletingCommentIds.contains(comment.id) else { return }
        deletingCommentIds.insert(comment.id)
        defer { deletingCommentIds.remove(comment.id) }
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
        } catch {
            guard id == photoId else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }
}
