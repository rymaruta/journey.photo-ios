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

    /// **いま見ている1枚**（題・共有・下のハート）。左右に送れる画面では、
    /// 開いたときの1枚とは限らない。**ダブルタップの行き先には使わない**（`tap`）
    static func shown(_ photos: [Photo], at index: Int) -> Photo? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    /// 叩いたページへの答え。**行き先は叩いたページの写真**（`tapped`）で、
    /// 選んでいる添字（`shownIndex`）からは引かない。
    ///
    /// 🔴 ページ式 TabView の `selection` は、送りの指を離してから少し遅れて替わる。
    /// その窓で新しいページを2回叩くと、添字から引いた「前のページ」の写真に
    /// いいねが付いていた。拡大も**叩いたページが拡大しているページ**のときだけ見る
    /// ——拡大は選んでいるページにだけ掛かるので、遅れた添字の拡大で新しいページの
    /// いいねを「倍率を戻す」に化けさせない
    struct Tap: Equatable {
        let target: Photo
        let action: Action
    }

    static func tap(_ tapped: Photo, at offset: Int, shownIndex: Int, isZoomed: Bool,
                    alreadyLiked: Bool, signedIn: Bool, acceptsLike: Bool = true) -> Tap {
        Tap(target: tapped,
            action: action(isZoomed: offset == shownIndex && isZoomed, alreadyLiked: alreadyLiked,
                           signedIn: signedIn, acceptsLike: acceptsLike))
    }

    /// - Parameter acceptsLike: その写真にいいねを付けられるか。**下書きは付けられない**
    ///   （サーバーが断る。送ると先に灯したハートが黙って消えた）
    static func action(isZoomed: Bool, alreadyLiked: Bool, signedIn: Bool,
                       acceptsLike: Bool = true) -> Action {
        if isZoomed { return .resetZoom }
        // **ログインしていない人・下書きには何も起きない。** 断り書きを出しても、
        // 写真を見ている最中に割り込むだけ（いいねのボタンは別にある）
        guard signedIn, acceptsLike else { return .burstOnly }
        return alreadyLiked ? .burstOnly : .like
    }
}
