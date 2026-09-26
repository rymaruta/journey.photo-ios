import SwiftUI

/// 写真を大きく見る。**送りと拡大だけ**——ここで操作を増やさない。
///
/// 一覧から開いた写真は、たいてい隣も見たい。詳細画面に戻ってから
/// もう1枚押す、をさせない（Web のモーダルが左右送りを持っているのと同じ理由）。
struct PhotoViewerView: View {

    let photos: [Photo]
    @State var index: Int
    /// その写真にいいねを付けているか（詳細画面が知っている）。
    ///
    /// 🔴 **写真ごとに聞く。** 以前は詳細画面の1枚の値を1つ受け取り、
    /// 隣へ送ってから2回叩くと**元の1枚にいいねが付いていた**
    /// （元の1枚がいいね済みなら、隣の写真には何も起きなかった）
    var isLiked: (Photo) -> Bool = { _ in false }
    var isSignedIn: Bool = false
    /// ダブルタップでいいねを送る。**いま見ている写真**を渡す。
    /// 解除はしない（`DoubleTapLike`）
    var onDoubleTapLike: (Photo) -> Void = { _ in }

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
            .tabViewStyle(.page(indexDisplayMode: .never))

            // **何枚目か**（モック6 の「3/10」）。点の列より数の方が、
            // 20枚あるときに現在地が分かる
            if photos.count > 1 {
                Text("\(index + 1)/\(photos.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(.top, 20)
                    .padding(.trailing, 76)
                    .allowsHitTesting(false)
            }

            // 撮影地とサムネイルの帯（モック6 の状態例）。**下に重ねる**
            VStack(spacing: 10) {
                Spacer()
                if let place = currentPlace {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill")
                        Text(place).lineLimit(1)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.55), in: Capsule())
                }
                thumbnailStrip
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)

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
                    .font(.system(size: 20, weight: .bold))
                    .padding(14)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
            .accessibilityLabel(Labels.Common.close)
        }
        .statusBarHidden()
    }

    /// いま見ている写真の撮影地（無ければ出さない）
    private var currentPlace: String? {
        guard photos.indices.contains(index) else { return nil }
        let place = (photos[index].location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? nil : place
    }

    /// サムネイルの帯。**1枚しか無いときは出さない**（送る先が無い）
    @ViewBuilder
    private var thumbnailStrip: some View {
        if photos.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { offset, photo in
                        Button {
                            index = offset
                            // 送ったら倍率は戻す（拡大したまま別の写真に移らない）
                            scale = 1
                        } label: {
                            RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                                    offset == index ? Color.white : Color.white.opacity(0.25),
                                    lineWidth: offset == index ? 2.5 : 1))
                                .opacity(offset == index ? 1 : 0.65)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("\(offset + 1)枚目", "Photo \(offset + 1)"))
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 60)
        }
    }

    private func handleDoubleTap() {
        guard let shown = DoubleTapLike.shown(photos, at: index) else { return }
        switch DoubleTapLike.action(isZoomed: scale > 1, alreadyLiked: isLiked(shown), signedIn: isSignedIn) {
        case .resetZoom:
            scale = 1
        case .like:
            onDoubleTapLike(shown)
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
