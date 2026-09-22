import SwiftUI

/// 見出しのロゴ（モック1・2・3・5 の左上）。
///
/// **絵の素材を持ち込まない。** 画像を足すと、色を変えるたびに
/// 差し替えが要り、ダークとライトで2枚になる。青い角丸の中に山の記号を
/// 置くだけなら、字の大きさに合わせて伸び縮みもする。
///
/// 文字は `Journey` が細く `Photo` が太い——モックの組み方に合わせる。
struct AppLogo: View {

    var body: some View {
        HStack(spacing: 8) {
            mark
            HStack(spacing: 4) {
                Text("Journey")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                Text("Photo")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.68, blue: 1.0))
            }
        }
        // **読み上げは1つの名前として。** 記号と2つの語がばらばらに
        // 読まれると、開くたびに3回喋る
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journey Photo")
    }

    private var mark: some View {
        Image(systemName: "mountain.2.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 24, height: 24)
            .background(Color(red: 0.16, green: 0.45, blue: 0.95),
                        in: RoundedRectangle(cornerRadius: 7))
    }
}
