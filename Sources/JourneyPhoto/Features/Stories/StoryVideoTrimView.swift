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
///  - 色: 帯は写真（サムネイル）の上なので、つまみ・選んだ範囲の枠は白（真鍮は黒地の上だけ・墨の溝）。長さの字は黒地の上なので真鍮
///
/// 書き出しは `StoryVideoPipeline.export` が `StoryVideoClip.trim` の範囲だけを切って行う。
struct StoryVideoTrimSheet: View {

    let clip: StoryVideoClip
    /// 「完了」で、選んだ範囲を渡す
    let onDone: (StoryVideoTrim) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var trim: StoryVideoTrim
    @StateObject private var playback: StoryTrimPlayback
    /// 帯のサムネイル（取れるまで空・取れなかったコマは nil）
    @State private var thumbs: [UIImage?] = []
    /// いま動かしているつまみと、動かし始めの時刻
    @State private var dragging: Handle?
    @State private var dragOrigin: Double = 0
    /// 指を離したら再生に戻すか（動かし始めに再生中だったか）
    @State private var resumeAfterDrag = true
    /// 触覚の合図（つまみを掴んだ・60 秒の枠に当たった）
    @State private var grabTick = 0
    @State private var limitTick = 0

    private enum Handle { case start, end }

    /// 帯のサムネイルの数・高さ・つまみの幅
    static let tileCount = 10
    static let stripHeight: CGFloat = 56
    static let handleWidth: CGFloat = 16
    private static let space = "storyTrimStrip"

    init(clip: StoryVideoClip, onDone: @escaping (StoryVideoTrim) -> Void) {
        self.clip = clip
        self.onDone = onDone
        _trim = State(initialValue: clip.trim)
        _playback = StateObject(wrappedValue: StoryTrimPlayback(url: clip.url, start: clip.trim.start, end: clip.trim.end))
    }

    var body: some View {
        VStack(spacing: 14) {
            preview
            summary
            strip
                .frame(height: Self.stripHeight + 8)
            fineAdjust
            Text(note)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WebTheme.background)
        .foregroundStyle(.white)
        .webScreen()
        .navigationTitle(L("動画を切り取る", "Trim video"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("完了", "Done")) {
                    onDone(trim)
                    dismiss()
                }
                .accessibilityIdentifier("story.trim.done")
            }
        }
        .sensoryFeedback(.selection, trigger: grabTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: limitTick)
        .onAppear { playback.begin() }
        .onDisappear { playback.stop() }
        // 帯のサムネイル。**動画全体を `tileCount` 等分**した各区間の真ん中を、小さく・近いキーフレームで取る
        .task {
            let images = await StoryVideoPipeline.filmstrip(of: clip, count: Self.tileCount)
            if !Task.isCancelled { thumbs = images }
        }
    }

    // MARK: - 再生

    /// 動画の再生（枠いっぱいに敷く面を、動画の縦横比で収める）。**押すと止める・再生する**
    private var preview: some View {
        let aspect: Double = clip.size.width > 0 && clip.size.height > 0 ? Double(clip.size.width / clip.size.height) : 9.0 / 16.0
        return StoryVideoSurface(player: playback.player)
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
            .overlay(alignment: .bottomLeading) {
                Button { playback.isMuted.toggle() } label: {
                    Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .jpGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(playback.isMuted ? L("音を入れる", "Turn sound on") : L("音を止める", "Turn sound off"))
            }
            .overlay(alignment: .bottomTrailing) {
                Button { playback.toggle() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .jpGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(playback.isPlaying ? L("止める", "Pause") : L("再生", "Play"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 「0:12 – 1:12 · 1:00」（等幅の数字）
    private var summary: some View {
        HStack(spacing: 8) {
            Text("\(StoryVideoTrim.label(trim.start)) – \(StoryVideoTrim.label(trim.end))")
                .font(JPFont.mono(15))
                .foregroundStyle(.white)
            Text(L("長さ \(StoryVideoTrim.label(trim.length))", "Length \(StoryVideoTrim.label(trim.length))"))
                .font(JPFont.mono(15))
                .foregroundStyle(WebTheme.accent)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trim.spokenSummary)
        .accessibilityIdentifier("story.trim.summary")
    }

    private var note: String {
        trim.total > StoryVideoTrim.maxLength
            ? L("この動画は\(StoryVideoTrim.label(trim.total))あります。残せるのは最大60秒です。両端のつまみで範囲を選びます",
                "This video is \(StoryVideoTrim.label(trim.total)) long. You can keep up to 60 seconds. Drag the handles to choose")
            : L("両端のつまみを動かして、残す所を選びます。最短1秒",
                "Drag the handles to choose the part to keep. At least 1 second")
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
            ZStack(alignment: .topLeading) {
                // 動画全体のサムネイル
                HStack(spacing: 0) {
                    ForEach(0..<Self.tileCount, id: \.self) { index in
                        tile(index, width: tileWidth)
                    }
                }
                .frame(width: barWidth, height: Self.stripHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .offset(x: inset, y: 4)
                .accessibilityHidden(true)
                // 選んだ範囲の外を暗くする
                Rectangle().fill(Color.black.opacity(0.62))
                    .frame(width: startX, height: Self.stripHeight)
                    .offset(x: inset, y: 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Rectangle().fill(Color.black.opacity(0.62))
                    .frame(width: rightDimWidth, height: Self.stripHeight)
                    .offset(x: inset + endX, y: 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                // 選んだ範囲の枠
                Rectangle().strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: selectedWidth, height: Self.stripHeight + 4)
                    .offset(x: inset + startX, y: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                // いまの再生位置（範囲の中だけ・つまみを動かしている間は出さない）
                if dragging == nil, playback.playhead >= trim.start, playback.playhead <= trim.end {
                    Rectangle().fill(Color.white)
                        .frame(width: 2, height: Self.stripHeight + 8)
                        .offset(x: inset + StoryVideoTrim.position(of: playback.playhead, total: trim.total,
                                                                   width: barWidth) - 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                handle(.start, x: inset + startX - Self.handleWidth, barWidth: barWidth)
                handle(.end, x: inset + endX, barWidth: barWidth)
            }
            .coordinateSpace(.named(Self.space))
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
            Rectangle().fill(WebTheme.surface3)
                .frame(width: width, height: Self.stripHeight)
        }
    }

    /// つまみ 1 つ。見た目は幅 16 の真鍮の板（中に墨の溝）、**当たりは幅 44**（見た目の外へ 14 ずつ）。
    /// 読み上げは「開始位置・0:12」で、増やす・減らすで 1 秒ずつ動く
    private func handle(_ which: Handle, x: CGFloat, barWidth: CGFloat) -> some View {
        let time = which == .start ? trim.start : trim.end
        let hit = WebTheme.minTapTarget
        return ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .frame(width: Self.handleWidth, height: Self.stripHeight + 8)
            RoundedRectangle(cornerRadius: 1)
                .fill(WebTheme.accentText)
                .frame(width: 2, height: 20)
        }
        .frame(width: hit, height: Self.stripHeight + 8)
        .contentShape(Rectangle())
        .offset(x: x - (hit - Self.handleWidth) / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    if dragging != which {
                        dragging = which
                        dragOrigin = time
                        resumeAfterDrag = playback.isPlaying
                        playback.pause()
                        grabTick += 1
                    }
                    let delta = Double(value.translation.width / barWidth) * trim.total
                    let before = trim.length
                    if which == .start { trim.setStart(dragOrigin + delta) } else { trim.setEnd(dragOrigin + delta) }
                    // 60 秒の枠に当たった（反対側が引かれた）瞬間に触覚
                    if trim.length >= StoryVideoTrim.maxLength - 0.001, before < StoryVideoTrim.maxLength - 0.001 {
                        limitTick += 1
                    }
                    playback.show(at: which == .start ? trim.start : trim.end)
                }
                .onEnded { _ in
                    dragging = nil
                    playback.setRange(start: trim.start, end: trim.end, playing: resumeAfterDrag)
                }
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

    // MARK: - 細かい合わせ

    /// 「開始 −0:12＋」「終了 −1:12＋」。**長い動画は帯の 1pt が数秒**なので、1 秒ずつの合わせを置く
    private var fineAdjust: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                stepper(.start)
                Spacer(minLength: 0)
                stepper(.end)
            }
            VStack(alignment: .leading, spacing: 8) {
                stepper(.start)
                stepper(.end)
            }
        }
    }

    private func stepper(_ which: Handle) -> some View {
        let time = which == .start ? trim.start : trim.end
        let name = which == .start ? L("開始", "Start") : L("終了", "End")
        return HStack(spacing: 4) {
            stepButton(symbol: "minus", label: L("\(name)を1秒戻す", "Move \(name.lowercased()) 1 second earlier")) {
                nudge(which, by: -StoryVideoTrim.nudgeStep)
            }
            VStack(spacing: 0) {
                Text(name).font(JPFont.caption).foregroundStyle(WebTheme.text2)
                Text(StoryVideoTrim.label(time)).font(JPFont.mono(15)).foregroundStyle(.white)
            }
            .frame(minWidth: 52)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(StoryVideoTrim.label(time))
            stepButton(symbol: "plus", label: L("\(name)を1秒進める", "Move \(name.lowercased()) 1 second later")) {
                nudge(which, by: StoryVideoTrim.nudgeStep)
            }
        }
    }

    private func stepButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .background(WebTheme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 1 秒ずつ動かして、その時刻の絵を出し、範囲の頭から再生し直す
    private func nudge(_ which: Handle, by delta: Double) {
        let before = trim.length
        if which == .start { trim.nudgeStart(by: delta) } else { trim.nudgeEnd(by: delta) }
        if trim.length >= StoryVideoTrim.maxLength - 0.001, before < StoryVideoTrim.maxLength - 0.001 { limitTick += 1 }
        playback.setRange(start: trim.start, end: trim.end, playing: playback.isPlaying)
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

    init(url: URL, start: Double, end: Double) {
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
