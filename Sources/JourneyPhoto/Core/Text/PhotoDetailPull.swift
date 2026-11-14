import Foundation

/// **写真の詳細で、写真を下に引いて前の画面へ戻る**（2026-11-13 owner 決定・札 #592）。
///
/// iPhone の写真アプリ・Instagram と同じ: いちばん上まで戻っている状態で写真を下に引くと、写真が指に付いて
/// 縮みながら動き、離すと前の画面に戻る。引く量が足りなければ元に戻る。上に払うと今までどおり説明・コメントへ流れる。
/// 押す回数は「左上の戻る（1回）」→ 0回（引くだけ）。左上の戻る・端からの戻るは残す（指を使わない人・読み上げの道）。
///
/// 画面を持たない計算（`DetailPullCatcher`・`PhotoDetailView` が読む）。値は pt・pt/秒
enum PhotoDetailPull {

    /// これだけ下へ引いた所（勢いを足した行き先）で離すと戻る。**人のストーリーの下へ払って閉じる
    /// （`StoryReel.closeDistance`）と同じ 120pt**——同じアプリの中で「下へ引いて閉じる」の手ごたえをそろえる
    static let closeDistance: Double = 120

    /// 離したときの勢いを行き先に足す割合（秒）。UIKit の送りの止まり方（`UIScrollView.DecelerationRate.normal`
    /// ＝ 0.998/ms）で、その速さのまま指を離したときに滑って止まるまでの距離（速さ × 0.998 / (1 − 0.998) / 1000 ≒ 0.499 秒分）。
    /// 2026-11-13 判断: 短く素早く払っても戻れる（写真アプリと同じ）。**上へ払い戻した指は行き先が縮むので戻らない**
    static let projectionSeconds: Double = 0.998 / (1 - 0.998) / 1000

    /// 写真の縮みの下限（いちばん引いた所で 0.75 倍）。写真アプリ・Instagram の「指に付いて小さくなる」の程度。
    /// 小さくしすぎると何の写真か分からなくなる（つまむと地図の `PinchToMap.minDisplayScale` 0.35 は地図を見せる所なので別）
    static let minScale: Double = 0.75
    /// ここまで引くと縮みが下限に届く（pt）。画面の高さの半分ほど
    static let fullShrinkDistance: Double = 400
    /// 写真の下の説明・コメント・入力欄が消えきる量（pt）。戻る所（`closeDistance`）を越えたら、ほとんど写真だけになる
    static let fadeDistance: Double = 200

    /// 見えている上端に居るとみなす幅（pt）。送りの止まり際の端数で「上に居ない」にしない
    static let topTolerance: Double = 1

    /// いちばん上まで戻っているか（`UIScrollView` の `contentOffset.y` と、上の余白 `adjustedContentInset.top`）
    static func isAtTop(offsetY: Double, insetTop: Double) -> Bool {
        offsetY <= -insetTop + topTolerance
    }

    /// 動き始めで、引く動きを始めるか。**上に居て、下向きで、縦が横より大きいとき**だけ。
    /// 上へ払う・横に払う（束の写真を送る・端からの戻る）・上に居ないときは今までどおり下の部品に渡す
    static func starts(dx: Double, dy: Double, atTop: Bool) -> Bool {
        atTop && dy > 0 && dy >= abs(dx)
    }

    /// 指を止めているとみなす時間（ms）。最後に量が変わってからこれより長く経って離した指は、速さ 0 として扱う。
    ///
    /// **2026-11-14 判断（Mac の回 1232 の値）**: 90pt ゆっくり引いて 1.5 秒止めて離した指で、UIKit のパン
    /// （`UIPanGestureRecognizer.velocity(in:)`）が離した時の縦の速さとして 172pt/秒を返した
    /// （`moveAgeMs=1478`・止めている間に量は一度も変わっていない・動いている間の最大は 288）。止めた指の速さを
    /// 0 に戻さず、最後に動いていた頃の速さを返していた。そのため行き先が 80 ＋ 172 × 0.499 ≒ 166pt になり、
    /// 戻る所（120pt）を越えて閉じた（`endCloses=1`）。
    /// 100ms は、触れている指の動きが届く間隔（60〜120Hz で 8〜17ms）の6倍以上。これだけ量が変わらなければ止めている
    static let stillMilliseconds: Double = 100

    /// 離したときに使う縦の速さ。**最後に量が変わってから `stillMilliseconds` を越えて止めていたら 0**
    /// （UIKit が返す速さは、止めている間も最後に動いていた頃の値のまま）
    static func releaseVelocity(reportedY: Double, sinceLastMoveMs: Double) -> Double {
        sinceLastMoveMs > stillMilliseconds ? 0 : reportedY
    }

    /// 離したとき（勢いを足した行き先）に前の画面へ戻るか。`velocityY` は `releaseVelocity` を通した値
    static func closes(dy: Double, velocityY: Double) -> Bool {
        dy + velocityY * projectionSeconds >= closeDistance
    }

    /// 引いている間の写真の倍率（1 → `minScale`）。**「視差効果を減らす」では縮めない**（指に付いて動くだけ）
    static func scale(dy: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let pulled = min(max(dy, 0), fullShrinkDistance) / fullShrinkDistance
        return 1 - (1 - minScale) * pulled
    }

    /// 引いている間の写真のずらし。**縦は下向きだけ**（指を上へ戻しても写真が元の位置より上へ行かない）、横は指どおり
    static func offset(dx: Double, dy: Double) -> (x: Double, y: Double) {
        (dx, max(0, dy))
    }

    /// 写真の下（説明・コメント・入力欄）の濃さ（1 → 0）。写真だけが指に付いて残る
    static func restOpacity(dy: Double) -> Double {
        max(0, 1 - max(0, dy) / fadeDistance)
    }

    /// 写真の角の丸み。引いている間だけ（つまむと地図で縮めたときと同じ角・`PinchToMapHero`）
    static func rounds(dy: Double) -> Bool {
        dy > 0
    }
}
