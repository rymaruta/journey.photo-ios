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
/// **シャッターはタップで写真、長押しで動画**（離すと止まる）。動画モードのタップは「始める／止める」。
/// 上限は 60 秒（`StoryVideoRules.maxSeconds`）で自動で止まる。
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
    @StateObject private var camera = StoryCameraModel()

    @State private var mode: StoryCameraRules.Mode = .photo
    /// シャッターを押している最中か・押し始めの時刻（長押しの判定）
    @State private var pressing = false
    @State private var holdTask: Task<Void, Never>?
    @State private var recordingStartedByHold = false

    // 触覚（`StoryCameraRules.haptic(for:)` の対応どおり）
    @State private var photoTick = 0
    @State private var startTick = 0
    @State private var stopTick = 0
    @State private var modeTick = 0
    @State private var limitTick = 0
    @State private var failTick = 0


    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera.state {
            case .preparing:
                ProgressView().tint(.white)
            case .ready:
                StoryCameraPreview(session: camera.session)
                    .ignoresSafeArea()
                controls
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
        .onDisappear { camera.stop() }
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
            if !camera.isRecording { modePicker.padding(.bottom, 14) }
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
                Button {
                    camera.flip()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .disabled(camera.isRecording)
                .opacity(camera.isRecording ? 0.4 : 1)
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
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("story.camera.shutter")
        // 読み上げからは長押しができないので、操作で動画の始め／止めを出す
        .accessibilityAction { perform(StoryCameraRules.tapAction(mode: mode, isRecording: camera.isRecording)) }
    }

    private var shutterLabel: String {
        if camera.isRecording { return L("録画を止める", "Stop recording") }
        return mode == .photo ? L("写真を撮る（長押しで動画）", "Take a photo (hold for video)")
                              : L("録画を始める", "Start recording")
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
                          let action = StoryCameraRules.holdAction(isRecording: camera.isRecording) else { return }
                    recordingStartedByHold = true
                    perform(action, fromHold: true)
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                holdTask = nil
                let held = recordingStartedByHold
                pressing = false
                recordingStartedByHold = false
                if StoryCameraRules.releaseStopsRecording(startedByHold: held) {
                    perform(.stopRecording)
                } else {
                    perform(StoryCameraRules.tapAction(mode: mode, isRecording: camera.isRecording))
                }
            }
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

    private func perform(_ action: StoryCameraRules.ShutterAction, fromHold: Bool = false) {
        switch action {
        case .takePhoto:
            Task {
                guard let data = await camera.capturePhoto() else {
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
            Task {
                // 🔴 録画を始める前にマイクの許可を済ませる(まだ尋ねていなければ、ここでダイアログを出す)。
                // 写真モードの長押しもここを通る。断られても音なしで撮る(注記を出す)
                await camera.prepareAudio()
                // 長押しで始めるはずが、ダイアログの間に指が離れていたら始めない(もう一度押してもらう)
                guard StoryCameraRules.startsAfterPermission(fromHold: fromHold, stillPressing: pressing) else { return }
                guard camera.startRecording() else {
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
        state = .ready
    }

    func stop() {
        if movieOutput.isRecording {
            // 録画の途中で画面が閉じた(✕・下へ払った): 撮れたファイルの渡し先が無いので、止まったあとに消す
            abandoned = true
            movieOutput.stopRecording()
        }
        timer?.invalidate()
        timer = nil
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

    private static func camera(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
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

    // MARK: 写真

    func capturePhoto() async -> Data? {
        guard state == .ready, photoContinuation == nil else { return nil }
        applyRotation(to: photoOutput.connection(with: .video))
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            settings = AVCapturePhotoSettings()
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            photoContinuation = continuation
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: 動画

    /// 録画を始める。始められなければ false
    @discardableResult
    func startRecording() -> Bool {
        guard state == .ready, !isRecording, !movieOutput.isRecording,
              session.outputs.contains(movieOutput) else { return false }
        applyRotation(to: movieOutput.connection(with: .video))
        let url = StoryVideoPipeline.temporaryURL(ext: "mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
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
