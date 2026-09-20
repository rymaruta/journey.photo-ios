import SwiftUI

/// 写真を出す。読み込み中と失敗をはっきり分ける。
///
/// **失敗を「ただの空白」にしない。** Web 側は水和のあとサムネイルが消える
/// 不具合を踏んでいて（CLAUDE.md の `24f9df2c`）、無言で消えると
/// 「そういう写真」に見えてしまい原因に気づけない。
struct RemoteImage: View {

    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
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
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(.tertiary)
            // 飾り。読み上げの邪魔をしない
            .accessibilityHidden(true)
    }
}
