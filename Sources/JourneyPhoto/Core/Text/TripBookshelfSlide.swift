import Foundation

/// **本棚の背を、押して・ずらして・離して開く**（2026-11-25 判断・人間工学の案 3）。
///
/// キーボードと同じ形: 押さえると背が浮き、指を離す前なら横へずらして隣の背に替えられる。離すと、浮いている背が開く。
/// 背は 30〜44pt と細く（`spineWidth`）、指先（約 60pt）は背2冊ぶんの幅なので、隣を押しやすい。
/// 押し間違えても、離す前にずらせば直る（前は開いて閉じて押し直す、の2回と約1秒）。
///
/// - **すぐ押して離す**（`holdSeconds` より短い）: 押した背がそのまま開く（今と同じ1回）
/// - **押さえる**（`holdSeconds` 動かさない）: 背が浮く。ずらすと指の下の背に替わる。段の上下へ外す（`slack` より外）と浮きが消え、
///   そこで離せば何も開かない（やめる道）
/// - **押してすぐ払う**（`holdSeconds` の前に `holdSlop` より動く）: 縦の送り・札の横の払い（`ProfileTabSwipe`）に渡す
/// - 振動は「ずらして別の背に替わった時」の軽い1回（`Slide.move` が真）と、「開き切った時」の1回（`TripBookOpening`）だけ。
///   押した時・棚に戻った時の振動はやめた（前は1回の開け閉めで3回鳴った）
///
/// 画面を持たない計算（`SpineSlideCatcher` が読む）
extension TripBookshelf {

    /// 押さえたとみなす時間（秒）。これより早く離せばそのまま開き、これより早く動けば送り・払いに渡す。
    /// 2026-11-25 確かめ役の指摘で 0.15 → 0.28（背の上に指を置いてから縦に送ろうとした指を、押さえたと取り違えない）。
    /// 長押しのメニュー（約 0.5 秒）より短い
    static let holdSeconds: Double = 0.28
    /// 押さえる前に動いてよい量（pt）。これより動いたら送り・払いの指（UIKit の既定の動き出しと同じ 10）
    static let holdSlop: Double = 10
    /// 段の上下へ外れても浮きを残す幅（pt）。これより外へ出たら浮きを消す（やめる）
    static let slideSlack: Double = 30

    /// 押さえたあと縦にこれだけ（`slideSlack` より多く）動いたら、ずらすのをやめて縦の送りに渡す（2026-11-25 確かめ役の指摘）
    static func handsToScroll(dy: Double) -> Bool {
        abs(dy) > slideSlack
    }

    /// 流れている（指を離したあとの惰性の）送りの上の一押しは、送りを止めるだけ。背を開かない・浮かせない（2026-11-25 確かめ役の指摘）
    static func receivesTouch(scrollDecelerating: Bool) -> Bool {
        !scrollDecelerating
    }

    /// 段の左端からの横の位置 `x` にある背（`slots` は段の背ごとの押せる幅＝背の幅＋間・`hitWidth`）。段の外は nil
    static func slotIndex(at x: Double, slots: [Double]) -> Int? {
        guard x >= 0 else { return nil }
        var right = 0.0
        for (index, width) in slots.enumerated() {
            right += width
            if x < right { return index }
        }
        return nil
    }

    /// 押さえている指の下の背。段の上下 `slideSlack` より外は nil（浮きを消す）
    static func slideTarget(x: Double, y: Double, height: Double, slots: [Double]) -> Int? {
        guard y >= -slideSlack, y <= height + slideSlack else { return nil }
        return slotIndex(at: x, slots: slots)
    }

    /// 押さえてずらしている間の状態
    struct Slide: Equatable {
        /// いま浮いている背（段の中の番号）。外したら nil
        private(set) var lifted: Int?
        /// 最後に浮いた背（外して戻ったときに、同じ背なら振動しない）
        private(set) var lastShown: Int?

        init(start: Int?) {
            lifted = start
            lastShown = start
        }

        /// 指が動いた。**別の背に替わったら真**（軽い振動を1回）。外した・同じ背のままは偽
        mutating func move(to index: Int?) -> Bool {
            guard index != lifted else { return false }
            lifted = index
            guard let index else { return false }
            defer { lastShown = index }
            return lastShown != nil && lastShown != index
        }

        /// 離した。開く背（外していたら nil）
        var opens: Int? { lifted }
    }
}
