import Foundation
import SwiftUI

/// **すれちがいの束の画面の、文字の大きさの上限**（`PassViewerView.typeLimit` が読む・2026-11-14）。
///
/// 束の画面は送らない（きっぷは決まった大きさ・`PassCardStyle` の字組の注記）。文字を大きくしすぎると、見出し・
/// 手がかり・下のボタン（ありがとう・帳に入れる）が画面の外へ押し出されて押せなくなるので、上限を置いている
/// （2026-10-21 判断）。人間工学の点検「追加の点検 4」（HIG「少なくとも 200%」）で、上限を**ボタンが画面の中で
/// 押せる大きさのうち一番大きい段**まで上げる。どの段まで入るかは UI テストで上限を差し替えて測る
/// （`ScreenshotTests.testMeasuresPassViewerTypeLimits`・推定で決めない）。
///
/// 画面のほうは別の担当が触っているので、`PassViewerView` は上限の1行だけをこちらに向けた。
enum PassViewerTypeLimit {

    /// 決めた上限
    nonisolated static let decided: DynamicTypeSize = .xxxLarge

    /// UI テストで上限を差し替えて測る鍵（Debug のみ）。`-JPPreviewPassTypeLimit ax3` など
    static let previewKey = "JPPreviewPassTypeLimit"

    /// 画面が使う上限。Release では必ず `decided`
    nonisolated static var value: DynamicTypeSize {
        #if DEBUG
        if let override = parse(UserDefaults.standard.string(forKey: previewKey)) { return override }
        #endif
        return decided
    }

    /// 「xxxl」「ax1」〜「ax5」を段に読む（それ以外は nil）
    nonisolated static func parse(_ raw: String?) -> DynamicTypeSize? {
        switch raw?.lowercased() {
        case "xxl": return .xxLarge
        case "xxxl": return .xxxLarge
        case "ax1": return .accessibility1
        case "ax2": return .accessibility2
        case "ax3": return .accessibility3
        case "ax4": return .accessibility4
        case "ax5": return .accessibility5
        default: return nil
        }
    }
}
