import SwiftUI

/// 写真を出す。読み込み中と失敗をはっきり分ける。
///
/// **失敗を「ただの空白」にしない。** Web 側は水和のあとサムネイルが消える
/// 不具合を踏んでいて（CLAUDE.md の `24f9df2c`）、無言で消えると
/// 「そういう写真」に見えてしまい原因に気づけない。
struct RemoteImage: View {

    let url: URL?
    var contentMode: ContentMode = .fill
    /// 枠からはみ出したぶんを、どちら側に残すか。
    ///
    /// **切り抜きの中心は写真ごとに違う**（`Photo.focalPoint`。owner が
    /// Web で掴んで動かせる）。既定の中央のままだと、動かした写真が
    /// アプリでだけ別の切り抜きで出る。
    var alignment: Alignment = .center
    /// 読み込みが片付いたときに呼ぶ（出た＝true・出せないと分かった＝false）。
    /// ストーリーが「絵が出る前から秒数を減らす」のを防ぐためのもの。
    /// 既定は何もしない（他の呼び出しは変わらない）
    var onSettled: ((Bool) -> Void)? = nil
    /// 出せないときに置く記号。
    ///
    /// **人のアイコンに「壊れた写真」の記号を出さない。** アバターを
    /// 設定していない人は珍しくないのに、丸の中に写真の記号が出て
    /// 「読み込みに失敗した」ように見えていた（実機の絵・run 40）。
    /// 人を指す場所では人型を置く。
    var placeholderSymbol: String = "photo"

    var body: some View {
        ZStack {
            WebTheme.surface
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
                    switch phase {
                    case .success(let image):
                        // **寄せるのは写真だけ。** `ZStack` ごと寄せると、
                        // 読み込み中の輪と失敗の記号まで隅に寄って、
                        // 44〜56pt の枠では切れて見えなくなる
                        image.resizable().aspectRatio(contentMode: contentMode)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                            .onAppear { onSettled?(true) }
                    case .failure:
                        placeholder
                            .onAppear { onSettled?(false) }
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        Image(systemName: placeholderSymbol)
            .font(.title2)
            .foregroundStyle(.tertiary)
            // 飾り。読み上げの邪魔をしない
            .accessibilityHidden(true)
    }
}
