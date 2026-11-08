import Foundation

/// ストーリーのカメラ（札 #500・デザイナーのモック A 案「iPhone 型」）の決まり。
/// 画面（`StoryCameraView`）から出しておく——Linux の `swift test` で確かめられるように。
enum StoryCameraRules {

    enum Mode: Equatable {
        case photo
        case video

        /// 切り替えの表の言葉（モック: 「写真｜動画」）
        var label: String {
            switch self {
            case .photo: return L("写真", "Photo")
            case .video: return L("動画", "Video")
            }
        }
    }

    // MARK: - シャッター

    /// 押し続けたら動画にする長さ（秒）。これより短い押しは「タップ」
    static let holdThreshold: Double = 0.4

    enum ShutterAction: Equatable {
        case takePhoto
        case startRecording
        case stopRecording
    }

    /// 指を離した（タップで終わった）ときの動作。**撮っている最中のタップは止める**
    static func tapAction(mode: Mode, isRecording: Bool) -> ShutterAction {
        if isRecording { return .stopRecording }
        switch mode {
        case .photo: return .takePhoto
        case .video: return .startRecording
        }
    }

    /// 押し続けて `holdThreshold` を超えた。**どちらのモードでも動画を始める**（写真モードの長押し＝動画）。
    /// すでに撮っていれば何もしない
    static func holdAction(isRecording: Bool) -> ShutterAction? {
        isRecording ? nil : .startRecording
    }

    /// 押し続けて始めた録画は、**指を離したら止める**。タップで始めた録画（動画モード）は次のタップで止める
    static func releaseStopsRecording(startedByHold: Bool) -> Bool { startedByHold }

    // MARK: - 録画

    /// 録画の進み具合（0〜1）。上限は `StoryVideoRules.maxSeconds`
    static func progress(elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        return min(1, elapsed / StoryVideoRules.maxSeconds)
    }

    /// 上限に着いたか（`AVCaptureMovieFileOutput.maxRecordedDuration` が止める）
    static func reachedLimit(elapsed: Double) -> Bool {
        elapsed >= StoryVideoRules.maxSeconds - 0.05
    }

    // MARK: - 触覚

    /// 触覚が鳴る出来事（札 #500 の決め）
    enum Event: Equatable {
        case photoTaken
        case recordingStarted
        case recordingStopped
        case modeSwitched
        case limitReached
        case failed
        case posted
    }

    enum Haptic: Equatable {
        case impactMedium
        case impactHeavy
        case impactLight
        case selection
        case warning
        case error
        case success
    }

    /// 写真 impact(medium)・録画開始 heavy・停止 light・切り替え selection・上限 warning・失敗 error・投稿完了 success
    static func haptic(for event: Event) -> Haptic {
        switch event {
        case .photoTaken: return .impactMedium
        case .recordingStarted: return .impactHeavy
        case .recordingStopped: return .impactLight
        case .modeSwitched: return .selection
        case .limitReached: return .warning
        case .failed: return .error
        case .posted: return .success
        }
    }

    // MARK: - アプリのアイコン長押し

    /// ホーム画面のアイコン長押しの項目の種類（`project.yml` の `UIApplicationShortcutItems` と同じ文字）
    static let shortcutType = "photo.journey.shortcut.storyCamera"

    // MARK: - 起動直後

    /// 起動の時刻（`AppDelegate` が起動の早い時期に触って固定する）
    static let launchedAt = Date()
    /// 起動してから、アイコン長押しを受けるまで待つ秒数（起動直後の約1秒は処理が詰まる・#435 の計測で最大 1.6 秒）
    static let settleSeconds: TimeInterval = 2.0

    /// 起動からの経過に対して、あと何秒待つか（0 以下なら待たない）
    static func settleWait(sinceLaunch: TimeInterval) -> TimeInterval {
        max(0, settleSeconds - max(0, sinceLaunch))
    }

    /// アイコン長押しの「ストーリーを撮る」を、いま受けてよいか。
    ///
    /// 2026-11-08 判断（札 #500・#435）: 起動直後の約1秒はメインスレッドが止まりやすく（最大 1.6 秒・#435 の計測）、
    /// 起動直後に画面を重ねる設計は競合しうる。**タブが出て、ログインが済み、ほかの画面（投稿・お知らせ・
    /// 規約など）が出ていないときだけ**受け、それまでは**持ち越す**（捨てない）。タブの選択（`selection`）には触らない
    static func canOpenCamera(signedIn: Bool, tabsShown: Bool, anotherScreenShown: Bool) -> Bool {
        signedIn && tabsShown && !anotherScreenShown
    }
}
