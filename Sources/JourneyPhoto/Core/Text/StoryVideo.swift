import Foundation

/// ストーリーの動画（札 #500・owner 2026-11-08）の決まり。**画面と AVFoundation から出しておく**
/// （`Shims/` では動画を扱えないので、ここに置いたぶんが Linux の `swift test` で確かめられる）。
///
/// 上限は Web と同じ（`StoriesBar.tsx` の `MAX_VIDEO_SECONDS`・`api-user/src/upload.ts` の `MAX_UPLOAD_BYTES`）:
/// 60 秒・50MB、許可は mp4 / webm / mov（`ALLOWED_VIDEO_TYPES`）。
enum StoryVideoRules {

    /// 動画の長さの上限（秒）。Web と同じ 60
    static let maxSeconds: Double = 60
    /// 上げられる大きさの上限（バイト）。サーバーの `MAX_UPLOAD_BYTES`（50MB）
    static let maxBytes = 50 * 1024 * 1024
    /// 書き出しの目標。**上限ちょうどに寄せない**（書き出しの見積もりは多少ずれる）
    static let targetBytes = 45 * 1024 * 1024
    /// サーバーが受ける動画の種類（presign の許可リスト）
    static let allowedFileTypes = ["video/mp4", "video/quicktime", "video/webm"]

    /// この端末で書き出す形。**mp4（H.264 + AAC）** にする
    ///
    /// 2026-11-08 判断（札 #500）: 書き出しは HEVC にしない。iPhone の既定は HEVC だが、Web の
    /// `isHevcVideo` が警告するとおり HEVC は Android・PC で映らないことがある。ストーリーは Web でも見られるので、
    /// 全部の端末で映る H.264 の mp4 にそろえる（`AVAssetExportPreset…x…` は H.264）。
    /// 同じ長さなら HEVC のほうが小さいが、50MB に収まらないときは下の段（`presetLadder`）で解像度を落として収める
    static let exportFileType = "video/mp4"
    static let exportExtension = "mp4"

    /// 拡張子から送る種類。知らない拡張子は nil（送らない）
    static func fileType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov", "qt": return "video/quicktime"
        case "webm": return "video/webm"
        default: return nil
        }
    }

    /// 種類から拡張子（presign の `fileName` に使う）。許可に無い種類は nil
    static func fileExtension(forFileType type: String) -> String? {
        switch type.split(separator: ";").first.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "video/webm": return "webm"
        default: return nil
        }
    }

    // MARK: - 取り込みの確かめ

    enum Problem: Equatable {
        /// 60 秒を超える
        case tooLong
        /// 長さが読めない（壊れている・動画でない）
        case unreadable
        /// 50MB に収まらない（書き出しても届かなかった）
        case tooLarge
        /// 位置情報を消せなかった（消せないまま上げない・Web の `toUploadSafeVideo` と同じ）
        case locationRemains
        /// 書き出しに失敗した
        case exportFailed
        /// 動画の取り込みが時間内に終わらなかった(iCloud から落とせない・返ってこない)
        case importTimedOut
        /// 取り込みに失敗した（写真アプリから読めない・iCloud から落とせない）
        case importFailed

        /// 画面に出す一言（何が起きたか＋どうすればよいか）
        var message: String {
            switch self {
            case .tooLong:
                return L("動画は60秒以内にしてください", "Video must be 60 seconds or shorter")
            case .unreadable:
                return L("動画を読み込めませんでした", "Couldn't read the video")
            case .tooLarge:
                return L("動画が大きすぎて、50MBに収められませんでした。短くして、もう一度選んでください",
                         "The video is too large to fit in 50MB. Trim it and try again")
            case .locationRemains:
                return L("動画の位置情報を消せなかったので、投稿できません。別の動画を選んでください",
                         "The video's location data couldn't be removed, so it can't be posted. Choose a different video")
            case .exportFailed:
                return L("動画の準備に失敗しました。もう一度お試しください", "Couldn't prepare the video. Please try again")
            case .importTimedOut:
                return L("動画の読み込みに時間がかかっています。通信の状態を確かめて、もう一度選んでください",
                         "Loading the video is taking too long. Check your connection and choose it again")
            case .importFailed:
                return L("動画を読み込めませんでした。通信の状態を確かめて、もう一度選んでください",
                         "Couldn't load the video. Check your connection and choose it again")
            }
        }
    }

    /// 取り込み時の確かめ。**長さを先に**（長すぎる動画の大きさを測っても、書き出しで収まる保証がない）
    static func problem(durationSec: Double?) -> Problem? {
        guard let durationSec, durationSec.isFinite, durationSec > 0 else { return .unreadable }
        // 60.0 ちょうどは通す（撮影が 60 秒で止まった動画は 60.02 のように少し超える。0.5 秒の余裕）
        return durationSec > maxSeconds + 0.5 ? .tooLong : nil
    }

    /// 書き出した結果の確かめ
    static func problem(exportedBytes: Int) -> Problem? {
        guard exportedBytes > 0 else { return .exportFailed }
        return exportedBytes > maxBytes ? .tooLarge : nil
    }

    // MARK: - 書き出し

    /// 書き出しの段（解像度の名前は `AVAssetExportPreset…` の末尾と同じ）
    struct Step: Equatable {
        let preset: String
        /// 見積もりの映像の速さ（ビット毎秒）。段を選ぶ目安だけに使う
        let estimatedBitsPerSecond: Double
        /// 出す画面の長い辺の上限(画素)。重ねを焼き込むとき、この大きさまで縮めて描き直す
        /// (縮めないと、4K の動画は 1080p の段でも 4K のまま書き出されて 50MB に収まらない)
        let longSide: Double
    }

    /// 重ねを焼き込むときの、段に合わせた大きさ。**長い辺が段の上限を超えるときだけ縮め**(拡大しない)、
    /// 画素は偶数にする(H.264 は偶数を好む)。縦横比は保つ
    static func renderSize(for size: CGSize, step: Step) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        let longSide = Double(max(size.width, size.height))
        let scale = min(1, step.longSide / longSide)
        func even(_ value: Double) -> CGFloat { CGFloat(max(2, (value / 2).rounded() * 2)) }
        return CGSize(width: even(Double(size.width) * scale), height: even(Double(size.height) * scale))
    }

    /// 重ねを焼き込むときの 1 秒あたりのコマ数。**30 を上限にする**(60fps のまま焼くと大きさが倍近くなる)
    static func overlayFrameRate(source: Float) -> Int32 {
        source.isFinite && source > 1 ? Int32(min(30, source.rounded())) : 30
    }

    /// 送る直前の確かめ。**動画のストーリーが書き出し済みでない・書き出したあとに重ねが変わった**なら、
    /// 静止画として黙って出さず、書き出し直す(`StoryComposerView.post`)
    enum ExportCheck: Equatable {
        case ok
        case reexport
    }

    static func exportCheck(videoShots: [UUID], exported: Set<UUID>, overlaysMatch: Bool) -> ExportCheck {
        let wanted = Set(videoShots)
        return wanted == exported && overlaysMatch ? .ok : .reexport
    }

    /// 上の段から順に。**長さに対して 45MB に収まりそうな段から始める**（収まらなければ下げる）。
    /// 音声（128kbps）ぶんを引いて比べる。最後の段でも収まらなければ呼ぶ側が `tooLarge` にする
    static let allSteps: [Step] = [
        Step(preset: "AVAssetExportPreset1920x1080", estimatedBitsPerSecond: 8_000_000, longSide: 1920),
        Step(preset: "AVAssetExportPreset1280x720", estimatedBitsPerSecond: 4_000_000, longSide: 1280),
        Step(preset: "AVAssetExportPreset960x540", estimatedBitsPerSecond: 2_000_000, longSide: 960),
        Step(preset: "AVAssetExportPreset640x480", estimatedBitsPerSecond: 1_000_000, longSide: 640),
    ]

    static let audioBitsPerSecond = 128_000.0

    /// この長さで試す段の並び（先頭がいちばん画質が良い、収まりそうな段）。**空にはしない**
    /// （どれも収まりそうになければ最後の段だけ）。
    /// 例: 10 秒は 1080p から、60 秒は 720p でも 34MB 見込みなので 720p から
    static func ladder(durationSec: Double) -> [Step] {
        let seconds = max(durationSec, 1)
        let fits = allSteps.filter { step in
            (step.estimatedBitsPerSecond + audioBitsPerSecond) * seconds / 8 <= Double(targetBytes)
        }
        if !fits.isEmpty { return fits }
        return [allSteps[allSteps.count - 1]]
    }

    // MARK: - 位置情報

    /// 動画の付帯情報の識別子が位置情報か。**1つでも残っていたら上げない**。
    /// QuickTime の `com.apple.quicktime.location.ISO6709`、共通の `location`、MP4 の `©xyz` を見る
    static func isLocationIdentifier(_ identifier: String) -> Bool {
        let id = identifier.lowercased()
        return id.contains("location") || id.contains("©xyz") || id.contains("iso6709") || id.hasSuffix("/xyz")
    }

    // MARK: - 投稿の形

    /// 動画の投稿本文に付けてよいもの。**サーバーは動画の位置・座標・表示秒数を捨てる**
    /// （`stories.ts`: `mediaType === "image"` のときだけ読む）。送らないことで、片側だけの防御にしない
    static func sendsLocation(mediaType: String) -> Bool { mediaType == "image" }
    static func sendsDuration(mediaType: String) -> Bool { mediaType == "image" }
}

/// 取り込んだ動画（端末の一時ファイル）。**画面の `StoryShot` が持つ**
struct StoryVideoClip: Equatable {
    /// 端末の中の動画ファイル（アプリの一時フォルダの下に写したもの）
    let url: URL
    /// 長さ（秒）
    let durationSec: Double
    /// 映像の向きを直した後の大きさ（画素）。重ねの焼き込みの基準
    let size: CGSize
    /// 元のファイルの大きさ
    let bytes: Int

    /// 一覧・読み上げ用の「0:12」
    var durationLabel: String { Self.label(durationSec) }

    static func label(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

extension StoryVideoRules.Problem: LocalizedError {
    /// 送れなかった知らせにそのまま出る（`StoryUploadCenter` の失敗の言い分）
    var errorDescription: String? { message }
}
