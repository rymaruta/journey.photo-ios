import Foundation

/// すれちがいの束の「‹ 1 / 7 枚 ›」（`PassViewerView`）。
///
/// **2026-11-14 判断（人間工学の点検・WCAG 2.5.1「指の動きだけに頼らない」）**: 前は次・前の乗車券へ行く方法が
/// 払うだけだった（読み上げの操作を除く）。払えない人・払うと回ってしまう人のために、下の「ありがとう」「帳に入れる」の
/// すぐ上（親指の届く帯）に「‹」「›」のボタンを置く。払う・回す操作は今のまま残す（速さの境目 `PassSpinGesture` は変えない）。
/// 手数: 次へは「払う1回」→「払う1回、または押す1回」。
///
/// - 枚数は上の眉の下（親指から遠い）から、このボタンの間へ移す
/// - 最初では「‹」、最後では「›」を押せなくする（板の「使えないとき 32%」で薄く・読み上げでは「淡色」と読まれる）
///
/// 画面を持たない層に置いてあるので、Linux の `swift test` で確かめられる
enum PassViewerPager {

    /// 押せない側の濃さ（板 Components「01 ボタン」の使えないとき 32%）
    static let disabledOpacity = 0.32

    static let previousIdentifier = "pass.viewer.previous"
    static let nextIdentifier = "pass.viewer.next"
    static let countIdentifier = "pass.viewer.count"

    static var previousLabel: String { L("前の乗車券", "Previous ticket") }
    static var nextLabel: String { L("次の乗車券", "Next ticket") }

    /// 前へ行けるか（最初の1枚では行けない）
    static func canGoBack(index: Int, count: Int) -> Bool {
        count > 0 && index > 0
    }

    /// 次へ行けるか（最後の1枚では行けない）
    static func canGoForward(index: Int, count: Int) -> Bool {
        index + 1 < count
    }

    /// 「1 / 7 枚」
    static func countText(index: Int, count: Int) -> String {
        L("\(index + 1) / \(count) 枚", "\(index + 1) of \(count)")
    }
}
