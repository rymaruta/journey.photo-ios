import Foundation
// `ObservableObject` と `@Published` は Combine のもの（`FavoritesStore` と同じ）
import Combine

/// サーバーが**いま答えた**いいねの数。画面をまたいで共有する。
///
/// 一覧の数（`Photo.likes`）は一覧を読んだ時点の数で、ホームは画面に
/// 戻っても読み直さない。だから**詳細画面でいいねして戻ると、ハートは
/// 灯っているのに数は押す前のまま**になっていた。サーバーが答えた数を
/// ここに置き、ホームのカードと検索の格子は**これを先に見る**。
///
/// 入れるのは、サーバーの答え（押した回の `likes`・詳細画面で読んだ数）だけ。
/// 端末で数えた数は入れない。**誰の数でもない公開の数**なので、
/// ログインし直しても捨てない。
///
/// ⚠️ **アプリを閉じるまで残る。** 答えた後に他の人が押したぶんは、
/// その写真を詳細で開き直すか、アプリを開き直すまで出ない
/// （以前のカードの `serverLikes` と同じ割り切り）。
@MainActor
final class LikeCountStore: ObservableObject {

    @Published private(set) var counts: [String: Int] = [:]

    func set(_ photoId: String, count: Int) {
        let value = max(0, count)
        guard counts[photoId] != value else { return }
        counts[photoId] = value
    }

    func count(for photoId: String) -> Int? {
        counts[photoId]
    }
}
