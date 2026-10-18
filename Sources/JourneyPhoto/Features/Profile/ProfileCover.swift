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
            .overlay {
                LinearGradient(stops: [.init(color: WebTheme.background.opacity(0.25), location: 0),
                                       .init(color: WebTheme.background.opacity(0), location: 0.4),
                                       .init(color: WebTheme.background, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            // 飾り。読み上げは名前から始める
            .accessibilityHidden(true)
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
