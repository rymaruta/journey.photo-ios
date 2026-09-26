import Foundation

/// 「曲を選ぶ」（板 23）の並びと文言。
///
/// **欄が空のときに出すのは、この端末で最近選んだ曲だけ。** 板は検索前にも
/// 5曲並べているが、サーバーの曲の口は `/music/search`（打った語で探す）
/// しか無い——「おすすめ」「人気」の口は無い（2026-09-26・`api-user/serverless.yml`
/// を develop で確認）。**口の無いものを作って並べない。** 手元にある本物の
/// 材料（自分が前に選んだ曲）だけを出す。
enum SongPickerText {

    /// 覚えておく数。板の並び（5曲）と同じ
    static let recentLimit = 5

    /// 並べる曲。欄が空（空白だけも空）なら最近選んだ曲、打っていれば検索結果。
    /// **同じ試聴の URL は1つにする**——`ForEach` の目印に使うので、重なると
    /// 行が取り違えられる
    static func rows(query: String, results: [Photo.Song], recent: [Photo.Song]) -> [Photo.Song] {
        let typed = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return unique(typed ? results : recent)
    }

    /// 選んだ曲を最近の並びの先頭に置く。**前に選んだ同じ曲は取り除いてから**
    /// （下に残ると同じ曲が2行並ぶ）。`limit` を超えたぶんは古い方から落とす
    static func remembering(_ song: Photo.Song, in recent: [Photo.Song],
                            limit: Int = recentLimit) -> [Photo.Song] {
        let rest = recent.filter { $0.previewUrl != song.previewUrl }
        return Array(([song] + rest).prefix(max(limit, 0)))
    }

    static func unique(_ songs: [Photo.Song]) -> [Photo.Song] {
        var seen: Set<String> = []
        return songs.filter { seen.insert($0.previewUrl).inserted }
    }

    /// 一覧の下の注記（板 23）
    static var previewNote: String {
        L("30秒の試聴だけを使います。", "Only the 30-second preview is used.")
    }

    /// 試し聴きの丸ボタンの読み上げ。**鳴っている間は「止める」**
    /// （押すと `stop()`——頭に戻る。一時停止ではないので英語も "Stop"）。
    /// `SongRow` と同じ語
    static func previewButtonLabel(isPlaying: Bool) -> String {
        isPlaying ? L("止める", "Stop") : L("試し聴き", "Preview")
    }

    /// 検索の返事を画面に入れてよいか。**送ったときの語といまの欄が同じときだけ。**
    /// 返事が遅れて届くと、欄を空にした（または打ち直した）あとに古い
    /// 「見つかりませんでした」や前の語の結果が出る
    static func isCurrent(sent: String, now: String) -> Bool {
        sent.trimmingCharacters(in: .whitespacesAndNewlines)
            == now.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 再生バーを出すか。**曲選びの中のバーは、鳴っている曲なら何でも出す**
    /// ——全体のバーはシートに覆われて見えないので、前から鳴っていた曲
    /// （マイページの BGM など）を出さないと、鳴っているのに止める口が画面に無い。
    /// **全体のバーは曲選びで鳴らした曲を出さない**——シートを下へ引いて閉じる
    /// 途中に2本並ばないように。前から鳴っていた曲（`.app`）だけは閉じる途中に
    /// 2本見えうるが、止める口が無いよりよい
    static func showsBar(playingFrom origin: PlaybackOrigin?, inSongPicker: Bool) -> Bool {
        guard let origin else { return false }
        return inSongPicker ? true : origin != .songPicker
    }

    /// バーの1行目。**「· 試し聴き中」は曲選びで鳴らした曲をシートの中で出すときだけ**
    /// （前から鳴っていた曲は試し聴きではない）
    static func barTitle(_ title: String, playingFrom origin: PlaybackOrigin?, inSongPicker: Bool) -> String {
        inSongPicker && origin == .songPicker ? nowPreviewing(title) : title
    }

    /// シートの中の再生バーの1行目（板 23「[曲名] · 試し聴き中」）
    static func nowPreviewing(_ title: String) -> String {
        L("\(title) · 試し聴き中", "\(title) · Previewing")
    }

    /// 検索の回の番号。**くるくるを戻すのは最新の回だけ**（`isCurrent` と同じ考え方）。
    /// 古い検索の返事が遅れて届いたとき、新しい検索の途中の表示を消さないため
    struct SearchRuns {
        private(set) var latest = 0
        mutating func begin() -> Int {
            latest += 1
            return latest
        }
        func isLatest(_ run: Int) -> Bool { run == latest }
    }
}

/// 曲をどこで鳴らしたか（`MusicPreviewPlayer.origin`）
enum PlaybackOrigin: Equatable {
    /// 写真・プロフィール・ストーリーなど、ふつうの画面
    case app
    /// 「曲を選ぶ」の試し聴き
    case songPicker
}
