import Foundation

@MainActor
final class PhotoDetailViewModel: ObservableObject {

    @Published private(set) var likes: Int = 0
    @Published private(set) var liked = false
    @Published private(set) var comments: [PhotoComment] = []
    @Published private(set) var commentCount = 0
    @Published var draftComment = ""
    @Published var errorMessage: String?
    @Published private(set) var isPosting = false

    private let photoId: String
    private let social: SocialService

    /// **画面ができてから入る。** `@StateObject` の初期化時には
    /// `EnvironmentObject`（＝ログイン状態）をまだ読めないので、
    /// `.task` で渡してもらう。init で `false` に固定すると
    /// 「ログインしているのに、いいねが押せない」になる。
    private var isSignedIn = false

    init(photoId: String, social: SocialService) {
        self.photoId = photoId
        self.social = social
    }

    func setSignedIn(_ value: Bool) {
        isSignedIn = value
    }

    /// いいね数とコメントは未認証でも読める。自分が押しているかだけ要ログイン。
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
        liked = mine ?? false
    }

    /// **数は自分で足さない。** サーバーが押したあとの数を返すので、
    /// それを使う（二重に押した回や既に押していた回でずれる）。
    func toggleLike() async {
        guard isSignedIn else {
            errorMessage = "いいねするにはログインしてください"
            return
        }
        let wasLiked = liked
        do {
            let result = wasLiked
                ? try await social.unlike(photoId: photoId)
                : try await social.like(photoId: photoId)
            liked = result.liked
            if let likes = result.likes { self.likes = likes }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "うまくいきませんでした"
        }
    }

    func postComment() async {
        let text = draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard isSignedIn else {
            errorMessage = "コメントするにはログインしてください"
            return
        }
        isPosting = true
        defer { isPosting = false }
        do {
            let comment = try await social.postComment(photoId: photoId, text: text)
            comments.insert(comment, at: 0)
            commentCount += 1
            draftComment = ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "コメントできませんでした"
        }
    }

    func deleteComment(_ comment: PhotoComment) async {
        do {
            try await social.deleteComment(photoId: photoId, commentId: comment.id)
            comments.removeAll { $0.id == comment.id }
            commentCount = max(0, commentCount - 1)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "削除できませんでした"
        }
    }
}
