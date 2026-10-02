import UIKit

/// 下のタブバーの色。**選んでいるタブは真鍮**（owner「デザインの箇所は白より真鍮色が好き」
/// 2026-09-29）。
///
/// 🔴 **TabView の `.tint` だけに頼らない（2026-10-02 の調査）。** `RootView` は
/// TabView に `.tint(WebTheme.accent)`（真鍮）を付け、各タブの中身に
/// `.tint(WebTheme.foreground)`（白）を配り直している。SwiftUI はタブの札の
/// 選択色を「選んでいるタブの中身の tint」から拾うことがあり（OS の版で振る舞いが
/// 違う）、そのときは真鍮が白に上書きされて見える。中身の白は変えたくないので、
/// タブバーそのもの（UIKit の `UITabBarAppearance`）に選択色を直に書く——
/// 明示した `selected.iconColor` / `titleTextAttributes` は tint より強い。
///
/// 背景には触らない。ふだんの面は OS の既定（`configureWithDefaultBackground`）、
/// 下端まで送ったときの面は OS の既定と同じく透明（`configureWithTransparentBackground`）
/// にして、見た目は前のまま色だけ決める
enum TabBarStyle {

    /// 選んでいるタブの色（真鍮 `#C9A66B`）。**黒い地の上だけ**に置く色
    /// （タブバーは黒い面の上）
    static let selectedHex: UInt32 = BrandPalette.accent

    /// アプリの起動時に一度だけ（`JourneyPhotoApp.init`）。これより後に作られる
    /// タブバーに効く
    /// `apply()` を呼んだ回数。**起動時に呼ばれていることを試験で確かめる印**
    /// （呼び出しを消すと、色の決まりだけの試験は通ったまま札が白に戻る）
    @MainActor private(set) static var appliedCount = 0

    @MainActor
    static func apply() {
        appliedCount += 1
        let brass = UIColor(red: Double((selectedHex >> 16) & 0xFF) / 255,
                            green: Double((selectedHex >> 8) & 0xFF) / 255,
                            blue: Double(selectedHex & 0xFF) / 255, alpha: 1)
        let standard = UITabBarAppearance()
        standard.configureWithDefaultBackground()
        paint(standard, selected: brass)
        let edge = UITabBarAppearance()
        edge.configureWithTransparentBackground()
        paint(edge, selected: brass)

        let bar = UITabBar.appearance()
        bar.standardAppearance = standard
        bar.scrollEdgeAppearance = edge
        bar.tintColor = brass
    }

    /// 縦並び・横並び・狭い横並びの3つ全部の「選んでいる」に色を書く
    /// （iPad・横向きで別の並びが使われる）
    @MainActor
    private static func paint(_ appearance: UITabBarAppearance, selected color: UIColor) {
        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.selected.iconColor = color
            item.selected.titleTextAttributes = [.foregroundColor: color]
        }
    }
}
