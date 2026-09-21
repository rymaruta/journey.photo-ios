import SwiftUI

/// 写真を大きく見る。**送りと拡大だけ**——ここで操作を増やさない。
///
/// 一覧から開いた写真は、たいてい隣も見たい。詳細画面に戻ってから
/// もう1枚押す、をさせない（Web のモーダルが左右送りを持っているのと同じ理由）。
struct PhotoViewerView: View {

    let photos: [Photo]
    @State var index: Int
    /// いま見ている写真にいいねを付けているか（詳細画面が持っている）
    var isLiked: Bool = false
    var isSignedIn: Bool = false
    /// ダブルタップでいいねを送る。**解除はしない**（`DoubleTapLike`）
    var onDoubleTapLike: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var scale: Double = 1
    /// ハートを弾けさせる回数。値が変わるたびに演出が走る
    @State private var burst = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { offset, photo in
                    RemoteImage(url: photo.detailImageURL, contentMode: .fit)
                        .scaleEffect(scale)
                        // **両指で広げて拡大、離したら戻す。**
                        // 倍率を持ち越すと、次の写真が拡大されたまま出る
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in scale = max(1, min(4, value)) }
                                .onEnded { _ in scale = 1 }
                        )
                        // **2回叩いていいね**（Web のモーダルと同じ）。
                        // 拡大中だけは倍率を戻す側に倒す
                        .onTapGesture(count: 2) { handleDoubleTap() }
                        .accessibilityLabel(photo.accessibilityText)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // ダブルタップの演出。Web も同じ位置（画面の中央）で出す
            if burst > 0 {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
                    .id(burst)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
            .accessibilityLabel(Labels.Common.close)
        }
        .statusBarHidden()
    }

    private func handleDoubleTap() {
        switch DoubleTapLike.action(isZoomed: scale > 1, alreadyLiked: isLiked, signedIn: isSignedIn) {
        case .resetZoom:
            scale = 1
        case .like:
            onDoubleTapLike()
            showBurst()
        case .burstOnly:
            showBurst()
        }
    }

    private func showBurst() {
        burst += 1
        let shown = burst
        // **消すのは自分が出したぶんだけ。** 続けて叩かれたとき、
        // あとから出たハートまで一緒に消えないように
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if burst == shown { burst = 0 }
        }
    }
}
