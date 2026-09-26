import Foundation
// `ObservableObject` と `@Published` は Combine のもの（`FavoritesStore` と同じ）
import Combine

/// **押した回に**サーバーが答えたいいねの数。画面をまたいで共有する。
///
/// 一覧の数（`Photo.likes`）は一覧を読んだ時点の数で、ホームは画面に
/// 戻っても読み直さない。だから**詳細画面でいいねして戻ると、ハートは
/// 灯っているのに数は押す前のまま**になっていた。押した答えをここに置き、
/// ホームのカードと検索の格子は**一覧の数と比べて新しい方**を出す
/// （`LiveLikes.base`）。
///
/// **入れるのは押した回の答えだけ。** 詳細画面を開いて読んだ数は入れない
/// ——読み取りは DynamoDB の「あとで揃う」読み方で、押した直後に開くと
/// 押す前の数が返ることがある。それで押した答えを上書きしないため。
/// 誰の数でもない公開の数なので、ログインし直しても捨てない。
@MainActor
final class LikeCountStore: ObservableObject {

    struct Entry: Equatable {
        let count: Int
        /// 答えを受け取った時刻。一覧の `likesAsOf` と比べる
        let at: Date
    }

    @Published private(set) var entries: [String: Entry] = [:]

    func set(_ photoId: String, count: Int, at: Date = Date()) {
        entries[photoId] = Entry(count: max(0, count), at: at)
    }

    func entry(for photoId: String) -> Entry? {
        entries[photoId]
    }
}
