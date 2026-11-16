import Foundation

/// 地図の札を、**地図を押して閉じる**（2026-11-16 判断・使い勝手の見直し A7）。
///
/// 札の右上の × をやめた（写真のピン・観光スポット・Apple の地点の3つとも）。地図の空いている所を押したら札を下げる。
/// - 押した所が**ピンの上（件数のバッジを含む）なら閉じない**——ピンのボタンが札を開き直すので、ここで閉じると
///   開いた札をすぐ消してしまう（ピンのボタンと地図を押した合図は同時に届く）
/// - **すぐには閉じない。** 少し待ち（`closeDelayNanoseconds`）、その間に
///   - 2回目が来たら（2回たたいて寄せる操作）取り消す（`Pending`）
///   - 札が替わっていたら（Apple の地点を押して別の地点の札になった）閉じない（`Snapshot`）
enum MapCardDismiss {

    /// ピンの中心から見た「閉じない」範囲（pt）。写真のピンは 44 の四角（中心から ±22）で、
    /// 件数のバッジは右上へはみ出す（`PhotoMapView.badgeOffset` の 10・8 だけ外へ。バッジは 24 の丸）
    /// ——バッジの右上の角は中心から (32, -30)。それに指のゆとり 6 を足す。
    /// 観光スポットの印（40 の丸・当たり 44）もこの中に入る
    static let protectedMinX: CGFloat = -28
    static let protectedMaxX: CGFloat = 38
    static let protectedMinY: CGFloat = -36
    static let protectedMaxY: CGFloat = 28

    /// 閉じるまで待つ長さ。2回たたいた2回目は、1回目から約 0.3 秒以内に来る
    static let closeDelayNanoseconds: UInt64 = 400_000_000

    /// 押した所で札を閉じるか。`pinPoints` は地図の上のピンの中心（画面の座標）
    static func closes(tap: CGPoint, pinPoints: [CGPoint]) -> Bool {
        !pinPoints.contains { point in
            let dx = tap.x - point.x, dy = tap.y - point.y
            return dx >= protectedMinX && dx <= protectedMaxX && dy >= protectedMinY && dy <= protectedMaxY
        }
    }

    /// いま出している札（写真のピン・観光スポット・Apple の地点の id）。閉じる予約の間に替わったら閉じない
    struct Snapshot: Equatable {
        var pin: String?
        var official: String?
        var place: String?
    }

    /// 閉じる予約。新しく予約するか取り消すと、前の予約は効かなくなる
    struct Pending {
        private var current = 0

        mutating func schedule() -> Int {
            current += 1
            return current
        }

        mutating func cancel() {
            current += 1
        }

        func isCurrent(_ ticket: Int) -> Bool {
            ticket == current
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
