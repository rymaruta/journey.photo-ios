import SwiftUI

/// プロフィールの上に敷くカバー写真（板 05c・31）。
///
/// **変えられるのに、どこにも出ていなかった。** `ProfileEditView` で上げられて
/// 「カバーを変えました」と出るのに、マイページも人のページもアイコンと名前
/// だけで、`UserProfile.coverURL` はどこからも呼ばれていなかった（2026-09-26）。
///
/// **設定していない人には帯を出さない**（板 05d）。`profiles/<uid>/cover` は
/// 無ければ読み込みに失敗するので、**出せたときだけ**帯を置く。灰色の空き地や
/// 「壊れた写真」の記号は、写真が主役の画面で場所を取るだけになる。
/// 出せたかどうかは `onLoaded` で返す（見出しをカバーの下端に重ねるため）。
struct ProfileCover: View {

    let url: URL?
    /// 前の回に出せていたか。**読み直しの間も帯の場所を空けておく**——
    /// カバーを変えた・開き直したときは `cacheBust` で別の URL になる（`ProfileImageVersions`）
    /// ので、0 に畳むとそのたびに見出しが 180pt 跳ねる
    var reserve = false
    var onLoaded: (Bool) -> Void = { _ in }

    /// 板 v2（MyPage・UserProfile）の高さ 196。上 25% の黒 → 40% で透明 → 下端で黒へ溶かす
    /// （上は時計とガラスの丸の地・下はアイコンと名前が乗る側）。v1 は 180・下 110pt だけ
    nonisolated static let height: CGFloat = 196
    /// 見出しのアイコン（板 v2 88pt）と、帯の下端へ引き上げる量（板 v2 44pt）。
    /// マイページと人のページで同じ。v1 は 84・50
    nonisolated static let avatarSize: CGFloat = 88
    nonisolated static let avatarOverlap: CGFloat = 44
    /// カバーの無い人のアイコン（板 MyPageNoCover: 72pt・名前と横に並べる）
    nonisolated static let compactAvatarSize: CGFloat = 72
    /// カバーに重なるアイコンの黒い縁（板 v2: `box-shadow: 0 0 0 4px #000`）。v1 は 3
    nonisolated static let cutoutWidth: CGFloat = 4

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    band(image)
                        .onAppear { onLoaded(true) }
                case .failure:
                    // 設定していない（または取れない）＝帯ごと出さない
                    Color.clear.frame(height: 0)
                        .onAppear { onLoaded(false) }
                default:
                    // 初めての読み込みは場所を取らない（無い人で跳ねない）。
                    // 前に出せていたなら、同じ高さの地で待つ
                    if reserve {
                        WebTheme.surface.frame(maxWidth: .infinity).frame(height: Self.height)
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
            }
        }
    }

    private func band(_ image: Image) -> some View {
        // **写真は `overlay` で敷く。** `.fill` の写真をそのまま置くと、
        // はみ出した横幅が並びの幅を押し広げる
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .overlay {
                image.resizable().aspectRatio(contentMode: .fill)
            }
            .overlay { ProfileCoverFade() }
            .clipped()
            // 飾り。読み上げは名前から始める
            .accessibilityHidden(true)
    }
}

/// カバーの上に重ねる黒の掛け（マイページ・人のページで同じ。`ProfileCover` だけが使う）。
///
/// 上 25% の黒 → 40% で透明（時計とガラスの丸の地）→ **下端でちょうど黒**（アイコンと名前が乗る側）。
///
/// 2026-10-28 判断（owner が案A を選んだ）: 下半分は**多段で溶かす**。前は 40% の透明から下端の黒まで
/// 1本の直線で、下端で傾きが急に 0 になるため、写真の終わりに**一本の線が入ってバッサリ黒**に見えた。
/// 写真の中ほど（40%）から 10% 刻みに 0 → .08 → .24 → .46 → .70 → .90 → 1.0 と、入りは緩く・
/// 終わりも緩く寄せて、下の黒い地との継ぎ目を消す。下端は 1.0（地の `WebTheme.background` と同じ黒）。
/// 板 v1 の MyPage は 180pt・下 110pt の `linear-gradient(to top,#000,transparent)`（始まりは 39% の所）
struct ProfileCoverFade: View {

    /// 写真の中ほど。ここで透明になり、下へ黒を重ねていく
    nonisolated static let fadeStart: CGFloat = 0.4
    /// 下半分の黒の濃さ（案A）。`fadeStart` から下端まで等間隔に置く
    nonisolated static let fadeOpacities: [Double] = [0, 0.08, 0.24, 0.46, 0.70, 0.90, 1.0]
    /// 上端の黒（時計とガラスの丸の地）
    nonisolated static let topOpacity: Double = 0.25

    /// 掛けの段（位置 0…1・黒の濃さ）。上端 → 中ほどの透明 → 多段で下端の黒
    nonisolated static var stops: [(location: CGFloat, opacity: Double)] {
        let steps = fadeOpacities.count - 1
        let fade = fadeOpacities.enumerated().map { index, opacity in
            (location: fadeStart + (1 - fadeStart) * CGFloat(index) / CGFloat(steps), opacity: opacity)
        }
        return [(location: 0, opacity: topOpacity)] + fade
    }

    var body: some View {
        LinearGradient(stops: Self.stops.map { .init(color: WebTheme.background.opacity($0.opacity), location: $0.location) },
                       startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// カバーに重なるアイコンの縁。**板 v2 どおり黒の 4pt**で、写真の上でも丸が割れない
    @ViewBuilder
    func coverCutout(_ onCover: Bool) -> some View {
        if onCover {
            overlay(Circle().strokeBorder(WebTheme.background, lineWidth: ProfileCover.cutoutWidth)
                .padding(-ProfileCover.cutoutWidth))
        } else {
            self
        }
    }
}
