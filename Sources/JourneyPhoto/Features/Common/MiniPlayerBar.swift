import SwiftUI

/// 画面の下に出る小さなプレイヤー。**Web の `MiniPlayer` と同じ役目。**
///
/// それまでは `SongRow` が `onDisappear` で止めていた——つまり
/// **曲を鳴らしたまま別の画面へ行けなかった**。Web は移動しても
/// 鳴り続け、下のバーから止められる。アプリだけ止まると、
/// 「写真を見ながら曲を聴く」という同じ体験にならない。
///
/// **出すのは鳴っているときだけ。** 何も鳴っていないのに場所を取らない。
///
/// **全体のバーは指で動かせる**（2026-10-28 owner「再生中の音楽自由に動かせるといいね」）。
/// ホームの「いまの季節のスポット」の説明文の上に重なり、透ける地のせいで下の文字と曲名が
/// 重なって読めなかった。置き場所の決まりは `MiniPlayerPlacement`。
/// 曲選びの中のバーはシートの中に据えるので動かさない（下へ引くとシートを閉じる操作とぶつかる）
struct MiniPlayerBar: View {

    /// 「曲を選ぶ」のシートの中のバー（板 23）。曲選びで鳴らした曲なら1行目が
    /// 「曲名 · 試し聴き中」になる。**シートは下の全体のバーを覆う**ので、曲選びは自分のシートの中に
    /// このバーを置く。どちらのバーに出すかは `SongPickerText.showsBar`
    var inSongPicker = false

    @ObservedObject private var player = MusicPreviewPlayer.shared
    @ObservedObject private var placement = MiniPlayerPlacementStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 動かしている間の量（離したら 0 に戻す）
    @State private var dragOffset = CGSize.zero
    /// 指が触れて動かしている間か。**取り消された（電話が来た等）ときも戻す**ために
    /// `@GestureState` で持つ（取り消しでは `onEnded` が呼ばれない）
    @GestureState private var dragging = false
    /// 再生器の高さ（文字の大きさで変わる）。範囲の計算に使う
    @State private var barHeight: CGFloat = MiniPlayerBar.pickerBarHeight

    /// 曲選びの中のバー（v2 SongPicker）
    static let pickerBarHeight: CGFloat = 60
    static let pickerBarRadius: CGFloat = 18
    @MainActor static var pickerBarFill: Color { RaisedTile.fill }

    /// 動かしている間の縮み（持ち上げた感じ）。「動きを減らす」がオンなら縮めない
    static let liftedScale: CGFloat = 0.96
    /// 動かす置き場所の座標の名前
    private static let area = "miniPlayer.area"

    var body: some View {
        if let song = player.playingSong,
           SongPickerText.showsBar(playingFrom: player.origin, inSongPicker: inSongPicker) {
            if inSongPicker {
                bar(song)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("mini.player")
            } else {
                floating(song)
            }
        }
    }

    /// 曲の絵・曲名・歌手名と停止ボタン。
    /// 2026-10-28 判断: 地は**不透明の一段浮かせた面**（`RaisedTile.fill`・板 SongPicker の帯 #17171a と
    /// 同じ段）。前の全体のバーは白 10%（`WebTheme.raised`）で、下の文字が透けて曲名と重なっていた
    private func bar(_ song: Photo.Song) -> some View {
        HStack(spacing: 10) {
            if inSongPicker {
                info(song)
            } else {
                // 読み上げ: 曲の札（絵と名前）を1つにまとめ、移動の代わりの操作を付ける。停止ボタンは別に読む
                info(song)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("再生中の曲。ドラッグで移動", "Now playing. Drag to move"))
                    .accessibilityValue([song.title, song.artist ?? ""].filter { !$0.isEmpty }.joined(separator: "、"))
                    .accessibilityAction(named: L("上へ移す", "Move up")) { move(up: true) }
                    .accessibilityAction(named: L("下へ移す", "Move down")) { move(up: false) }
            }
            Button {
                player.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(WebTheme.foreground)
                    // 押せる範囲は 44pt（見た目はそのまま）
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("止める", "Stop"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        // 曲選びの中のバーは v2 SongPicker の形（高さ 60・角 18・地 #1A1A1C・縁は白 8%）。
        // 全体のバーも同じ形・同じ地。縁だけ白 12%（写真の上に浮かぶので境目を見せる）
        .frame(minHeight: inSongPicker ? Self.pickerBarHeight : nil)
        .background(Self.pickerBarFill, in: RoundedRectangle(cornerRadius: Self.pickerBarRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.pickerBarRadius)
            .strokeBorder(inSongPicker ? WebTheme.hairline : WebTheme.border, lineWidth: 1))
    }

    private func info(_ song: Photo.Song) -> some View {
        HStack(spacing: 10) {
            if let artwork = song.artworkURL {
                RemoteImage(url: artwork)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(SongPickerText.barTitle(song.title, playingFrom: player.origin,
                                             inSongPicker: inSongPicker))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                if let artist = song.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: WebTheme.minTapTarget)
    }

    /// 全体のバー。指で動かせて、離すと左右の近い端へ寄る（`MiniPlayerPlacement`）
    private func floating(_ song: Photo.Song) -> some View {
        GeometryReader { proxy in
            let container = proxy.size
            let size = CGSize(width: MiniPlayerPlacement.barWidth(container: container), height: barHeight)
            let base = MiniPlayerPlacement.center(of: placement.spot, container: container, barSize: size)
            bar(song)
                .frame(width: size.width)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { barHeight = $0 }
                // 再生器全体を1つの入れ物にして道しるべを付ける（中の曲の札・停止ボタンは別々に読む）
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("mini.player")
                // 持ち上げた感じ: 少し縮めて影を濃く。「動きを減らす」なら縮めない
                .scaleEffect(dragging && !reduceMotion ? Self.liftedScale : 1)
                .shadow(color: .black.opacity(dragging ? 0.7 : 0.5), radius: dragging ? 22 : 14,
                        x: 0, y: dragging ? 14 : 8)
                // 押すとぶつからないよう、少し動いてから動かす（停止ボタンのタップは指が動かないので効く）
                .gesture(dragGesture(container: container, size: size))
                .position(x: base.x + dragOffset.width, y: base.y + dragOffset.height)
        }
        .coordinateSpace(.named(Self.area))
        // 取り消された（`onEnded` が来ない）ときは元の場所へ戻す
        .onChange(of: dragging) { _, active in
            guard !active, dragOffset != .zero else { return }
            withAnimation(settleAnimation) { dragOffset = .zero }
        }
    }

    private func dragGesture(container: CGSize, size: CGSize) -> some Gesture {
        // 動かす間に再生器自身が動くので、量は動かない枠の座標で測る
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.area))
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                let outcome = MiniPlayerPlacement.settle(from: placement.spot,
                                                         translation: value.translation,
                                                         predicted: value.predictedEndTranslation,
                                                         container: container, barSize: size)
                switch outcome {
                case .dismiss:
                    // 停止ボタンと同じ結果。置き場所は覚えたまま（次の曲も同じ所に出る）
                    dragOffset = .zero
                    player.stop()
                case .place(let spot):
                    withAnimation(settleAnimation) {
                        placement.spot = spot
                        dragOffset = .zero
                    }
                }
            }
    }

    private var settleAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
    }

    private func move(up: Bool) {
        withAnimation(settleAnimation) {
            placement.spot = MiniPlayerPlacement.moved(placement.spot, up: up)
        }
    }
}
