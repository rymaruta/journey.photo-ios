import Foundation

/// 写真を2回叩いたときの振る舞い。**Web のモーダルと同じ約束**
/// （`app/components/GalleryModal/index.tsx` の `handleImageTap`）。
///
/// 決まりは2つだけ:
///
/// 1. **いいね済みなら解除しない。** 2回目は演出だけにする。
///    ——うっかり2回叩いていいねが消えると、押した本人は気づけない
///    （数は他人のぶんも含むので、1 減ってもおかしく見えない）
/// 2. **拡大しているときは、いいねではなく倍率を戻す。**
///    Web のモーダルに拡大は無いのでこの分岐も無いが、アプリには
///    両指で広げる操作がある。拡大したまま迷子になる出口を潰さない
enum DoubleTapLike {

    enum Action: Equatable {
        /// いいねを送る
        case like
        /// 何もしない（いいね済み・演出だけ）
        case burstOnly
        /// 倍率を戻す
        case resetZoom
    }

    /// **いいねの行き先は、いま見ている1枚。** 左右に送れる画面では、
    /// 開いたときの1枚とは限らない
    static func shown(_ photos: [Photo], at index: Int) -> Photo? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    static func action(isZoomed: Bool, alreadyLiked: Bool, signedIn: Bool) -> Action {
        if isZoomed { return .resetZoom }
        // **ログインしていない人には何も起きない。** 断り書きを出しても、
        // 写真を見ている最中に割り込むだけ（いいねのボタンは別にある）
        guard signedIn else { return .burstOnly }
        return alreadyLiked ? .burstOnly : .like
    }
}
