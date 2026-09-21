import SwiftUI

/// 写真を大きく見る。**送りと拡大だけ**——ここで操作を増やさない。
///
/// 一覧から開いた写真は、たいてい隣も見たい。詳細画面に戻ってから
/// もう1枚押す、をさせない（Web のモーダルが左右送りを持っているのと同じ理由）。
struct PhotoViewerView: View {

    let photos: [Photo]
    @State var index: Int

    @Environment(\.dismiss) private var dismiss
    @State private var scale: Double = 1

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
                        // 2回叩いて元に戻す（拡大したまま迷子にならない出口）
                        .onTapGesture(count: 2) { scale = 1 }
                        .accessibilityLabel(photo.accessibilityText)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

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
}
