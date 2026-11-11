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

    /// 指を離したときにすること
    enum ReleaseOutcome: Equatable {
        /// この押しで録画が始まった（長押し）。**離しても止めない**
        case keepRecording
        /// 長押しにならなかった。タップとして扱う（`pressIntent`）
        case tap
    }

    /// 2026-11-11 判断（owner「録画、指を離すと止まる。すごく面倒。撮影するときずっと押さないといけないのは嫌」）:
    /// **長押しで始めた録画も、指を離しても止めない。** 止めるのはもう一度押す（タップ）か、上限の秒数（60 秒）。
    /// 以前は長押しの録画だけ「離すと止まる」で、撮っている間ずっと押していなければならなかった。
    /// 動画モードのタップ（始める／止める）は今までどおり
    static func releaseOutcome(startedByHold: Bool) -> ReleaseOutcome {
        startedByHold ? .keepRecording : .tap
    }

    /// 録画を始めてから、止めるタップを受け付けるまでの秒数（2026-11-11 判断）。
    /// 始めた直後の二度押し——長押しを離した直後のもう一押し・動画モードの続けての2回タップ——で、
    /// 0 秒の動画になって画面が閉じないように。これより後のタップはいつでも止める
    static let stopGuardSeconds: Double = 0.5

    /// 録画中のタップで止めてよいか（`stopGuardSeconds` より前は受けない）
    static func acceptsStopTap(recordedSeconds: Double) -> Bool {
        guard recordedSeconds.isFinite else { return true }
        return recordedSeconds >= stopGuardSeconds
    }

    /// 録画中・始めている途中のシャッターの案内（録画を止める四角の上に出す）
    static var stopHint: String { L("押すと止まります", "Tap to stop") }

    // MARK: - マイク

    /// マイクの許可を済ませたあと、録画を始めてよいか。**長押しで始めた録画は、許可のダイアログの間に指が
    /// 離れていたら始めない**。タップで始める録画は常に始める。
    /// 2026-11-11 判断: 録画は離しても続くようになったが、ここは変えない——ダイアログに答えている間は映像を見て
    /// いないので、答えたあとに押していない録画が勝手に始まると驚く（もう一度押せばすぐ始まる）
    ///
    /// 2026-11-11 判断: **画面を閉じた（✕・下へ払った）あとは、どちらの録画も始めない**。始めている一瞬
    /// （マイクの用意の間）に閉じると、`camera.stop()` のあとに録画が始まり得た（前からの件・確かめ役の指摘）
    static func startsAfterPermission(fromHold: Bool, stillPressing: Bool, screenClosed: Bool) -> Bool {
        guard !screenClosed else { return false }
        return !fromHold || stillPressing
    }

    /// 「マイクが許可されていないので、音なしで撮ります」を出すか。動画モードのとき、
    /// **写真モードの長押しで録っている最中**にも出す(モードの切り替えが隠れている間)
    static func showsMicNote(micDenied: Bool, mode: Mode, isRecording: Bool) -> Bool {
        micDenied && (mode == .video || isRecording)
    }

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

    // MARK: - フラッシュ（2026-11-09・ストーリーのカメラの仕上げ）

    /// フラッシュの3つ。**順は オフ → オン → 自動 → オフ**（札 #500 の決め）。
    /// 写真は `AVCapturePhotoSettings.flashMode`、動画は録画の間だけのライト（`torchMode`）に当てる。
    /// 初めはいつも「オフ」（開くたびに戻す。暗い所で急に光らせない）
    enum Flash: Equatable, CaseIterable {
        case off
        case on
        case auto

        var next: Flash {
            switch self {
            case .off: return .on
            case .on: return .auto
            case .auto: return .off
            }
        }

        /// 記号（形でも状態が分かる・色だけで伝えない）
        var symbol: String {
            switch self {
            case .off: return "bolt.slash.fill"
            case .on: return "bolt.fill"
            case .auto: return "bolt.badge.automatic.fill"
            }
        }

        /// 読み上げ（「フラッシュ オフ」）
        var accessibilityLabel: String {
            switch self {
            case .off: return L("フラッシュ オフ", "Flash off")
            case .on: return L("フラッシュ オン", "Flash on")
            case .auto: return L("フラッシュ 自動", "Flash auto")
            }
        }

        /// 光る設定になっているか（ボタンの「選んでいる」札）
        var isActive: Bool { self != .off }
    }

    /// フラッシュのボタンを出すか。**背面だけ**（前面は光るものが無く、画面を光らせる作りは明るさを
    /// 書き換えて戻し忘れる恐れがあるので、出さない・2026-11-09 判断）。録画中・カウントダウン中は変えさせない
    static func showsFlash(hasFlash: Bool, isRecording: Bool, counting: Bool) -> Bool {
        hasFlash && !isRecording && !counting
    }

    // MARK: - タイマー（3秒・10秒）

    /// タイマーの3つ。**順は オフ → 3秒 → 10秒 → オフ**。開くたびに「オフ」へ戻す
    enum TimerOption: Equatable, CaseIterable {
        case off
        case three
        case ten

        var seconds: Int {
            switch self {
            case .off: return 0
            case .three: return 3
            case .ten: return 10
            }
        }

        var next: TimerOption {
            switch self {
            case .off: return .three
            case .three: return .ten
            case .ten: return .off
            }
        }

        var isActive: Bool { self != .off }

        /// 読み上げ（「タイマー 3秒」）
        var accessibilityLabel: String {
            switch self {
            case .off: return L("タイマー オフ", "Timer off")
            case .three: return L("タイマー 3秒", "Timer 3 seconds")
            case .ten: return L("タイマー 10秒", "Timer 10 seconds")
            }
        }
    }

    /// カウントダウンの数字（3, 2, 1）。0 は出さず、1 を見せ終えたら撮る
    static func countdownSequence(_ option: TimerOption) -> [Int] {
        guard option.seconds > 0 else { return [] }
        return Array((1...option.seconds).reversed())
    }

    /// 1つの数字を見せる長さ（秒）
    static let countdownStepSeconds: Double = 1

    /// シャッターを押した（タップで終えた）ときにすること。
    /// - カウントダウン中のタップは**取り消し**
    /// - 録画中のタップは止める（タイマーは使わない）
    /// - タイマーが入っていれば、数えてから `tapAction` の動作をする（**動画は押さずに始まる＝ハンズフリー**。
    ///   止めるのは次のタップか 60 秒の上限）
    /// - 録画を始めている途中（マイクの用意・始める処理の間）と、始めて `stopGuardSeconds` より前のタップは**受けない**
    ///   （2026-11-11 判断・二度押しで始まってすぐ止まる／始めている途中に写真を撮って閉じる、を防ぐ）
    enum PressIntent: Equatable {
        case perform(ShutterAction)
        case startCountdown(then: ShutterAction)
        case cancelCountdown
        case ignore
    }

    static func pressIntent(mode: Mode, isRecording: Bool, recordedSeconds: Double, starting: Bool,
                            timer: TimerOption, counting: Bool) -> PressIntent {
        if counting { return .cancelCountdown }
        if starting { return .ignore }
        if isRecording {
            return acceptsStopTap(recordedSeconds: recordedSeconds) ? .perform(.stopRecording) : .ignore
        }
        let action = tapAction(mode: mode, isRecording: false)
        return timer.isActive ? .startCountdown(then: action) : .perform(action)
    }

    /// 押し続けて動画にするか。**タイマーが入っているとき・数えている間は長押しを動画にしない**
    /// （押して離すだけで数え始める。長押しの動画と取り違えない）
    static func holdAction(isRecording: Bool, timer: TimerOption, counting: Bool) -> ShutterAction? {
        guard !counting, !timer.isActive else { return nil }
        return holdAction(isRecording: isRecording)
    }

    /// カウントダウンを続けてよいか。**アプリが前面でなくなった（電話・通知センター・ホームへ戻る）・
    /// 撮影の場が中断された・映像が出なくなった**ら取り消す（裏で勝手に撮らない）
    static func countdownContinues(sceneActive: Bool, sessionInterrupted: Bool, cameraReady: Bool) -> Bool {
        sceneActive && !sessionInterrupted && cameraReady
    }

    /// カウントダウンを始めるときの読み上げ（「3秒後に写真を撮ります」）
    static func countdownAnnouncement(seconds: Int, action: ShutterAction) -> String {
        switch action {
        case .takePhoto: return L("\(seconds)秒後に写真を撮ります", "Taking a photo in \(seconds) seconds")
        case .startRecording: return L("\(seconds)秒後に録画を始めます", "Recording starts in \(seconds) seconds")
        case .stopRecording: return ""
        }
    }

    static var countdownCancelledAnnouncement: String {
        L("カウントダウンを取り消しました", "Countdown cancelled")
    }

    // MARK: - ズーム（倍率の刻みは `ComposeControls.zoomLevels` を使い回す）

    /// 倍率の丸（0.5・1・2 …）を出すか。段が1つだけの端末（1× のみ）では出さない
    static func showsZoomPills(presetCount: Int) -> Bool { presetCount > 1 }

    /// 録画の間・数えている間も倍率は変えられる。**モードの切り替えと前後の切り替えは変えられない**
    static func allowsModeAndFlip(isRecording: Bool, counting: Bool) -> Bool {
        !isRecording && !counting
    }

    // MARK: - 画面の部品の出し方（2026-11-12 判断・設計の案「ストーリーのデザイン 残り」01）

    /// 撮る前の部品（右上のガラスの柱・左下の最近の1枚・右下の前後の切り替え・下の「写真｜動画」）を出すか。
    /// **録画中・数えている間は消す**（まわりの印を消して、映像とシャッターだけにする）
    static func showsChrome(isRecording: Bool, counting: Bool) -> Bool {
        !isRecording && !counting
    }

    /// 左上の ✕ を出すか。**録画中だけ消す**（止めるのはシャッター。数えている間は閉じられる）
    static func showsClose(isRecording: Bool) -> Bool { !isRecording }

    /// 倍率の丸を出すか。段が1つの端末と、**数えている間は出さない**（録画中は寄れる）
    static func showsZoom(presetCount: Int, counting: Bool) -> Bool {
        showsZoomPills(presetCount: presetCount) && !counting
    }

    /// 準備中（映像が出る前）の部品の濃さ。部品を先に置いて沈め、映像が出たら明るくする（位置が跳ねない）
    static let preparingOpacity = 0.4

    /// 数えている間の、シャッターの下の案内（「3秒後に撮ります · 押すと取り消し」）
    static func countdownNote(seconds: Int, action: ShutterAction) -> String {
        switch action {
        case .startRecording:
            return L("\(seconds)秒後に録画を始めます · 押すと取り消し", "Recording in \(seconds)s · Tap to cancel")
        case .takePhoto, .stopRecording:
            return L("\(seconds)秒後に撮ります · 押すと取り消し", "Taking a photo in \(seconds)s · Tap to cancel")
        }
    }

    /// 撮れなかった（写真・録画を始められない・録画が壊れた）ときの上の知らせ。以前は震えるだけで、目に見える知らせが無かった
    static var failureNote: String {
        L("撮れませんでした。もう一度押してください", "Couldn't capture. Please tap again")
    }

    /// 撮れなかった知らせを出しておく秒数
    static let failureNoteSeconds: Double = 3

    /// 録画の時間の札の上限（「/ 1:00」）
    static var limitLabel: String { "/ " + StoryVideoClip.label(StoryVideoRules.maxSeconds) }

    /// 写真ライブラリの許可（`PHAuthorizationStatus` を画面の外で扱える形に）
    enum LibraryAccess: Equatable {
        case authorized, limited, denied, restricted, notDetermined
    }

    /// 左下に最近の1枚を出すか。**許可を求めない**——すでに許されている（全部・一部）ときだけ。
    /// それ以外は写真の印の丸（押すと写真選びへ。埋め込みの写真選びは許可が要らない）
    static func showsRecentThumbnail(_ access: LibraryAccess) -> Bool {
        access == .authorized || access == .limited
    }

    /// 「写真から選ぶ」でカメラを閉じたあと、作る画面が写真選びを開くか。**まだ1枚も無ければ開かない**
    /// ——作る画面の下にもう最近の写真の格子（埋め込みの写真選び）が出ているので、閉じるだけで格子に戻る
    static func opensLibraryAfterCamera(shotCount: Int) -> Bool { shotCount > 0 }

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
        /// 2026-11-09: タイマーのカウントダウンの1秒ごとの刻み（軽く）
        case countdownTick
        /// カウントダウンを取り消した・フラッシュ／タイマー／倍率の段を選んだ（切り替えと同じ手ざわり）
        case countdownCancelled
        /// 2026-11-11: 録画を始めた直後（`stopGuardSeconds` より前）・始めている途中のタップを受けなかった。
        /// 押したのに何も起きないと感じさせないよう、軽く返す
        case tapIgnored
        case optionChanged
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
        case .countdownTick: return .impactLight
        case .countdownCancelled, .optionChanged: return .selection
        case .tapIgnored: return .impactLight
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
