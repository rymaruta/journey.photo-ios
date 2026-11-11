import SwiftUI
import AVFoundation
import UIKit

/// 動画の切り取り（2026-11-09 owner「ストーリーをインスタと遜色なく」の第1弾）。
///
/// 動画を**再生しながら**、始点・終点のつまみで残す範囲を選ぶ。範囲の決まり（最大 60 秒・最短 1 秒・
/// 枠が 60 秒を超えると反対側がついてくる）は `StoryVideoTrim`（画面から出してある）。
///  - 帯は**動画全体**のサムネイル（`StoryVideoPipeline.filmstrip`）。選んだ範囲の外は暗くする
///  - つまみを動かしている間は**その時刻の絵**を出す（再生は止める）。離したら範囲の頭から繰り返し再生
///  - 数十分の動画は 1pt が数秒になるので、**「−1秒／＋1秒」**で細かく合わせられる（読み上げの増減も同じ）
///  - 音は既定で止めてある（作る画面で曲が鳴っていることがある）。スピーカーで入れる
///
/// **2026-11-12 判断（設計の案「ストーリーのデザイン 残り」02・作る画面 v2 の文字の上の段に合わせる）**:
///  - 動画は作る画面と同じく**上の面いっぱい**（下の角 24）に敷き、上の段（キャンセル 17・題 17/600・完了 17/700）を
///    動画の上に重ねる。以前は小さな角丸の窓に収まり、黒い余白が多かった
///  - 下の黒地に「長さ（白の 20pt）・範囲と全体（12pt の注記）」→ 帯 → 「−1秒／＋1秒」のチップ（見た目 32・当たり 44）
///  - 長い説明の文は出さない。**60 秒を超える動画のときだけ**「全体 2:24 · 60秒まで」と短く（`StoryVideoTrim.totalNote`）
///  - 長さの数は白（数は合図ではない・板 v2）。以前は真鍮だった
///  - つまみを動かしている間はつまみの上に「0:12.4」の吹き出し。60 秒の枠に当たったら枠の外に白い光の縁と「60秒まで」
///  - 選んだ枠を掴むと、長さを変えずに範囲ごと動かせる（`StoryVideoTrim.shift`）
///  - 帯の読み込み中は光が流れる骨組み（動きを減らす設定では止めた灰色）。動画を開けないときは空の状態の型で理由と次の一手
///  - 色: 帯は写真（サムネイル）の上なので、つまみ・選んだ範囲の枠は白（真鍮は黒地の上だけ・墨の溝）
///
/// 書き出しは `StoryVideoPipeline.export` が `StoryVideoClip.trim` の範囲だけを切って行う。
struct StoryVideoTrimSheet: View {

    let clip: StoryVideoClip
    /// 作る画面の何枚目か（「1 / 2」・写真の右下）。1枚だけのときは nil
    var positionLabel: String?
    /// 「別の動画を選ぶ」（開けなかったとき）。シートを閉じてから呼ぶ側が写真選びを開く。nil なら出さない
    var onPickAnother: (() -> Void)?
    /// 「完了」で、選んだ範囲を渡す
    let onDone: (StoryVideoTrim) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trim: StoryVideoTrim
    @StateObject private var playback: StoryTrimPlayback
    /// 帯のサムネイル（取れるまで空・取れなかったコマは nil）
    @State private var thumbs: [UIImage?] = []
    /// 帯を取り終えたか（骨組みを出すのは取り終えるまで）
    @State private var stripLoaded = false
    /// 読み込みの回（「もう一度」で取り直す）
    @State private var loadRound = 0
    /// いま動かしているつまみと、動かし始めの時刻
    @State private var dragging: Handle?
    @State private var dragOrigin: Double = 0
    /// 指を離したら再生に戻すか（動かし始めに再生中だったか）
    @State private var resumeAfterDrag = true
    /// 60 秒の枠に当たった印（光の縁と「60秒まで」）を出しているか
    @State private var limitShown = false
    @State private var limitTask: Task<Void, Never>?
    /// 触覚の合図（つまみを掴んだ・60 秒の枠に当たった）
    @State private var grabTick = 0
    @State private var limitTick = 0

    private enum Handle { case start, end, range }

    /// 帯のサムネイルの数・高さ・つまみの幅・帯の角
    static let tileCount = 10
    static let stripHeight: CGFloat = 56
    static let handleWidth: CGFloat = 16
    static let stripRadius: CGFloat = 10
    /// 「−1秒／＋1秒」のチップの見た目の高さ（当たりは 44）
    nonisolated static let chipHeight: CGFloat = 32
    private static let space = "storyTrimStrip"

    init(clip: StoryVideoClip, positionLabel: String? = nil, onPickAnother: (() -> Void)? = nil,
         onDone: @escaping (StoryVideoTrim) -> Void) {
        self.clip = clip
        self.positionLabel = positionLabel
        self.onPickAnother = onPickAnother
        self.onDone = onDone
        _trim = State(initialValue: clip.trim)
        _playback = StateObject(wrappedValue: StoryTrimPlayback(url: clip.url, start: clip.trim.start, end: clip.trim.end))
    }

    /// 何枚目かの札（「1 / 2」）。1枚だけなら出さない
    nonisolated static func positionLabel(index: Int, count: Int) -> String? {
        guard count > 1, index >= 0, index < count else { return nil }
        return "\(index + 1) / \(count)"
    }

    /// 動画を開けない（長さが読めない・帯の絵が1コマも取れない）。`StoryVideoTrim.cannotOpen`
    private var openFailed: Bool {
        StoryVideoTrim.cannotOpen(total: trim.total, framesRead: thumbs.compactMap { $0 }.count,
                                  framesAsked: thumbs.count, stripLoaded: stripLoaded)
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebTheme.background.ignoresSafeArea()
            if openFailed {
                failedState
            } else {
                VStack(spacing: 0) {
                    preview
                    summary
                        .padding(.horizontal, JPSpace.m)
                        .padding(.top, JPSpace.m)
                    strip
                        .frame(height: Self.stripHeight + 8)
                        .padding(.horizontal, JPSpace.m)
                        .padding(.top, JPSpace.s)
                    fineAdjust
                        .padding(.horizontal, JPSpace.m)
                        .padding(.top, JPSpace.s)
                        .padding(.bottom, JPSpace.s)
                }
            }
            topBar
        }
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: grabTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: limitTick)
        .onAppear { playback.begin() }
        .onDisappear { playback.stop() }
        // 帯のサムネイル。**動画全体を `tileCount` 等分**した各区間の真ん中を、小さく・近いキーフレームで取る
        .task(id: loadRound) {
            stripLoaded = false
            let images = await StoryVideoPipeline.filmstrip(of: clip, count: Self.tileCount)
            guard !Task.isCancelled else { return }
            thumbs = images
            stripLoaded = true
        }
    }

    // MARK: - 上の段

    /// 作る画面の文字の上の段と同じ（キャンセル 17・題 17/600・完了 17/700）。動画の上なので白と影
    private var topBar: some View {
        ZStack {
            Text(L("動画を切り取る", "Trim video"))
                .font(JPFont.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(Labels.Common.cancel) { dismiss() }
                    .font(Font.body)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .padding(.horizontal, JPSpace.xs)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("story.trim.cancel")
                Spacer()
                Button(L("完了", "Done")) {
                    onDone(trim)
                    dismiss()
                }
                .font(Font.body.weight(.bold))
                .frame(minHeight: WebTheme.minTapTarget)
                .padding(.horizontal, JPSpace.xs)
                .contentShape(Rectangle())
                .disabled(openFailed)
                .opacity(openFailed ? 0.3 : 1)
                .accessibilityIdentifier("story.trim.done")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .jpPhotoTextShadow()
        .padding(.horizontal, JPSpace.xs)
        .padding(.top, JPSpace.xs)
    }

    // MARK: - 再生

    /// 動画（上の面いっぱい・下の角 24）。**押すと止める・再生する**。左下に音、右下に何枚目か
    private var preview: some View {
        ZStack {
            StoryVideoSurface(player: playback.player)
            // 上の段の字を読めるように（作る画面と同じ 50% → 0 の暗がり）
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // 止めているとき（つまみを動かしている間は除く）は真ん中に再生の丸
            if !playback.isPlaying && dragging == nil {
                Image(systemName: "play.fill")
                    .font(Font.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .jpGlass(in: Circle())
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { playback.toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(playback.isPlaying ? L("止める", "Pause") : L("再生", "Play"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { playback.toggle() }
        .accessibilityIdentifier("story.trim.preview")
        .overlay(alignment: .bottomLeading) {
            Button { playback.isMuted.toggle() } label: {
                Image(systemName: playback.isMuted ? "speaker.slash" : "speaker.wave.2")
                    .font(Font.body)
                    .foregroundStyle(.white)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .jpGlass(in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(playback.isMuted ? L("音を入れる", "Turn sound on") : L("音を止める", "Turn sound off"))
        }
        .overlay(alignment: .bottomTrailing) {
            if let positionLabel {
                Text(positionLabel)
                    .font(JPFont.mono(12, medium: true, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .jpGlass(in: Capsule())
                    .padding(12)
                    .padding(.bottom, 7)
                    .accessibilityLabel(L("\(positionLabel) 枚目", "Item \(positionLabel)"))
            }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: JPRadius.xl, bottomTrailingRadius: JPRadius.xl))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
    }

    /// 「1:00　0:12–1:12　全体 2:24 · 60秒まで」。長さは白の 20pt（数は合図ではないので白）、範囲と全体は 12pt の注記
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(StoryVideoTrim.label(trim.length))
                .font(JPFont.mono(20, relativeTo: .title3))
                .foregroundStyle(.white)
            Text(trim.rangeLabel)
                .font(JPFont.mono(12, relativeTo: .caption))
                .foregroundStyle(WebTheme.text3)
            Spacer(minLength: 0)
            Text(trim.totalNote)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trim.spokenSummary)
        .accessibilityIdentifier("story.trim.summary")
    }

    // MARK: - 開けないとき

    /// 動画を開けない（iCloud から読み込めなかった・形式に対応していない）。以前は窓が黒いまま何も言わなかった。
    /// 空の状態の型で理由と次の一手（写真の無い画面の主ボタン＝真鍮に墨・「もう一度」は線のボタン）
    private var failedState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if let onPickAnother {
                EmptyState(title: L("この動画を開けません", "Can't open this video"),
                           message: StoryVideoTrim.cannotOpenMessage,
                           actionTitle: L("別の動画を選ぶ", "Choose another video"),
                           actionIdentifier: "story.trim.pickAnother") {
                    onPickAnother()
                    dismiss()
                }
            } else {
                EmptyState(title: L("この動画を開けません", "Can't open this video"),
                           message: StoryVideoTrim.cannotOpenMessage)
            }
            RetryButton { reload() }
                .accessibilityIdentifier("story.trim.retry")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JPSpace.m)
        .accessibilityIdentifier("story.trim.failed")
    }

    /// 「もう一度」: 再生器を作り直し、帯を取り直す
    private func reload() {
        thumbs = []
        playback.reload()
        loadRound += 1
    }

    // MARK: - 帯とつまみ

    private var strip: some View {
        GeometryReader { geometry in
            let inset = Self.handleWidth
            let barWidth = max(geometry.size.width - inset * 2, 1)
            let startX = StoryVideoTrim.position(of: trim.start, total: trim.total, width: barWidth)
            let endX = StoryVideoTrim.position(of: trim.end, total: trim.total, width: barWidth)
            let tileWidth = barWidth / CGFloat(Self.tileCount)
            // `.frame(width:)` の模型は Double・`barWidth` などは CGFloat。`max` の引数を1つの型に決めておく
            // （CI: conflicting arguments to generic parameter 'T' ('CGFloat' vs. 'Double')）
            let rightDimWidth: CGFloat = max(barWidth - endX, 0)
            let selectedWidth: CGFloat = max(endX - startX, 1)
            // 模型の `.offset`・`.frame` は Double、実 SwiftUI は CGFloat。**算術は先に CGFloat の変数に決めて渡す**
            // （CI: ambiguous use of operator '-'）
            let rightDimX: CGFloat = inset + endX
            let selectedX: CGFloat = inset + startX
            let playheadX: CGFloat = inset + StoryVideoTrim.position(of: playback.playhead, total: trim.total,
                                                                    width: barWidth) - 1
            let startHandleX: CGFloat = inset + startX - Self.handleWidth
            let stripHeightPlus8: CGFloat = Self.stripHeight + 8
            let stripHeightPlus4: CGFloat = Self.stripHeight + 4
            let loading = !stripLoaded
            ZStack(alignment: .topLeading) {
                // 動画全体のサムネイル（読み込み中は光が流れる骨組み）
                HStack(spacing: 0) {
                    ForEach(0..<Self.tileCount, id: \.self) { index in
                        tile(index, width: tileWidth)
                    }
                }
                .frame(width: barWidth, height: Self.stripHeight)
                .overlay { if loading { StoryTrimShimmer(animated: !reduceMotion) } }
                .clipShape(RoundedRectangle(cornerRadius: Self.stripRadius))
                .offset(x: inset, y: 4)
                .accessibilityHidden(true)
                if !loading {
                    // 選んだ範囲の外を暗くする
                    Rectangle().fill(Color.black.opacity(0.62))
                        .frame(width: startX, height: Self.stripHeight)
                        .offset(x: inset, y: 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    Rectangle().fill(Color.black.opacity(0.62))
                        .frame(width: rightDimWidth, height: Self.stripHeight)
                        .offset(x: rightDimX, y: 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    // 選んだ範囲の枠。**掴むと範囲ごと動かせる**。60 秒の枠に当たったら外に白い光の縁
                    Rectangle().strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: selectedWidth, height: stripHeightPlus4)
                        .background(Color.clear)
                        .overlay {
                            if limitShown {
                                Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 6)
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        .offset(x: selectedX, y: 2)
                        .gesture(rangeDrag(barWidth: barWidth))
                        .accessibilityHidden(true)
                    // いまの再生位置（範囲の中だけ・つまみを動かしている間は出さない）
                    if dragging == nil, playback.playhead >= trim.start, playback.playhead <= trim.end {
                        Rectangle().fill(Color.white)
                            .frame(width: 2, height: stripHeightPlus8)
                            .shadow(color: Color.black.opacity(0.6), radius: 2)
                            .offset(x: playheadX)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    handle(.start, x: startHandleX, barWidth: barWidth)
                    handle(.end, x: rightDimX, barWidth: barWidth)
                    // つまみの上の吹き出し（動かしている間は時刻・60 秒の枠に当たったら「60秒まで」）
                    if let bubble = bubbleText {
                        let anchor: CGFloat = dragging == .end || (dragging == nil && limitShown) ? rightDimX : selectedX
                        let bubbleX: CGFloat = min(max(anchor - 40, 0), max(geometry.size.width - 80, 0))
                        Text(bubble)
                            .font(JPFont.mono(13, medium: true, relativeTo: .footnote))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(width: 80, height: 30)
                            .jpGlass(in: Capsule())
                            .offset(x: bubbleX, y: -40)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .accessibilityIdentifier("story.trim.bubble")
                    }
                }
            }
            .coordinateSpace(.named(Self.space))
        }
    }

    /// 吹き出しの字。動かしている間は時刻（「0:12.4」）、60 秒の枠に当たったら「60秒まで」
    private var bubbleText: String? {
        if limitShown { return L("60秒まで", "Up to 60s") }
        switch dragging {
        case .start?, .range?: return StoryVideoTrim.preciseLabel(trim.start)
        case .end?: return StoryVideoTrim.preciseLabel(trim.end)
        case nil: return nil
        }
    }

    @ViewBuilder
    private func tile(_ index: Int, width: CGFloat) -> some View {
        if index < thumbs.count, let image = thumbs[index] {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: Self.stripHeight)
                .clipped()
        } else {
            Rectangle().fill(WebTheme.sheet)
                .frame(width: width, height: Self.stripHeight)
        }
    }

    /// つまみ 1 つ。見た目は幅 16 の白い板（中に墨の溝）、**当たりは幅 44**（見た目の外へ 14 ずつ）。
    /// 読み上げは「開始位置・0:12」で、増やす・減らすで 1 秒ずつ動く
    private func handle(_ which: Handle, x: CGFloat, barWidth: CGFloat) -> some View {
        let time = which == .start ? trim.start : trim.end
        let hit: CGFloat = WebTheme.minTapTarget
        let fullHeight: CGFloat = Self.stripHeight + 8
        let handleOffset: CGFloat = x - (hit - Self.handleWidth) / 2
        return ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .frame(width: Self.handleWidth, height: fullHeight)
            RoundedRectangle(cornerRadius: 1)
                .fill(WebTheme.accentText)
                .frame(width: 2, height: 20)
        }
        .frame(width: hit, height: fullHeight)
        .contentShape(Rectangle())
        .offset(x: handleOffset)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    if dragging != which {
                        beginDrag(which, origin: time)
                    }
                    let delta = Double(value.translation.width / barWidth) * trim.total
                    let before = trim.length
                    if which == .start { trim.setStart(dragOrigin + delta) } else { trim.setEnd(dragOrigin + delta) }
                    noteLimit(before: before)
                    playback.show(at: which == .start ? trim.start : trim.end)
                }
                .onEnded { _ in endDrag() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(which == .start ? L("開始位置", "Start") : L("終了位置", "End"))
        .accessibilityValue(StoryVideoTrim.label(time))
        .accessibilityHint(L("増やす・減らすで1秒ずつ動かします", "Adjust to move by one second"))
        .accessibilityAdjustableAction { direction in
            nudge(which, by: direction == .increment ? StoryVideoTrim.nudgeStep : -StoryVideoTrim.nudgeStep)
        }
        .accessibilityIdentifier(which == .start ? "story.trim.start" : "story.trim.end")
    }

    /// 選んだ枠を掴んで、長さを変えずに範囲ごと動かす
    private func rangeDrag(barWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragging != .range { beginDrag(.range, origin: trim.start) }
                let delta = Double(value.translation.width / barWidth) * trim.total
                trim.shift(toStart: dragOrigin + delta)
                playback.show(at: trim.start)
            }
            .onEnded { _ in endDrag() }
    }

    private func beginDrag(_ which: Handle, origin: Double) {
        dragging = which
        dragOrigin = origin
        resumeAfterDrag = playback.isPlaying
        playback.pause()
        grabTick += 1
    }

    private func endDrag() {
        dragging = nil
        playback.setRange(start: trim.start, end: trim.end, playing: resumeAfterDrag)
    }

    /// 60 秒の枠に当たった（反対側が引かれた）瞬間に触覚1回と、光の縁・「60秒まで」を少しの間
    private func noteLimit(before: Double) {
        guard trim.atLimit, before < StoryVideoTrim.maxLength - 0.001 else { return }
        limitTick += 1
        limitTask?.cancel()
        limitShown = true
        limitTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            limitShown = false
        }
    }

    // MARK: - 細かい合わせ

    /// 「− 1秒 ＋ 1秒 開始 ……… 終了 − 1秒 ＋ 1秒」。**長い動画は帯の 1pt が数秒**なので、1 秒ずつの合わせを置く。
    /// 見た目 32 のチップ・当たりは 44。大きい文字で並びきらなければ2段に
    private var fineAdjust: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                stepButton(symbol: "minus", which: .start)
                stepButton(symbol: "plus", which: .start)
                stepLabel(.start)
                Spacer(minLength: JPSpace.xs)
                stepLabel(.end)
                stepButton(symbol: "minus", which: .end)
                stepButton(symbol: "plus", which: .end)
            }
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                HStack(spacing: 6) {
                    stepLabel(.start)
                    stepButton(symbol: "minus", which: .start)
                    stepButton(symbol: "plus", which: .start)
                }
                HStack(spacing: 6) {
                    stepLabel(.end)
                    stepButton(symbol: "minus", which: .end)
                    stepButton(symbol: "plus", which: .end)
                }
            }
        }
    }

    private func stepLabel(_ which: Handle) -> some View {
        Text(which == .start ? L("開始", "Start") : L("終了", "End"))
            .font(JPFont.caption)
            .foregroundStyle(WebTheme.text3)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }

    /// 「− 1秒」「＋ 1秒」のチップ（白 12% の地・13pt の等幅数字）。読み上げは「開始を1秒戻す」
    private func stepButton(symbol: String, which: Handle) -> some View {
        let name = which == .start ? L("開始", "Start") : L("終了", "End")
        let back = symbol == "minus"
        let label = back ? L("\(name)を1秒戻す", "Move \(name.lowercased()) 1 second earlier")
                         : L("\(name)を1秒進める", "Move \(name.lowercased()) 1 second later")
        return Button {
            nudge(which, by: back ? -StoryVideoTrim.nudgeStep : StoryVideoTrim.nudgeStep)
        } label: {
            Text(back ? L("− 1秒", "− 1s") : L("＋ 1秒", "+ 1s"))
                .font(JPFont.mono(13, relativeTo: .footnote))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, JPSpace.s)
                .frame(minHeight: Self.chipHeight)
                .background(Color.white.opacity(0.12), in: Capsule())
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(StoryVideoTrim.label(which == .start ? trim.start : trim.end))
    }

    /// 1 秒ずつ動かして、その時刻の絵を出し、範囲の頭から再生し直す
    private func nudge(_ which: Handle, by delta: Double) {
        let before = trim.length
        if which == .start { trim.nudgeStart(by: delta) } else { trim.nudgeEnd(by: delta) }
        noteLimit(before: before)
        playback.setRange(start: trim.start, end: trim.end, playing: playback.isPlaying)
    }
}

/// 帯の読み込み中の骨組み（光が左から右へ 1.6 秒で流れる・設計の案 02）。**動きを減らす設定では止めた灰色**。
/// 2026-11-12 判断: 共通の `JPLoadingState` は光を流さない決まりだが、この帯は案が「光が流れる骨組み」を指定している
/// （灰色の四角が並ぶだけだと、帯が壊れているように見えた）。動きを減らす設定の人には流さない
private struct StoryTrimShimmer: View {
    let animated: Bool

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation) { context in
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let lightX: CGFloat = width * CGFloat(StoryVideoTrim.shimmerPhase(at: context.date))
                        ZStack(alignment: .leading) {
                            WebTheme.sheet
                            LinearGradient(colors: [WebTheme.sheet, Color.white.opacity(0.08), WebTheme.sheet],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: width)
                                .offset(x: lightX)
                        }
                        .clipped()
                    }
                }
            } else {
                WebTheme.sheet
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 切り取りの再生（範囲の中だけを繰り返す）。**画面から出した入れ物**——時刻の見張りの閉包が
/// 画面の値（`@State`）を掴まないように、見張りも再生器もここが持つ。`stop()` で必ず外す（`deinit` も保険）
@MainActor
final class StoryTrimPlayback: ObservableObject {

    let player: AVPlayer
    /// いまの位置（元の動画の秒）
    @Published private(set) var playhead: Double
    @Published private(set) var isPlaying = false
    /// 既定は止めてある（作る画面で曲が鳴っていることがある）
    @Published var isMuted = true {
        didSet { player.isMuted = isMuted }
    }

    private var rangeStart: Double
    private var rangeEnd: Double
    private var observer: Any?

    private let url: URL

    init(url: URL, start: Double, end: Double) {
        self.url = url
        self.player = AVPlayer(url: url)
        self.rangeStart = start
        self.rangeEnd = end
        self.playhead = start
        self.player.isMuted = true
    }

    deinit {
        if let observer { player.removeTimeObserver(observer) }
    }

    /// 画面が出たとき: 範囲の頭へ置いて鳴らし始める。見張りは 1 つだけ
    func begin() {
        guard observer == nil else { return }
        seek(to: rangeStart)
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.tick(seconds) }
        }
        play()
    }

    /// 画面が消えるとき: 止めて見張りを外す
    func stop() {
        player.pause()
        isPlaying = false
        if let observer {
            player.removeTimeObserver(observer)
            self.observer = nil
        }
    }

    /// 「もう一度」（開けなかったとき）: 項目を作り直して範囲の頭から
    func reload() {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        seek(to: rangeStart)
        play()
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            // 範囲の終わりで止まっていたら頭から
            if playhead >= rangeEnd - 0.05 { seek(to: rangeStart) }
            play()
        }
    }

    /// つまみを動かしている間: その時刻の絵を出す（再生は呼ぶ側が止めてある）
    func show(at seconds: Double) {
        seek(to: seconds)
    }

    /// 範囲が決まった（つまみを離した・1 秒ずつ動かした）: 頭から繰り返す
    func setRange(start: Double, end: Double, playing: Bool) {
        rangeStart = start
        rangeEnd = end
        seek(to: start)
        if playing { play() } else { pause() }
    }

    private func seek(to seconds: Double) {
        playhead = seconds
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        // 頭出しは正確に（既定は近いキーフレームで、始点の絵がずれる）
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 0.05 秒ごと。範囲の終わりに来たら頭へ戻す（繰り返し）。範囲より前にいたら頭へ寄せる
    private func tick(_ seconds: Double) {
        guard isPlaying else { return }
        if seconds >= rangeEnd - 0.03 || seconds < rangeStart - 0.25 {
            seek(to: rangeStart)
        } else {
            playhead = seconds
        }
    }
}
