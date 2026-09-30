import SwiftUI

/// 写真を大きく見る（板 14）。**送りと拡大、それに共有といいねだけ**。
///
///     ✕            1枚目 / 3            共有
///                 （写真）
///     題                                 ♡
///     機種 · レンズ · f · s · ISO
///
/// 一覧から開いた写真は、たいてい隣も見たい。詳細画面に戻ってから
/// もう1枚押す、をさせない（Web のモーダルが左右送りを持っているのと同じ理由）。
///
/// 板に無いサムネイルの帯は残す——20枚ある束で好きな1枚へ跳べるのはここだけ。
/// 板の点の列は、帯が同じことを言うので置かない。
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
    /// その写真にいいねを付けられるか（下書きは付けられない・`PhotoDetailRules.acceptsReactions`）
    var acceptsLike: (Photo) -> Bool = { _ in true }
    /// ダブルタップでいいねを送る。**いま見ている写真**を渡す。
    /// 解除はしない（`DoubleTapLike`）
    var onDoubleTapLike: (Photo) -> Void = { _ in }
    /// 下のハートを押した（板 14）。**こちらは付け外しの両方**
    /// ——ダブルタップと違い、押し直せば外れるのがボタンの約束
    var onToggleLike: (Photo) -> Void = { _ in }
    /// 共有するページの URL。**個別ページが無い写真は nil**（ボタンを出さない）
    /// ——配るのは画像ではなくページ（`PhotoDetailView` の共有と同じ）
    var shareURL: (Photo) -> URL? = { _ in nil }

    @Environment(\.dismiss) private var dismiss
    /// 拡大と移動（離しても保つ・写真を送ったら戻す）。計算は `ZoomPan`
    @State private var zoom = ZoomPan()
    /// つまんでいる最中の量（離したら `zoom` に畳む）。**`@GestureState`**——着信やシステムの
    /// 身振りで取り消されたときも自動で初期値へ戻る（`@State` だと `onEnded` が来ず量が残り、
    /// 見た目は2倍なのに「拡大していない」扱いになる）
    @GestureState private var pinch: Double = 1
    /// 動かしている最中の量（同上）
    @GestureState private var drag: CGSize = .zero
    /// 画面（写真を置く枠）の大きさ
    @State private var container: CGSize = .zero
    /// 写真ごとの、画面に収めたときの大きさ（移動できる範囲の計算に使う）
    @State private var fitted: [Int: CGSize] = [:]
    /// ハートを弾けさせる回数。値が変わるたびに演出が走る
    @State private var burst = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { offset, photo in
                    let shown = offset == index
                    RemoteImage(url: photo.detailImageURL, contentMode: .fit,
                                onFittedSize: { size in fitted[offset] = size })
                        // **拡大・移動は見ている1枚にだけ掛ける**（送りの途中で隣が拡大されて見えない）
                        .scaleEffect(shown ? zoom.liveScale(pinch: pinch) : 1)
                        .offset(x: shown ? Double(liveOffset.width) : 0, y: shown ? Double(liveOffset.height) : 0)
                        // **両指で広げて拡大。離しても倍率を保つ**（2026-09-30 のレビュー:
                        // 以前は離すと 1 倍に戻り、細部を見ていられなかった）
                        .gesture(
                            MagnificationGesture()
                                .updating($pinch) { value, state, _ in state = value }
                                .onEnded { value in
                                    zoom.endPinch(value, container: container, content: content(for: offset))
                                }
                        )
                        // **拡大中だけ、1本指で写真を動かす。** 等倍のときは受けない（`.subviews`）
                        // ので、横スワイプは下の送り（TabView）に渡る。
                        // **同時に受ける（simultaneous）**——優先（highPriority）にすると2本指で
                        // つまんだときの重心の動きで移動が先に成立し、拡大中につまみ直せなかった
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .updating($drag) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    zoom.endDrag(value.translation, container: container, content: content(for: offset))
                                },
                            including: zoom.isZoomed ? .all : .subviews
                        )
                        // **2回叩いていいね**（Web のモーダルと同じ）。
                        // 拡大中だけは倍率を戻す側に倒す（`DoubleTapLike`）
                        .onTapGesture(count: 2) { handleDoubleTap() }
                        .accessibilityLabel(photo.accessibilityText)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // **拡大中は送りを止める。** 写真を動かしているつもりで隣へ送られない
            // （SwiftUI の身振りの優先だけでは、ページ式 TabView の下のスクロールを止め切れない）
            .scrollDisabled(zoom.isZoomed)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { container = geo.size }
                        .onChange(of: geo.size) { _, size in container = size }
                }
            }
            // **どの経路で送っても倍率と位置を戻す**（横スワイプ・サムネイル）。
            // 拡大したまま次の写真が出ない
            .onChange(of: index) { _, _ in resetZoom() }

            // 下: サムネイルの帯と、題・撮影情報・いいね（板 14）。**下に重ねる**
            VStack(spacing: 14) {
                Spacer()
                thumbnailStrip
                caption
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

            topBar
        }
        .statusBarHidden()
    }

    /// いま見ている写真。送っている途中で添字が外れていたら nil
    private var current: Photo? { DoubleTapLike.shown(photos, at: index) }

    /// いま見ている写真の撮影地（無ければ出さない）
    private var currentPlace: String? {
        let place = (current?.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? nil : place
    }

    /// 上の列（板 14）: 左に閉じる・真ん中に「1枚目 / N」・右に共有。
    ///
    /// **閉じるは左上**（板どおり）。以前は右上だった。
    /// 枠は写真の外（黒地）に出るので、ガラスの丸は付けない（板も素の 44pt）
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Labels.Common.close)

            Spacer()

            // **何枚目か**。点の列より数の方が、20枚あるときに現在地が分かる
            if let position = PhotoMetaLine.viewerPosition(index, of: photos.count) {
                Text(position)
                    .font(JPFont.mono(13))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .allowsHitTesting(false)
            }

            Spacer()

            if let photo = current, let url = shareURL(photo) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("共有", "Share"))
            } else {
                // 真ん中の数をずらさないための空き（閉じるボタンと同じ幅）
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    /// 下の題・撮影地・撮影情報と、いいね（板 14）。
    ///
    /// 撮影地は板に無いが、以前ここに札で出していたので消さない
    /// （題の下に1行で）。**いいねはログイン中だけ**——押しても
    /// 「ログインしてください」しか返らないボタンを写真の上に置かない
    @ViewBuilder
    private var caption: some View {
        if let photo = current {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if !photo.displayTitle.isEmpty {
                        Text(photo.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(2)
                    }
                    if let place = currentPlace {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                            Text(place).lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.72))
                    }
                    if let line = PhotoMetaLine.exifLine(photo.exif) {
                        Text(line)
                            .font(JPFont.mono(11))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .jpPhotoTextShadow()

                if isSignedIn && acceptsLike(photo) {
                    let liked = isLiked(photo)
                    Button {
                        onToggleLike(photo)
                    } label: {
                        Image(systemName: liked ? "heart.fill" : "heart")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("いいね", "Like"))
                    .accessibilityAddTraits(liked ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
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
                            resetZoom()
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
        switch DoubleTapLike.action(isZoomed: zoom.isZoomed, alreadyLiked: isLiked(shown), signedIn: isSignedIn,
                                    acceptsLike: acceptsLike(shown)) {
        case .resetZoom:
            resetZoom()
        case .like:
            onDoubleTapLike(shown)
            showBurst()
        case .burstOnly:
            showBurst()
        }
    }

    /// 動かしている最中の位置（範囲に収める）
    private var liveOffset: CGSize {
        // **つまんでいる最中の倍率で範囲を取る**（縮めている間に写真の端が内側へ入らない）
        zoom.liveOffset(drag: drag, scale: zoom.liveScale(pinch: pinch),
                        container: container, content: content(for: index))
    }

    /// その写真の、画面に収めたときの大きさ（まだ測れていなければ画面の大きさで代える）
    private func content(for offset: Int) -> CGSize {
        fitted[offset] ?? container
    }

    private func resetZoom() {
        zoom.reset()
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
