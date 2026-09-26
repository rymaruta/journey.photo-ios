import SwiftUI

/// 見出しのロゴ（モック1・2・3・5 の左上）。
///
/// **記号はサイトと同じアパーチャ（`BrandMark`）。** 以前は青い角丸に
/// 山の記号を描いていたが、それはサイトが以前使っていたマークで、サイトは
/// アパーチャに揃え直している（`photo-gallery/app/layout.tsx`）。
/// 素材は `template` なので、色は `foregroundStyle` で決まる——
/// ライト／ダークで2枚持たなくてよい。
///
/// **大きさは枠で決める（`resizable`）。** 記号の文字（SF Symbols）だと、
/// ナビゲーションバーの中では指定より大きく描かれ、角丸からはみ出した
/// （実機の絵・2026-09-25）。
///
/// **文字もサイトと同じ**（`docs/BRAND.md`）: `Journey Photo`（ドット無し）、
/// serif の Bold（iPhone では New York）、字間 -0.025em、白1色、22pt。
/// 間 8pt もサイトの値。マークは**見える絵で約18pt**（サイトの 28px の枠に余白込みと
/// 同じ見た目の大きさ）。以前の「Photo だけ青」はサイトに無い。
struct AppLogo: View {

    /// 見出しのロゴ（22pt）と、ログイン画面の大きいロゴ（40pt・板 41）
    enum Size { case header, hero }

    var size: Size = .header

    /// 文字の大きさ（見出しはサイトと同じ 22pt 固定）
    private var fontSize: Double { size == .header ? 22 : 40 }
    /// **絵の枠の大きさ。** 絵は余白 2% で切り出してあるので、見える絵は枠の約96%。
    /// **見える大きさは以前のまま**（見出し: 28pt の枠に余白 17% 込み＝約18pt、
    /// 大きいロゴ: 44pt の枠＝約28pt）——直したのは「ずれ」で、大きさではない
    private var markSize: Double { size == .header ? 19 : 29.5 }
    /// 絵と文字の間。見出しはサイトの `gap-2` = 8px、大きいロゴは板 41 の 12px。
    /// 以前は透明な余白のぶん、これより約5〜8pt 広く見えていた
    private var spacing: Double { size == .header ? 8 : 12 }
    /// New York Bold の大文字の高さ（字の大きさに対する割合）。
    /// **文字が縮んだとき（minimumScaleFactor）は縮む前の大きさで計算する**ので、
    /// 絵は最大で見出し 1.5pt・大きいロゴ 3pt ほど上に寄る。縮むのは狭い端末で
    /// 文字が入り切らないときだけ（見積もり・実機で未確認）
    private static let capHeightRatio = 0.70

    var body: some View {
        // 🔴 **絵の中心は大文字の高さの真ん中に揃える。** 行の箱の中心で揃えると
        // 下の余白（J や y の下がり）の分だけ絵が上下にずれて見える
        // （owner の指摘 2026-09-26「アイコンと文字の位置がズレてる」）
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            mark
                .alignmentGuide(.firstTextBaseline) { d in
                    d.height / 2 + fontSize * Self.capHeightRatio / 2
                }
            Text("Journey Photo")
                .font(size == .header ? JPFont.wordmark : .system(size: 40, weight: .bold, design: .serif))
                // 字間 -0.025em（サイトと同じ）
                .tracking(-fontSize * 0.025)
                .foregroundStyle(WebTheme.foreground)
                // 見出しの幅が足りない端末で2行に割れないように
                .lineLimit(1)
                // **狭い端末では少しだけ縮める。** 右にベルとアバター（44pt×2）が
                // 並ぶので、375pt 幅だと中央に使えるのは約150pt。縮めずに固定すると
                // ベルに重なる（レビューの見積もり・実機で未確認）
                .minimumScaleFactor(size == .header ? 0.8 : 0.6)
        }
        // **読み上げは1つの名前として。** 記号と2つの語がばらばらに
        // 読まれると、開くたびに3回喋る
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journey Photo")
    }

    /// **絵は余白なしで切り出してある**（`Tools/make-brand-assets.cjs`）。
    /// 以前は元絵を丸ごと縮めた版で、周りに約17%の透明な余白があり、
    /// 文字との間が指定の 8pt ではなく約13pt に見えていた
    private var mark: some View {
        Image("BrandMark")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: markSize, height: markSize)
            .foregroundStyle(WebTheme.foreground)
    }
}
