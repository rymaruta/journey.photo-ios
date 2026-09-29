import SwiftUI

/// 曲の流し始めを選ぶ（owner の「ストーリーの自由度が低い」・2026-09-29）。
///
/// 30秒の試聴のうち、どこから鳴らすか。Web のストーリーの「好きな部分」と
/// 同じ値（`startSec`・0〜29秒。`stories.ts` が同じ丸めで保存する）で、
/// 見る人のアプリも Web もこの位置から流す（`StoryPlayback`）。
/// **動かし終えたらその位置から鳴らす**——数字だけでは、どこが好きな部分か選べない
struct SongStartSheet: View {

    let song: Photo.Song
    /// 表示秒数。**流し始めの上限を決める**（`Photo.Song.maxStart`）
    let durationSec: Int
    /// 決めたときに、流し始めを入れた曲を渡す
    let onDone: (Photo.Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = MusicPreviewPlayer.shared
    @State private var start: Double
    /// この画面で鳴らした回（閉じたときに**自分が鳴らした曲だけ**止める）
    @State private var playedSession: Int?

    init(song: Photo.Song, durationSec: Int, onDone: @escaping (Photo.Song) -> Void) {
        self.song = song
        self.durationSec = durationSec
        self.onDone = onDone
        _start = State(initialValue: Double(min(song.startSec ?? 0, Photo.Song.maxStart(window: durationSec))))
    }

    private var isPlaying: Bool {
        playedSession == player.session && player.isPlaying(song.previewURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                RemoteImage(url: song.artworkURL)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if let artist = song.artist, !artist.isEmpty {
                        Text(artist).font(.system(size: 13)).foregroundStyle(WebTheme.muted2).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    if isPlaying { player.stop() } else { playFromStart() }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .jpGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? L("止める", "Stop") : L("ここから聴く", "Play from here"))
            }

            Text(Photo.Song.startLabel(Int(start)))
                .font(JPFont.mono(15))
                .foregroundStyle(.white)
            Slider(value: $start, in: 0...Double(Photo.Song.maxStart(window: durationSec)), step: 1) { editing in
                // 動かし終えたら、その位置から鳴らして確かめる
                if !editing { playFromStart() }
            }
            .tint(WebTheme.accent)
            .accessibilityLabel(L("流し始め", "Start point"))
            .accessibilityValue(Photo.Song.startLabel(Int(start)))

            Text(L("30秒の試聴のうち、ここから表示の\(durationSec)秒ぶん流れます。見る人にもこの位置から流れます。",
                   "Plays \(durationSec)s from here within the 30-second preview — viewers hear it from here too."))
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.muted2)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WebTheme.background)
        .foregroundStyle(.white)
        .navigationTitle(L("流し始め", "Start point"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Labels.Common.cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("決める", "Set")) {
                    onDone(song.starting(at: start, window: durationSec))
                    dismiss()
                }
            }
        }
        // **自分が鳴らした曲だけ止める**（閉じるまでに別の画面が鳴らした曲は止めない）
        .onDisappear {
            if playedSession == player.session { player.stop() }
        }
    }

    private func playFromStart() {
        // 曲選びの試し聴きと同じ扱い（全体のミニプレイヤーには出さない）
        playedSession = player.play(song.previewURL, song: song, loops: true, from: start,
                                    origin: .songPicker)
    }
}
