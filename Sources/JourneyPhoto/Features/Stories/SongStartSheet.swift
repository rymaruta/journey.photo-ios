import SwiftUI

/// 曲の流し始めを選ぶ（owner の「ストーリーの自由度が低い」・2026-09-29）。
///
/// 30秒の試聴のうち、どこから鳴らすか。Web のストーリーの「好きな部分」と
/// 同じ値（`startSec`・0〜29秒。`stories.ts` が同じ丸めで保存する）で、
/// 見る人のアプリも Web もこの位置から流す（`StoryPlayback`）。
/// **動かし終えたらその位置から鳴らす**——数字だけでは、どこが好きな部分か選べない
///
/// **2026-11-12 判断（設計の案「ストーリーのデザイン 残り」03・曲を選ぶ SongPicker v2 に合わせる）**:
///  - 曲の絵を大きく（152・角 14）、題と歌い手を真ん中に
///  - 「▶ 0:12 から 5秒」の下に **30 秒の帯**。白い枠が表示の秒数ぶん。枠の中は鳴った所まで白（`SongStartStrip`）
///  - 枠を左右に動かす・帯を押すとその位置へ。**離すとその位置から鳴らし直す**
///  - 決めるのは下の主ボタン「この位置にする」（写真の無い画面なので真鍮に墨・親指の届く所）。上の「決める」はやめた
///  - 試聴の読み込み中は帯を灰の骨組み・再生の丸を回る印に。流せない（圏外）ときは帯を薄くし、理由と「もう一度」。
///    位置は決められる（見る人の側で鳴る）
///  - 開いたらすぐ鳴らす（押さなくても聴ける）
struct SongStartSheet: View {

    let song: Photo.Song
    /// 表示秒数。**流し始めの上限を決める**（`Photo.Song.maxStart`）
    let durationSec: Int
    /// 決めたときに、流し始めを入れた曲を渡す
    let onDone: (Photo.Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var player = MusicPreviewPlayer.shared
    @State private var start: Int
    /// この画面で鳴らした回（閉じたときに**自分が鳴らした曲だけ**止める）
    @State private var playedSession: Int?
    /// 自分で止めた（「流せない」と取り違えない）
    @State private var stoppedByMe = false
    /// 枠を掴んだ所（枠の左端から何秒か）。掴んでいない間は nil
    @State private var grab: Double?
    /// 枠を動かした・帯を押した（触覚）
    @State private var moveTick = 0

    init(song: Photo.Song, durationSec: Int, onDone: @escaping (Photo.Song) -> Void) {
        self.song = song
        self.durationSec = durationSec
        self.onDone = onDone
        _start = State(initialValue: min(song.startSec ?? 0, Photo.Song.maxStart(window: durationSec)))
    }

    /// 枠の秒数（表示秒数。試聴より長ければ試聴の長さ）
    private var window: Int { min(max(1, durationSec), SongStartStrip.totalSeconds) }

    private var mine: Bool { playedSession != nil && playedSession == player.session }

    /// 試聴の状態（`SongStartStrip.playback`）
    private var playback: SongStartStrip.Playback {
        SongStartStrip.playback(mine: mine, playing: player.isPlaying(song.previewURL), stoppedByMe: stoppedByMe,
                                itemFailed: mine && player.previewItemFailed(for: song.previewURL),
                                waiting: mine && player.previewWaiting(for: song.previewURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, JPSpace.l)
                    playRow
                        .padding(.top, JPSpace.xl)
                    strip
                        .padding(.top, JPSpace.l)
                    ticks
                        .padding(.top, JPSpace.xs)
                }
                .padding(.horizontal, JPSpace.m)
            }
            Button {
                onDone(song.starting(at: Double(start), window: durationSec))
                dismiss()
            } label: {
                Text(L("この位置にする", "Use this point")).jpPillButton(.main(onPhoto: false))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, JPSpace.m)
            .padding(.vertical, JPSpace.s)
            .accessibilityIdentifier("songStart.done")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WebTheme.background)
        .foregroundStyle(.white)
        // バーも黒に（曲選び `SongPickerView` と同じく、画面の側で持つ）
        .webScreen()
        .navigationTitle(L("流し始め", "Start point"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.cancel) { dismiss() }
            }
        }
        .sensoryFeedback(.selection, trigger: moveTick)
        // 開いたらすぐ、いまの位置から鳴らす（押さなくても聴ける）
        .onAppear { if playedSession == nil { playFromStart() } }
        // **自分が鳴らした曲だけ止める**（閉じるまでに別の画面が鳴らした曲は止めない）
        .onDisappear {
            if playedSession == player.session { player.stop() }
        }
    }

    // MARK: - 曲

    private var header: some View {
        VStack(spacing: 6) {
            RemoteImage(url: song.artworkURL)
                .frame(width: 152, height: 152)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
                .shadow(color: Color.black.opacity(0.6), radius: 20, y: 12)
                .accessibilityHidden(true)
            Text(song.title)
                .font(JPFont.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, JPSpace.s)
            if let artist = song.artist, !artist.isEmpty {
                Text(artist)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// 「▶ 0:12 から 5秒」。流せないときは、ここに理由と「もう一度」
    @ViewBuilder
    private var playRow: some View {
        if playback == .failed {
            HStack(spacing: JPSpace.xs) {
                Image(systemName: "wifi.exclamationmark")
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .accessibilityHidden(true)
                Text(L("試聴を流せません。通信を確かめてください", "Can't play the preview. Check your connection"))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                Button(Labels.Common.retry) { playFromStart() }
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .buttonStyle(.plain)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("songStart.retry")
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .accessibilityIdentifier("songStart.failed")
        } else {
            HStack(spacing: JPSpace.s) {
                Button {
                    if player.isPlaying(song.previewURL) && mine {
                        stoppedByMe = true
                        player.stop()
                    } else {
                        playFromStart()
                    }
                } label: {
                    Group {
                        if playback == .loading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: playback == .playing ? "pause.fill" : "play.fill")
                                .font(Font.title3)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(WebTheme.sheet, in: Circle())
                    .overlay(Circle().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback == .playing ? L("止める", "Stop") : L("ここから聴く", "Play from here"))
                .accessibilityIdentifier("songStart.play")
                Text(SongStartStrip.clock(start))
                    .font(JPFont.mono(20, relativeTo: .title3))
                Text(SongStartStrip.lengthNote(window: window))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text3)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
    }

    // MARK: - 帯

    /// 30 秒の帯と、表示の秒数ぶんの白い枠。**枠を動かす・帯を押す**とその位置へ。離すと鳴らし直す。
    /// 読み込み中は灰の骨組み、流せないときは薄く（位置は決められる）
    private var strip: some View {
        GeometryReader { geometry in
            let width = Double(geometry.size.width)
            let frame = SongStartStrip.windowFraction(start: start, window: window)
            let windowX: CGFloat = CGFloat(frame.left * width)
            let windowWidth: CGFloat = CGFloat(frame.width * width)
            let barHeight: CGFloat = CGFloat(SongStartStrip.stripHeight)
            let windowHeight: CGFloat = barHeight + 8
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(WebTheme.sheet)
                    .frame(height: barHeight)
                    .offset(y: 4)
                bars
                    .frame(height: barHeight)
                    .padding(.horizontal, 6)
                    .offset(y: 4)
                    .opacity(playback == .failed ? 0.4 : 1)
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: windowWidth, height: windowHeight)
                    .offset(x: windowX)
                    .allowsHitTesting(false)
            }
            .frame(height: windowHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let touch = SongStartStrip.seconds(atX: Double(value.location.x), width: width)
                        let held = grab ?? SongStartStrip.grabOffset(touchSeconds: touch, start: start, window: window)
                        if grab == nil {
                            grab = held
                            // 動かしている間は止める（離したらその位置から）
                            if mine && player.isPlaying(song.previewURL) {
                                stoppedByMe = true
                                player.stop()
                            }
                        }
                        let next = SongStartStrip.start(touchSeconds: touch, grab: held, window: window)
                        if next != start {
                            start = next
                            moveTick += 1
                        }
                    }
                    .onEnded { _ in
                        grab = nil
                        playFromStart()
                    }
            )
        }
        .frame(height: CGFloat(SongStartStrip.stripHeight) + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("流し始め", "Start point"))
        .accessibilityValue(Photo.Song.startLabel(start))
        .accessibilityHint(L("増やす・減らすで1秒ずつ動かします", "Adjust to move by one second"))
        .accessibilityAdjustableAction { direction in
            let next = start + (direction == .increment ? 1 : -1)
            start = min(max(0, next), Photo.Song.maxStart(window: durationSec))
            playFromStart()
        }
        .accessibilityIdentifier("songStart.strip")
    }

    /// 棒（1 秒に 2 本・等間隔の拍）。枠の中は鳴った所まで白、まだの所は白 55%、枠の外は灰。
    /// 鳴った所は描くたびに読む（`TimelineView`・再生器の時刻は `@Published` にしない）
    private var bars: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: playback != .playing || reduceMotion)) { _ in
            let played = playedSeconds
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<SongStartStrip.barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(SongStartStrip.tone(index: index, start: start, window: window, played: played)))
                        .frame(height: CGFloat(SongStartStrip.barHeight(index)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    /// 流し始めから何秒鳴ったか（鳴っていなければ 0）
    private var playedSeconds: Double {
        guard mine, grab == nil, let now = player.previewTime(for: song.previewURL) else { return 0 }
        return max(0, now - Double(start))
    }

    private func barColor(_ tone: SongStartStrip.BarTone) -> Color {
        if playback == .loading { return WebTheme.surface4 }
        switch tone {
        case .outside: return WebTheme.outline.opacity(0.9)
        case .played: return Color.white
        case .upcoming: return Color.white.opacity(0.55)
        }
    }

    private var ticks: some View {
        HStack {
            ForEach(SongStartStrip.tickLabels, id: \.self) { label in
                Text(label)
                if label != SongStartStrip.tickLabels.last { Spacer(minLength: 0) }
            }
        }
        .font(JPFont.mono(12, relativeTo: .caption))
        .foregroundStyle(WebTheme.text3)
        .accessibilityHidden(true)
    }

    private func playFromStart() {
        stoppedByMe = false
        // 曲選びの試し聴きと同じ扱い（全体のミニプレイヤーには出さない）。表示秒数ぶんを繰り返す
        playedSession = player.play(song.previewURL, song: song, loops: true, from: Double(start),
                                    length: Double(window), origin: .songPicker)
    }
}
