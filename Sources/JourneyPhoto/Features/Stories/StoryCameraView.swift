import SwiftUI
import UIKit

/// ストーリーのカメラの入口（札 #500）。本物（`StoryCameraContent`）は Darwin だけ。
/// Linux の模型では撮影の場が無いので黒い面を返す（画面の型だけ。実機・Mac の CI で確かめる）
struct StoryCameraView: View {
    /// 撮れた写真（JPEG）。閉じる前に呼ぶ
    let onPhoto: (Data) -> Void
    /// 撮れた動画（呼ぶ側のものになる一時ファイル）
    let onVideo: (URL) -> Void

    static var isAvailable: Bool {
        #if canImport(Darwin)
        return CameraPicker.isAvailable
        #else
        return false
        #endif
    }

    var body: some View {
        #if canImport(Darwin)
        StoryCameraContent(onPhoto: onPhoto, onVideo: onVideo)
        #else
        Color.black
        #endif
    }
}

#if canImport(Darwin)
import AVFoundation

/// ストーリーのカメラ（札 #500・デザイナーのモック A 案「iPhone 型」）。
///
/// 全画面の映像の上に、上に ✕ と前後の切り替え、下に「写真｜動画」の切り替えとシャッター。
/// **シャッターはタップで写真、長押しで動画**。動画モードのタップは「始める／止める」。
/// 録画は**指を離しても続き、もう一度押すと止まる**（2026-11-11 判断・`StoryCameraRules.releaseOutcome`。
/// 以前は長押しの録画だけ離すと止まった）。上限は 60 秒（`StoryVideoRules.maxSeconds`）で自動で止まる。
/// アプリが前面でなくなった・撮影の場が中断されたときは録画を止める（撮れた分は渡す）。
///
/// **2026-11-09 仕上げ（インスタと遜色なく・第1弾）**: ピンチと倍率の丸（0.5×・1×・2× …は端末が許す段だけ）、
/// フラッシュ（オフ→オン→自動・背面だけ。動画は録画の間のライト）、タイマー（3 秒・10 秒・数字のカウントダウン・
/// タップで取り消し）、ハンズフリー録画（動画モードでタイマーを入れると、押さずに数えて始まり、次のタップか 60 秒で止まる）。
/// 決まりは `StoryCameraRules`。数えている間にアプリが前面でなくなった・撮影の場が中断された・画面を閉じたときは取り消す。
///
/// 既存の自前カメラ `ComposeCamera` は流用しない（2026-11-08 判断・札 #500）: 作例を重ねる撮影の場で、
/// 背面カメラ固定・写真だけ・マイクなし・ズームと露出の操作つき。ここは前後の切り替えと動画（マイク）が要り、
/// 持ち物が違う。**映像を出す部品と保存の道（`ComposeCamera.save`）だけ同じ考えで作り直した**。
///
/// 現在地は使わない（位置情報の許可を増やさない）。撮った写真・動画の位置は、取り込みの段で消す
/// （写真は `ImagePreparer`、動画は `StoryVideoPipeline.export`）。
struct StoryCameraContent: View {

    let onPhoto: (Data) -> Void
    let onVideo: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = StoryCameraModel()

    @State private var mode: StoryCameraRules.Mode = .photo
    /// シャッターを押している最中か・押し始めの時刻（長押しの判定）
    @State private var pressing = false
    @State private var holdTask: Task<Void, Never>?
    @State private var recordingStartedByHold = false
    /// 録画を始めている途中（マイクの用意・始める処理の間）。この間のタップは受けない（`pressIntent`）
    @State private var recordingStarting = false

    // 触覚（`StoryCameraRules.haptic(for:)` の対応どおり）
    @State private var photoTick = 0
    @State private var startTick = 0
    @State private var stopTick = 0
    @State private var modeTick = 0
    @State private var limitTick = 0
    @State private var failTick = 0
    @State private var countdownTickCount = 0
    @State private var optionTick = 0
    @State private var cancelTick = 0

    // フラッシュ・タイマー・数えている最中（開くたびに「オフ」から）
    @State private var flash: StoryCameraRules.Flash = .off
    @State private var timerOption: StoryCameraRules.TimerOption = .off
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    /// ピンチを始めたときのカメラの倍率
    @State private var pinchStart: Double?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera.state {
            case .preparing:
                ProgressView().tint(.white)
            case .ready:
                StoryCameraPreview(session: camera.session)
                    .ignoresSafeArea()
                // ピンチで寄る（映像の部品は指を受けないので、上に透明な面を重ねる。部品は更に上）
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .gesture(zoomGesture)
                    .accessibilityHidden(true)
                controls
                if let countdown { countdownNumber(countdown) }
            case .denied:
                notice(L("カメラの許可がありません", "Camera access is off"),
                       detail: L("設定でカメラを許可すると、ここで撮れます。写真アプリから選ぶこともできます。",
                                 "Allow the camera in Settings to shoot here. You can also choose from your library."),
                       showsSettings: true)
            case .unavailable:
                notice(L("この端末ではカメラを使えません", "The camera isn't available on this device"),
                       detail: L("写真アプリから選んでください。", "Choose from your library instead."),
                       showsSettings: false)
            }
        }
        .task { await camera.start() }
        .onDisappear {
            // 長押しの 0.4 秒の間に閉じると、stop() のあとに録画が始まってしまう
            holdTask?.cancel()
            holdTask = nil
            cancelCountdown()
            camera.stop()
        }
        // 数えている間にアプリが前面でなくなった（電話・通知センター・ホームへ戻る）・撮影の場が中断された
        .onChange(of: scenePhase) { _, phase in
            if !StoryCameraRules.countdownContinues(sceneActive: phase == .active, sessionInterrupted: false,
                                                    cameraReady: camera.state == .ready) {
                cancelCountdown(announce: true)
            }
            // 2026-11-11 判断: 録画は離しても続くので、前面でなくなったら**必ず止める**（撮れた分は渡す）。
            // 押している途中の状態も消す（指を受け取れなくなった押しを、次の押しに持ち越さない）
            if phase != .active {
                releasePress()
                perform(.stopRecording)
            }
        }
        .onChange(of: camera.interruptions) { _, _ in
            cancelCountdown(announce: true)
            releasePress()
            perform(.stopRecording)
        }
        .onChange(of: camera.finished) { _, finished in
            guard let finished else { return }
            handle(finished)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: photoTick)
        .sensoryFeedback(.impact(weight: .heavy), trigger: startTick)
        .sensoryFeedback(.impact(weight: .light), trigger: stopTick)
        .sensoryFeedback(.selection, trigger: modeTick)
        .sensoryFeedback(.warning, trigger: limitTick)
        .sensoryFeedback(.error, trigger: failTick)
        // タイマーの刻みは軽く・選んだときと取り消しは切り替えと同じ
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: countdownTickCount)
        .sensoryFeedback(.selection, trigger: optionTick)
        .sensoryFeedback(.selection, trigger: cancelTick)
    }

    // MARK: - 部品

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if StoryCameraRules.showsMicNote(micDenied: camera.micDenied, mode: mode, isRecording: camera.isRecording) {
                Text(L("マイクが許可されていないので、音なしで撮ります", "The microphone is off, so the video will have no sound"))
                    .font(JPFont.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("story.camera.micNote")
            }
            if StoryCameraRules.showsZoomPills(presetCount: camera.zoomLevels.presets.count) {
                zoomPills.padding(.bottom, 10)
            }
            // 録画・カウントダウン中も場所は残す（消すと倍率の丸とシャッターの間が詰まって下へ落ちる）
            let modeLocked = !StoryCameraRules.allowsModeAndFlip(isRecording: camera.isRecording,
                                                                 counting: countdown != nil)
            modePicker
                .opacity(modeLocked ? 0 : 1)
                .allowsHitTesting(!modeLocked)
                .accessibilityHidden(modeLocked)
                // 録画中は、隠した切り替えの場所に「押すと止まります」（2026-11-11 判断・離しても止まらないので）
                .overlay {
                    if camera.isRecording { stopHint }
                }
                .padding(.bottom, 14)
            shutter.padding(.bottom, 28)
        }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel(Labels.Common.close)
                .accessibilityIdentifier("story.camera.close")
                Spacer()
                // フラッシュ・タイマー（録画中・数えている間は変えさせない）
                if !camera.isRecording && countdown == nil {
                    if StoryCameraRules.showsFlash(hasFlash: camera.hasFlash, isRecording: camera.isRecording,
                                                   counting: countdown != nil) {
                        flashButton
                    }
                    timerButton
                }
                Button {
                    camera.flip()
                    // 前後で倍率の段が変わる（背面は 0.5×・前面は 1× と 2× …）。映像は 1× から始まる
                    pinchStart = nil
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .disabled(!StoryCameraRules.allowsModeAndFlip(isRecording: camera.isRecording,
                                                              counting: countdown != nil))
                .opacity(StoryCameraRules.allowsModeAndFlip(isRecording: camera.isRecording,
                                                            counting: countdown != nil) ? 1 : 0.4)
                .accessibilityLabel(L("前後のカメラを切り替える", "Switch camera"))
                .accessibilityIdentifier("story.camera.flip")
            }
            if camera.isRecording {
                recordingBadge
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// フラッシュ（オフ→オン→自動）。選んでいる（オン・自動）ときは白い丸い札に黒い記号
    /// （「写真｜動画」の選んでいる札と同じ。写真の上なので白・真鍮は置かない。形でも状態が分かる）
    private var flashButton: some View {
        Button {
            flash = flash.next
            optionTick += 1
        } label: {
            Image(systemName: flash.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(flash.isActive ? Color.black : Color.white)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .background(flash.isActive ? Color.white : Color.black.opacity(0.35), in: Circle())
        }
        .accessibilityLabel(flash.accessibilityLabel)
        .accessibilityHint(L("押すたびにオフ・オン・自動が替わります", "Cycles through off, on and auto"))
        .accessibilityIdentifier("story.camera.flash")
    }

    /// タイマー（オフ→3秒→10秒）。入れているときは秒数も字で出す（色・形だけで伝えない）
    private var timerButton: some View {
        Button {
            timerOption = timerOption.next
            optionTick += 1
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.body.weight(.semibold))
                if timerOption.isActive {
                    Text("\(timerOption.seconds)")
                        .font(JPFont.mono(12, medium: true, relativeTo: .caption))
                }
            }
            .foregroundStyle(timerOption.isActive ? Color.black : Color.white)
            .padding(.horizontal, timerOption.isActive ? 10 : 0)
            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            .background(timerOption.isActive ? Color.white : Color.black.opacity(0.35), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(timerOption.accessibilityLabel)
        .accessibilityHint(L("押すたびにオフ・3秒・10秒が替わります。入れると押さずに撮れます",
                             "Cycles through off, 3 and 10 seconds. With a timer on, you can shoot hands-free"))
        .accessibilityIdentifier("story.camera.timerOption")
    }

    /// 倍率の丸（標準のカメラ App・`ComposeGuideView.zoomPills` と同じ形）。写真（映像）の上なので、
    /// 選んでいる段の字は白（真鍮は黒い地の上だけ）。段が1つの端末では出さない
    private var zoomPills: some View {
        let levels = camera.zoomLevels
        let display = levels.display(factor: camera.zoomFactor)
        let active = ComposeControls.activePreset(display: display, presets: levels.presets)
        return HStack(spacing: 0) {
            ForEach(levels.presets, id: \.self) { preset in
                let on = preset == active
                Button {
                    camera.setZoom(display: preset, animated: !reduceMotion)
                    optionTick += 1
                } label: {
                    Text(ComposeControls.zoomLabel(on ? display : preset, active: on))
                        .font(JPFont.mono(12, medium: true, relativeTo: .caption))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(minWidth: on ? 36 : 30, minHeight: on ? 36 : 30)
                        .background(Color.white.opacity(on ? 0.28 : 0.1), in: Capsule())
                        .background(Color.black.opacity(0.35), in: Capsule())
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ComposeControls.zoomAccessibility(preset))
                .accessibilityValue(on ? L("選択中", "Selected") : "")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier(ComposeControls.zoomIdentifier(preset).replacingOccurrences(
                    of: "composeGuide.zoom.", with: "story.camera.zoom."))
            }
        }
    }

    /// つまんで寄る（始めの倍率からの割合・範囲は端末の許す内）
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? camera.zoomFactor
                if pinchStart == nil { pinchStart = start }
                camera.setZoom(factor: ComposeControls.pinchedFactor(start: start,
                                                                     magnification: Double(value.magnification),
                                                                     levels: camera.zoomLevels),
                               animated: false)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// カウントダウンの数字（画面の真ん中・写真の上なので白に影）。動きを減らす設定では拡大の動きを付けない。
    /// 読み上げは数字ごとに声で知らせるので、この絵は読み上げから外す
    private func countdownNumber(_ value: Int) -> some View {
        Text("\(value)")
            .jpSystemFont(96, weight: .light, relativeTo: .largeTitle)
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.5), radius: 12)
            .id(value)
            .transition(reduceMotion ? .opacity : .scale(scale: 1.4).combined(with: .opacity))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .accessibilityIdentifier("story.camera.countdown")
    }

    /// 録画の時間（赤い点＋0:07）。点は動きを減らす設定のときは点滅させない
    private var recordingBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(WebTheme.danger)
                .frame(width: 8, height: 8)
                .opacity(reduceMotion ? 1 : (Int(camera.elapsed * 2) % 2 == 0 ? 1 : 0.3))
            Text(StoryVideoClip.label(camera.elapsed))
                .font(JPFont.footnote)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, JPSpace.s)
        .frame(minHeight: 30)
        .background(Color.black.opacity(0.45), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("録画中 \(StoryVideoClip.label(camera.elapsed))", "Recording \(StoryVideoClip.label(camera.elapsed))"))
        .accessibilityIdentifier("story.camera.timer")
    }

    /// 録画中の案内（マイクの注記と同じ黒い札に白い字。写真の上なので白・真鍮は置かない）。
    /// 読み上げはシャッターの名前とヒントで伝えるので、ここは読み上げから外す
    private var stopHint: some View {
        Text(StoryCameraRules.stopHint)
            .font(JPFont.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6), in: Capsule())
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .accessibilityIdentifier("story.camera.stopHint")
    }

    /// 「写真｜動画」の切り替え。選んでいるほうが白い丸い札（写真の上なので白・真鍮は置かない）
    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach([StoryCameraRules.Mode.photo, .video], id: \.label) { item in
                Button {
                    guard mode != item else { return }
                    mode = item
                    modeTick += 1
                    if item == .video { Task { await camera.prepareAudio() } }
                } label: {
                    Text(item.label)
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(mode == item ? Color.black : Color.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .background(mode == item ? Color.white : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
                .accessibilityIdentifier(item == .photo ? "story.camera.mode.photo" : "story.camera.mode.video")
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.45), in: Capsule())
    }

    /// シャッター。外の輪は録画の進み具合（60 秒で一周）、内側は写真が白・動画が赤
    private var shutter: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 4).frame(width: 78, height: 78)
            if camera.isRecording {
                Circle()
                    .trim(from: 0, to: StoryCameraRules.progress(elapsed: camera.elapsed))
                    .stroke(WebTheme.danger, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 90, height: 90)
                RoundedRectangle(cornerRadius: 8).fill(WebTheme.danger).frame(width: 30, height: 30)
            } else if countdown != nil {
                // 数えている間は「取り消し」（押すと止まる）
                Circle().fill(Color.white).frame(width: 62, height: 62)
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.black)
            } else {
                Circle()
                    .fill(mode == .video ? WebTheme.danger : Color.white)
                    .frame(width: 62, height: 62)
                    // 押している間は少し縮む。動きを減らす設定では縮めない
                    .scaleEffect(pressing && !reduceMotion ? 0.88 : 1)
            }
        }
        .frame(width: 96, height: 96)
        .contentShape(Circle())
        .gesture(shutterGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shutterLabel)
        .accessibilityHint(shutterHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("story.camera.shutter")
        // 読み上げからは長押しができないので、操作で動画の始め／止めを出す
        .accessibilityAction { press(currentPressIntent) }
    }

    private var shutterLabel: String {
        if countdown != nil { return L("カウントダウンを取り消す", "Cancel countdown") }
        if camera.isRecording { return L("録画を止める", "Stop recording") }
        let seconds = timerOption.seconds
        if timerOption.isActive {
            return mode == .photo ? L("\(seconds)秒後に写真を撮る", "Take a photo in \(seconds) seconds")
                                  : L("\(seconds)秒後に録画を始める（押さずに撮れます）",
                                      "Start recording in \(seconds) seconds (hands-free)")
        }
        return mode == .photo ? L("写真を撮る（長押しで動画）", "Take a photo (hold for video)")
                              : L("録画を始める", "Start recording")
    }

    /// 読み上げのヒント。録画中は「押すと止まります」、写真モードは長押しの録画の止め方も添える
    private var shutterHint: String {
        if countdown != nil { return "" }
        if camera.isRecording || recordingStarting { return StoryCameraRules.stopHint }
        if timerOption.isActive { return "" }
        return mode == .photo ? L("長押しで録画が始まります。もう一度押すと止まります",
                                  "Hold to start recording. Tap again to stop")
                              : L("もう一度押すと止まります", "Tap again to stop")
    }

    /// いまシャッターをタップしたときにすること（タイマー・数えている最中を含む）
    private var currentPressIntent: StoryCameraRules.PressIntent {
        StoryCameraRules.pressIntent(mode: mode, isRecording: camera.isRecording, recordedSeconds: camera.elapsed,
                                     starting: recordingStarting, timer: timerOption, counting: countdown != nil)
    }

    private var shutterGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressing else { return }
                pressing = true
                recordingStartedByHold = false
                holdTask?.cancel()
                holdTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(StoryCameraRules.holdThreshold * 1_000_000_000))
                    guard !Task.isCancelled, pressing,
                          let action = StoryCameraRules.holdAction(isRecording: camera.isRecording || recordingStarting,
                                                                   timer: timerOption,
                                                                   counting: countdown != nil) else { return }
                    recordingStartedByHold = true
                    perform(action, fromHold: true)
                }
            }
            .onEnded { _ in
                let held = recordingStartedByHold
                releasePress()
                // 長押しで始めた録画は、離しても止めない（もう一度押すか 60 秒で止まる・2026-11-11 判断）
                switch StoryCameraRules.releaseOutcome(startedByHold: held) {
                case .keepRecording: break
                case .tap: press(currentPressIntent)
                }
            }
    }

    /// 押している途中の状態を消す（指を離した・アプリが前面でなくなった・撮影の場が中断された）
    private func releasePress() {
        holdTask?.cancel()
        holdTask = nil
        pressing = false
        recordingStartedByHold = false
    }

    private func notice(_ title: String, detail: String, showsSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(JPFont.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .multilineTextAlignment(.center)
            if showsSettings {
                Button(L("設定を開く", "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .jpPillButton(.main(onPhoto: true))
                .accessibilityIdentifier("story.camera.openSettings")
            }
            Button(L("閉じる", "Close")) { dismiss() }
                .jpPillButton(.outline)
                .accessibilityIdentifier("story.camera.close")
        }
        .padding(.horizontal, 32)
    }

    // MARK: - 動作

    /// シャッターのタップ（タイマーで数える・数えている最中は取り消す・そうでなければ撮る／始める／止める）
    private func press(_ intent: StoryCameraRules.PressIntent) {
        switch intent {
        case .perform(let action):
            perform(action)
        case .startCountdown(let action):
            startCountdown(then: action)
        case .cancelCountdown:
            cancelCountdown(announce: true)
        case .ignore:
            break
        }
    }

    /// 数えてから `action` をする。**動画（ハンズフリー）は数える前にマイクの許可を済ませる**
    /// （数えている途中にダイアログが出て、カウントが止まる・取り消されるのを防ぐ）。
    /// 取り消し（もう一度押す・アプリが裏へ行く・電話・画面を閉じる）は `cancelCountdown`
    private func startCountdown(then action: StoryCameraRules.ShutterAction) {
        guard countdownTask == nil, timerOption.isActive else { return }
        let option = timerOption
        countdownTask = Task {
            if action == .startRecording { await camera.prepareAudio() }
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(
                StoryCameraRules.countdownAnnouncement(seconds: option.seconds, action: action)).post()
            for number in StoryCameraRules.countdownSequence(option) {
                if reduceMotion {
                    countdown = number
                } else {
                    withAnimation(.easeOut(duration: 0.25)) { countdown = number }
                }
                countdownTickCount += 1
                try? await Task.sleep(nanoseconds: UInt64(StoryCameraRules.countdownStepSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            countdown = nil
            countdownTask = nil
            perform(action)
        }
    }

    /// 数えるのをやめる（数えていなければ何もしない）。`announce` は読み上げと触覚で知らせる（自分で押した・裏へ行った）
    private func cancelCountdown(announce: Bool = false) {
        guard countdownTask != nil || countdown != nil else { return }
        // 数字がまだ出ていない（マイクの許可を待っていた）ときは、知らせない
        let visible = countdown != nil
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        if announce && visible {
            cancelTick += 1
            AccessibilityNotification.Announcement(StoryCameraRules.countdownCancelledAnnouncement).post()
        }
    }

    private func perform(_ action: StoryCameraRules.ShutterAction, fromHold: Bool = false) {
        switch action {
        case .takePhoto:
            Task {
                guard let data = await camera.capturePhoto(flash: flash) else {
                    failTick += 1
                    return
                }
                photoTick += 1
                // 撮った原本は端末にも残す（投稿せずに閉じても残る・前のカメラと同じ）
                Task.detached(priority: .utility) { _ = await ComposeCamera.save(data) }
                onPhoto(data)
                dismiss()
            }
        case .startRecording:
            // 始めている途中にもう一度始めない（二度押し・長押しとタップの重なり）
            guard !recordingStarting, !camera.isRecording else { return }
            recordingStarting = true
            Task {
                defer { recordingStarting = false }
                // 🔴 録画を始める前にマイクの許可を済ませる(まだ尋ねていなければ、ここでダイアログを出す)。
                // 写真モードの長押しもここを通る。断られても音なしで撮る(注記を出す)
                await camera.prepareAudio()
                // 長押しで始めるはずが、ダイアログの間に指が離れていたら始めない(もう一度押してもらう)
                guard StoryCameraRules.startsAfterPermission(fromHold: fromHold, stillPressing: pressing) else { return }
                guard camera.startRecording(flash: flash) else {
                    failTick += 1
                    return
                }
                startTick += 1
            }
        case .stopRecording:
            guard camera.isRecording else { return }
            camera.stopRecording()
        }
    }

    /// 録画が終わった（止めた・上限に着いた・失敗）
    private func handle(_ finished: StoryCameraModel.Finished) {
        switch finished.result {
        case .saved(let url):
            if finished.hitLimit { limitTick += 1 } else { stopTick += 1 }
            UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
            onVideo(url)
            dismiss()
        case .failed:
            failTick += 1
        }
    }
}

/// カメラの映像（全画面・縦横比を保って埋める）
private struct StoryCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        // 映像は押す物ではない（指はシャッターなど上の部品へ通す）
        view.isUserInteractionEnabled = false
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// 撮影の場（`AVCaptureSession`）。写真（`AVCapturePhotoOutput`）と動画（`AVCaptureMovieFileOutput`）を1本の場で持つ
@MainActor
final class StoryCameraModel: NSObject, ObservableObject {

    enum State: Equatable { case preparing, ready, denied, unavailable }

    struct Finished: Equatable {
        enum Result: Equatable { case saved(URL), failed }
        let id = UUID()
        let result: Result
        /// 上限（60 秒）で止まったか
        let hitLimit: Bool
    }

    @Published private(set) var state: State = .preparing
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var micDenied = false
    @Published private(set) var finished: Finished?
    /// 拡大の段（端末のレンズから・`ComposeControls.zoomLevels` を使い回す）。組み立てるまでは 1× だけ
    @Published private(set) var zoomLevels = ComposeControls.zoomLevels(hasUltraWide: false, switchOver: [],
                                                                         minFactor: 1, maxFactor: 1)
    /// いまのカメラの倍率（`videoZoomFactor`）
    @Published private(set) var zoomFactor = 1.0
    /// フラッシュ（写真）・ライト（動画）が使えるか。**背面のカメラだけ**
    @Published private(set) var hasFlash = false
    /// 撮影の場が中断された回数（電話・ほかのアプリがカメラを使う）。画面はカウントダウンを取り消す
    @Published private(set) var interruptions = 0

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "photo.journey.story.camera")
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var timer: Timer?
    private var recordingStartedAt: Date?
    /// 録画の途中で画面が閉じた。止まったファイルは誰にも渡さず消す(孤児にしない)
    private var abandoned = false
    private var photoContinuation: CheckedContinuation<Data?, Never>?
    private var interruptionObserver: NSObjectProtocol?

    // MARK: 始める・止める

    func start() async {
        guard AVCaptureDevice.default(for: .video) != nil else {
            state = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        guard configureIfNeeded() else {
            state = .unavailable
            return
        }
        await run(true)
        startObservingInterruptions()
        state = .ready
    }

    /// 撮影の場が中断されたら数える（`interruptions`）。画面を閉じるとき（`stop`）と消えるとき（deinit）に外す
    private func startObservingInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.interruptions += 1 }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func stop() {
        if movieOutput.isRecording {
            // 録画の途中で画面が閉じた(✕・下へ払った): 撮れたファイルの渡し先が無いので、止まったあとに消す
            abandoned = true
            movieOutput.stopRecording()
        }
        timer?.invalidate()
        timer = nil
        setTorch(.off)
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    private func run(_ on: Bool) async {
        let session = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if on { session.startRunning() } else { session.stopRunning() }
                continuation.resume()
            }
        }
    }

    /// 背面は**仮想カメラ（三眼・二眼）を先に**（`ComposeCamera.backCamera`・倍率だけで超広角・広角・望遠を OS が
    /// 切り替える。0.5× が出せる）。前面は広角1つ
    private static func camera(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back { return ComposeCamera.backCamera() }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// 流し始める前に 1× の倍率にしておく（三眼・二眼の広角は倍率 1 が超広角＝0.5×。後から合わせると
    /// 開いた瞬間に 0.5× の映像が見える・`ComposeCamera.run` と同じ理由）。組み立ての中（`beginConfiguration` の間）で呼ぶ
    private func applyOneTimesZoom(to device: AVCaptureDevice) {
        let levels = ComposeCamera.levels(for: device)
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = CGFloat(levels.factor(display: 1))
            device.unlockForConfiguration()
        }
        zoomLevels = levels
        zoomFactor = levels.factor(display: 1)
        hasFlash = device.position == .back && (device.hasFlash || device.hasTorch)
    }

    private func configureIfNeeded() -> Bool {
        guard videoInput == nil else { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard let device = Self.camera(.back), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        videoInput = input
        applyOneTimesZoom(to: device)
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        guard session.canAddOutput(photoOutput) else { return false }
        session.addOutput(photoOutput)
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            // 上限で自動で止める（`AVError.maximumDurationReached` が返る。ファイルは使える）
            movieOutput.maxRecordedDuration = CMTime(seconds: StoryVideoRules.maxSeconds, preferredTimescale: 600)
        }
        return true
    }

    /// 動画の音（マイク）。**動画モードに入ったときに初めて尋ねる**。断られても音なしで撮れる
    func prepareAudio() async {
        guard audioInput == nil else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                micDenied = true
                return
            }
        default:
            micDenied = true
            return
        }
        guard let mic = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: mic) else {
            return
        }
        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }
        session.commitConfiguration()
    }

    func flip() {
        guard !isRecording else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        guard let device = Self.camera(next), let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        if let old = videoInput { session.removeInput(old) }
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            position = next
            applyOneTimesZoom(to: device)
            rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        } else if let old = videoInput {
            session.addInput(old)
        }
        session.commitConfiguration()
    }

    /// 撮る向きは端末の向きに合わせる(2026-10-10 判断・`ComposeCamera.capture` と同じ求め方)。
    /// 向きの係(`RotationCoordinator`)の `videoRotationAngleForHorizonLevelCapture` をそのまま使い、
    /// 係が無いとき(組み立て前)は縦(90°)——`ComposeGuide.captureAngle`。以前は縦に決め打ちで、横に持って撮ると横倒しで残った
    private func applyRotation(to connection: AVCaptureConnection?) {
        guard let connection else { return }
        let angle = CGFloat(ComposeGuide.captureAngle(
            coordinator: rotation.map { Double($0.videoRotationAngleForHorizonLevelCapture) }))
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: 拡大・ライト

    /// 画面の倍率（0.5×・1×・2× …）へ寄る。段のボタンは滑らかに（`ramp`）
    func setZoom(display: Double, animated: Bool) {
        setZoom(factor: zoomLevels.factor(display: display), animated: animated)
    }

    /// カメラの倍率へ寄る（ピンチは滑らかにせずそのまま）。範囲は端末の許す内
    func setZoom(factor: Double, animated: Bool) {
        guard let device = videoInput?.device else { return }
        let target = min(max(factor, zoomLevels.minFactor), zoomLevels.maxFactor)
        zoomFactor = target
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if animated {
                device.ramp(toVideoZoomFactor: CGFloat(target), withRate: 8)
            } else {
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = CGFloat(target)
            }
            device.unlockForConfiguration()
        }
    }

    /// 動画のライト（`torchMode`）。録画の間だけ点ける。使えない・背面でないときは何もしない
    private func setTorch(_ mode: AVCaptureDevice.TorchMode) {
        guard let device = videoInput?.device, device.hasTorch else { return }
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isTorchAvailable, device.isTorchModeSupported(mode) { device.torchMode = mode }
            device.unlockForConfiguration()
        }
    }

    // MARK: 写真

    /// 写真を撮る。`flash` は背面で、端末が許す設定のときだけ当てる（許さない設定を渡すと撮影が例外で落ちる）
    func capturePhoto(flash: StoryCameraRules.Flash = .off) async -> Data? {
        guard state == .ready, photoContinuation == nil else { return nil }
        applyRotation(to: photoOutput.connection(with: .video))
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            settings = AVCapturePhotoSettings()
        }
        if hasFlash, photoOutput.supportedFlashModes.contains(flash.captureMode) {
            settings.flashMode = flash.captureMode
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            photoContinuation = continuation
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: 動画

    /// 録画を始める。始められなければ false
    @discardableResult
    func startRecording(flash: StoryCameraRules.Flash = .off) -> Bool {
        guard state == .ready, !isRecording, !movieOutput.isRecording,
              session.outputs.contains(movieOutput) else { return false }
        applyRotation(to: movieOutput.connection(with: .video))
        let url = StoryVideoPipeline.temporaryURL(ext: "mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        // 動画のフラッシュは録画の間だけ点くライト（オン＝点けっぱなし・自動＝端末まかせ）
        if hasFlash { setTorch(flash.torchMode) }
        isRecording = true
        elapsed = 0
        recordingStartedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        return true
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    private func tick() {
        guard let started = recordingStartedAt else { return }
        elapsed = min(StoryVideoRules.maxSeconds, Date().timeIntervalSince(started))
    }

    fileprivate func recordingEnded(url: URL, success: Bool, hitLimit: Bool) {
        timer?.invalidate()
        timer = nil
        setTorch(.off)
        isRecording = false
        recordingStartedAt = nil
        if abandoned || !success {
            // 渡し先が無い・失敗: ファイルはここで消す(画面側は失敗の知らせだけ受ける)
            try? FileManager.default.removeItem(at: url)
            if abandoned { return }
        }
        finished = Finished(result: success ? .saved(url) : .failed, hitLimit: hitLimit)
    }

    fileprivate func photoFinished(_ data: Data?) {
        photoContinuation?.resume(returning: data)
        photoContinuation = nil
    }
}

/// フラッシュの設定を、写真（`flashMode`）と動画のライト（`torchMode`）の値に直す
extension StoryCameraRules.Flash {
    var captureMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }

    var torchMode: AVCaptureDevice.TorchMode {
        switch self {
        case .off: return .off
        case .on: return .on
        case .auto: return .auto
        }
    }
}

extension StoryCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        Task { @MainActor in self.photoFinished(data) }
    }
}

extension StoryCameraModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        // 上限で止まったときも `error` が返るが、ファイルは使える（`AVErrorRecordingSuccessfullyFinishedKey`）
        let nsError = error as NSError?
        let hitLimit = nsError?.code == AVError.maximumDurationReached.rawValue
        let finishedFine = nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        let success = error == nil || finishedFine
        Task { @MainActor in self.recordingEnded(url: outputFileURL, success: success, hitLimit: hitLimit) }
    }
}

#endif
