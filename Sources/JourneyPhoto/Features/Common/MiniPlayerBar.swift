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
/// 地は後ろの写真がそのまま見える薄い黒（ぼかし無し・`glassTint`）。読ませるのは字の影（下の `bar` の注記）。
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
    /// 指で引いている間か。**取り消された（電話が来た等）ときも戻す**ために
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
    /// 全体のバーの地（2026-10-29 判断・owner「背景透過させて、後ろの画像とかが見えるようにしたい」#402）。
    /// 1.1.44 の `jpGlass`（黒 55%＋`.ultraThinMaterial`＋白 10% の縁）は、実機では黒 55% にぼかしの曇りが
    /// 重なってほぼ不透明の黒い板に見えた。**ぼかしを外し**、黒の重ねを薄くして後ろの写真の形と色を見せる。
    /// 読みやすさは字の影（`textShadow…`）で持たせる。`jpGlass` 自体は他の部品が使うので変えない。
    /// 黒は 30%: 見本の絵（run 759・760）で 20〜25% は白い写真の上で地が明るい灰になり、白い字が沈んだ。
    /// 30% でも写真の形と色はそのまま見える（ぼかしが無いので）
    static let glassTint: Double = 0.3
    /// 縁の白（髪の毛線）。明るい写真の上でも形が分かる強さ（板の border 白 12%）
    static let glassBorder: Double = 0.12
    /// 曲名・歌手名・停止ボタンの影は2枚（`SeeThroughTextShadow`）。2026-10-29 判断（run 759 の白・模様の見本の絵で、
    /// 黒 60%・半径 3 の1枚では白い写真の上の歌手名がほぼ消え、模様の上の白い字と曲名がぶつかった）:
    /// - 縁: 黒 60%・半径 2（板の「写真の上の字の影は黒 60%」）。字の輪郭を立てる
    /// - 後光: 黒 70%・半径 6。字の後ろだけを暗く沈め、地全体は暗くしない（写真は見えたまま）。
    ///   run 760 の 45%・半径 8 は細い字の周りに薄く広がるだけで、模様の上の白い字と曲名がまだぶつかった
    static let textShadowOpacity: Double = 0.6
    static let textShadowRadius: CGFloat = 2
    static let textGlowOpacity: Double = 0.7
    static let textGlowRadius: CGFloat = 6
    /// 動かす置き場所の座標の名前
    private static let area = "miniPlayer.area"
    /// 動き始めるまでに指が進む距離（pt）。**長押しは要らない。普通に引けば動く。**
    /// 2026-10-28 判断（owner 実機で動かせなかった）: #395 は 0.2 秒の長押しのあとに引く形
    /// （`LongPressGesture.sequenced(before: DragGesture)`）にしたが、owner は普通に引いて動かせなかった
    /// （長押しが済む前に指が動くと長押しが外れ、引きは始まらない）。再生器の上から始めたスクロールで
    /// 誤って動く件は、始まりの距離を標準（10）より少し大きい 12 にして軽減する。
    /// 停止ボタンのタップは 12pt 動かないので引きにならず、そのまま効く
    static let dragStartDistance: CGFloat = 12

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
    /// 2026-10-28 判断（owner「再生中の音楽の透明をやめちゃったの？好きだったのに」）: #395 の不透明の面をやめ、透ける地に戻した。
    /// 2026-10-29 判断（owner 背景を透かしたい・#402）: ガラス（黒 55%＋ぼかし）は実機でほぼ黒い板に見えたので、
    /// **ぼかしを外して黒 30%・白 12% の縁**にし、後ろの写真の形と色が見えるようにした（`glassTint`）。
    /// - 下の字（説明文など）が透けて曲名と重なる件（#395 より前の白 10%）は、曲名・歌手名・停止ボタンの
    ///   2枚の影（縁＋後光・`SeeThroughTextShadow`）で字を立てて読ませる。重なって読みにくければ再生器を指で動かせる（`MiniPlayerPlacement`）
    /// - 歌手名は白（曲名との差は字の大きさと太さで付ける）。見本の絵（run 759〜761）で、白 60%（faint）・
    ///   白 72%（muted2）は白い写真・模様の上で灰の地に沈んで読めなかった
    /// - 軽くする: ぼかし（material）は使わない。再生器の外の影は置いている間は付けない
    ///   （引いている間だけ・角丸の形にだけ）。地の下に影があると透け感も濁る
    /// - 曲選びの中のバーは板 SongPicker どおり不透明の面（#17171a の段）のまま
    private func bar(_ song: Photo.Song) -> some View {
        HStack(spacing: 10) {
            if inSongPicker {
                info(song)
            } else {
                // 読み上げ: 曲の札（絵と名前）を1つにまとめ、移動の代わりの操作を付ける。停止ボタンは別に読む
                info(song)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("再生中の曲", "Now playing"))
                    .accessibilityValue([song.title, song.artist ?? ""].filter { !$0.isEmpty }
                        .joined(separator: L("、", ", ")))
                    .accessibilityHint(L("ドラッグで移動", "Drag to move"))
                    .accessibilityAction(named: L("上へ移す", "Move up")) { move(up: true) }
                    .accessibilityAction(named: L("下へ移す", "Move down")) { move(up: false) }
                    .accessibilityAction(named: L("左の端へ", "Move to left edge")) { move(to: .leading) }
                    .accessibilityAction(named: L("右の端へ", "Move to right edge")) { move(to: .trailing) }
            }
            Button {
                player.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(WebTheme.foreground)
                    // 透ける地の上でも丸の形が立つよう、曲名と同じ影（曲選びの中は不透明の面なので付けない）
                    .modifier(SeeThroughTextShadow(active: !inSongPicker))
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
        // 全体のバーも同じ形（角 18）で、地は後ろが見える薄い黒（`glassTint`）
        .frame(minHeight: inSongPicker ? Self.pickerBarHeight : nil)
        .background { ground }
    }

    /// 地。曲選びの中は不透明の面、全体のバーは後ろの写真が見える薄い黒（ぼかし無し・`glassTint`）
    @ViewBuilder private var ground: some View {
        let shape = RoundedRectangle(cornerRadius: Self.pickerBarRadius)
        if inSongPicker {
            shape.fill(Self.pickerBarFill)
                .overlay(shape.strokeBorder(WebTheme.hairline, lineWidth: 1))
        } else {
            shape.fill(Color.black.opacity(Self.glassTint))
                .overlay { shape.strokeBorder(Color.white.opacity(Self.glassBorder), lineWidth: 1) }
                // 2026-10-28 判断（再生の重さの担当の手がかり）: #395 は `.shadow(radius: 14)` を再生器の中身ごとに
                // 付けていて、スクロール中に影を描き直していた疑い。影は**角丸の形にだけ**、**引いている間だけ**付ける。
                // 置いている間は影なし（地の下に影があると透け感も濁る）
                .background {
                    if dragging {
                        shape.fill(Color.black.opacity(0.5))
                            .shadow(color: .black, radius: 18, x: 0, y: 10)
                    }
                }
        }
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
                        .foregroundStyle(inSongPicker ? WebTheme.faint : WebTheme.foreground)
                        .lineLimit(1)
                }
            }
            // 透ける地の上の字を読ませる影（全体のバーだけ。曲選びの中は不透明の面なので要らない）
            .modifier(SeeThroughTextShadow(active: !inSongPicker))
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
                // 持ち上げた感じ: 少し縮める（影は `ground` の角丸にだけ・引いている間だけ）。
                // 「動きを減らす」なら縮めない
                .scaleEffect(dragging && !reduceMotion ? Self.liftedScale : 1)
                // 普通に引けば動く（停止ボタンのタップは 12pt 動かないので引きにならず効く）
                .gesture(dragGesture(container: container, size: size))
                // 動き始めた瞬間に軽く震わせる（掴んだ合図）
                .sensoryFeedback(.impact(weight: .light), trigger: dragging) { old, new in !old && new }
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
        // 長押しせずに引く（2026-10-28 判断・`dragStartDistance`）。動かす間に再生器自身が動くので、
        // 量は動かない枠の座標で測る
        DragGesture(minimumDistance: Self.dragStartDistance, coordinateSpace: .named(Self.area))
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

    private func move(to side: MiniPlayerPlacement.Side) {
        withAnimation(settleAnimation) {
            placement.spot = MiniPlayerPlacement.moved(placement.spot, to: side)
        }
    }
}

/// 透ける地の上の曲名・歌手名・停止ボタンの影（全体のバーだけ。曲選びの中は不透明の面なので付けない）。
/// 縁（黒 60%・半径 2）と後光（黒 70%・半径 6）の2枚。値は `MiniPlayerBar.textShadow…`・`textGlow…`
private struct SeeThroughTextShadow: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(active ? MiniPlayerBar.textShadowOpacity : 0),
                    radius: MiniPlayerBar.textShadowRadius, x: 0, y: 1)
            .shadow(color: .black.opacity(active ? MiniPlayerBar.textGlowOpacity : 0),
                    radius: MiniPlayerBar.textGlowRadius, x: 0, y: 0)
    }
}
