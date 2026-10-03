import Foundation

/// 写真の出典の1行（「写真: 作者 / ライセンス」など）から開ける先の1つ（2026-10-03）。
///
/// 2026-10-03 判断: 出典の1行は1本の文字の中にリンクを付けて出している（`SpotImage.linkedCredit`・
/// `SpotSample.linkedCredit`）が、文中のリンクの当たりは字の高さ（12pt の1行≒16pt）しかなく、
/// 44pt に届かない。1本の文字の中の複数のリンクは、折り返しで位置が決まらず、それぞれを 44pt に
/// 広げられない。そこで**見た目は文中のリンクのまま**、1行全体を 44pt 以上の1つの当たりにし、
/// 行き先が2つ以上ならメニューで選ばせる（1つならそのまま開く）。画面は `CreditLinksMenu`。
struct CreditLink: Equatable, Identifiable {
    let label: String
    let url: URL
    var id: URL { url }

    /// 出典の1行の当たりの高さの下限（押せるものは 44pt・`WebTheme.minTapTarget`）。
    /// 字が1行で短くても、当たりはこの高さまで広げる（字の大きさ・色・並びは変えない）
    static let tapHeight: Double = Double(WebTheme.minTapTarget)

    /// ライセンスの文面
    static func license(_ name: String, url: URL) -> CreditLink {
        CreditLink(label: L("ライセンス（\(name)）を開く", "Open license (\(name))"), url: url)
    }

    /// Commons のファイルのページ（出典）
    static func commonsPage(_ url: URL) -> CreditLink {
        CreditLink(label: L("Wikimedia Commons のページを開く", "Open on Wikimedia Commons"), url: url)
    }
}
