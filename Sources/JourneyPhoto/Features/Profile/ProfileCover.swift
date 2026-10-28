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

    /// 帯の高さ。**2026-10-28 owner の要望で 240**（「選んだ写真がヘッダーで映る範囲をもう少し広げたい」）。
    /// 板 v2（MyPage・UserProfile）は 196、v1 は 180。上 25% の黒 → 透明 → 下の 4 割で黒へ溶かす
    /// （`ProfileCoverFade`・帯の上 6 割＝144pt は写真がそのまま見える）。
    /// **帯の高さはここ1か所だけ**（表紙の見える範囲の調整など、帯の縦横比はここから取る）
    nonisolated static let height: CGFloat = 240
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
/// 上 25% の黒 → 透明（時計とガラスの丸の地）→ **下端でちょうど黒**（アイコンと名前が乗る側）。
///
/// 2026-10-28 判断（owner が案A を選び、そのあと値を直した）:
/// - 初めは 40% の透明から下端の黒まで1本の直線で、写真の終わりに線が入り「バッサリ黒」に見えた
/// - 案A の1回目（40% から 0, .08, .24, .46, .70, .90, 1.0）は、80% で .70・90% で .90 と直線より
///   下が濃く、帯の 6 割から下がほぼ黒になった。owner「だいぶ怪しい。元の写真のほとんど映ってないかも」
/// - いま: **透明を 60% まで下げ、黒は下端の 2 割に寄せる**。60% から等間隔に
///   0, .03, .10, .22, .42, .70, 1.0。入りはごく緩く（継ぎ目の上端に線を出さない）、帯の上 6 割は
///   写真がそのまま見え、下端は地の `WebTheme.background` と同じ黒で終わる
/// 板 v1 の MyPage は 180pt・下 110pt の `linear-gradient(to top,#000,transparent)`
struct ProfileCoverFade: View {

    /// ここまでは写真をそのまま見せる（上端の黒を除く）。ここから下へ黒を重ねていく
    nonisolated static let fadeStart: CGFloat = 0.6
    /// 下の黒の濃さ。`fadeStart` から下端まで等間隔に置く
    nonisolated static let fadeOpacities: [Double] = [0, 0.03, 0.10, 0.22, 0.42, 0.70, 1.0]
    /// 上端の黒（時計とガラスの丸の地）。前と同じく 40% で透明に戻す（透明を 60% に下げても、
    /// 上の黒を下へ伸ばさない）
    nonisolated static let topOpacity: Double = 0.25
    nonisolated static let topClearAt: CGFloat = 0.4

    /// 掛けの段（位置 0…1・黒の濃さ）。上端 → 40% で透明 → 60% まで透明 → 多段で下端の黒
    nonisolated static var stops: [(location: CGFloat, opacity: Double)] {
        let steps = fadeOpacities.count - 1
        let fade = fadeOpacities.enumerated().map { index, opacity in
            (location: fadeStart + (1 - fadeStart) * CGFloat(index) / CGFloat(steps), opacity: opacity)
        }
        return [(location: 0, opacity: topOpacity), (location: topClearAt, opacity: 0)] + fade
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
