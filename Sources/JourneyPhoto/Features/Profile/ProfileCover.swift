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
    /// 開くたびに `cacheBust` で別の URL になるので、0 に畳むと戻ってくる
    /// たびに見出しが 180pt 跳ねる
    var reserve = false
    var onLoaded: (Bool) -> Void = { _ in }

    /// 板どおりの高さ。下の 110pt を黒へ溶かす（アイコンと名前が乗る側）
    static let height: CGFloat = 180
    /// 見出しを帯の下端へ引き上げる量。64pt のアイコンの半分弱（板は 84pt に 50pt）
    static let avatarOverlap: CGFloat = 28

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
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [WebTheme.background.opacity(0), WebTheme.background],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
            }
            .clipped()
            // 飾り。読み上げは名前から始める
            .accessibilityHidden(true)
    }
}

extension View {
    /// カバーに重なるアイコンの縁。**板どおり黒の 3pt**で、写真の上でも丸が割れない
    @ViewBuilder
    func coverCutout(_ onCover: Bool) -> some View {
        if onCover {
            overlay(Circle().strokeBorder(WebTheme.background, lineWidth: 3).padding(-3))
        } else {
            self
        }
    }
}
