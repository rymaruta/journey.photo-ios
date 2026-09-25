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
/// マーク 28pt・間 8pt もサイトの値。以前の「Photo だけ青」はサイトに無い。
struct AppLogo: View {

    var body: some View {
        HStack(spacing: 8) {
            mark
            Text("Journey Photo")
                .font(JPFont.wordmark)
                .tracking(-0.55)
                .foregroundStyle(WebTheme.foreground)
                // 見出しの幅が足りない端末で2行に割れないように
                .lineLimit(1)
                .fixedSize()
        }
        // **読み上げは1つの名前として。** 記号と2つの語がばらばらに
        // 読まれると、開くたびに3回喋る
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journey Photo")
    }

    private var mark: some View {
        Image("BrandMark")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 28, height: 28)
            .foregroundStyle(WebTheme.foreground)
    }
}
