import Foundation

/// 地図の札を、**地図を押して閉じる**（2026-11-16 判断・使い勝手の見直し A7）。
///
/// 札の右上の × をやめた。地図の空いている所を押したら、写真のピンの札と観光スポットの札を下げる。
/// 押した所が**ピンの上なら閉じない**——ピンのボタンが札を開き直すので、ここで閉じると開いた札を
/// すぐ消してしまう（ピンのボタンと地図を押した合図は同時に届く）。
///
/// Apple の地点の札（`placeCard`）はここでは閉じない。地点を押すと地図の選び（`MapSelection`）が
/// 先に入れ替わり、どちらが後に届くか決まっていないため、新しく選んだ地点の札を消しかねない
enum MapCardDismiss {

    /// ピンの印の当たりの半径（ピンの印は 44pt の四角・`PhotoMapView.photoPinSize`。対角の半分＋少しのゆとり）
    static let pinRadius: CGFloat = 34

    /// 押した所で札を閉じるか。`pinPoints` は地図の上のピンの中心（画面の座標）
    static func closes(tap: CGPoint, pinPoints: [CGPoint], radius: CGFloat = pinRadius) -> Bool {
        !pinPoints.contains { point in
            let dx = point.x - tap.x, dy = point.y - tap.y
            return dx * dx + dy * dy <= radius * radius
        }
    }
}

/// 「このエリアを検索」を出すか（2026-11-16 判断・使い勝手の見直し A9）。
///
/// 開いたばかりの地図では押しても今と同じ範囲を探すだけなので出さない。**指で地図を動かした後だけ**出す。
/// 範囲で絞っている間は、数と解除の口として出し続ける（解除できる所を消さない）
enum MapAreaButton {
    static func shows(areaApplied: Bool, movedByUser: Bool) -> Bool {
        areaApplied || movedByUser
    }
}
