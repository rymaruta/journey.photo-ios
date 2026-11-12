import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// プロフィールの QR（札 #545 の第1段・2026-11-12）。入口は**マイページの名前の横**（owner の決定。マイページで
/// 変えるのはこの1点だけ）。QR は本人にだけ見える（自分のマイページにしか入口が無い）。
///
/// **1枚の画面で「自分の QR を見せる」と「読み取る」を切り替える**（他のアプリのように2つの画面に分けない・指示）。
/// 切り替えは繋がったセグメント（板 Components の「表示の切替」・行った県の地図と同じ形）。
///
/// - 見せる: 白い地に黒の QR（読み取れるのは明るい地の暗い点だけ）・名前・@名・一言。
///   中身は `ProfileQRSource` が作る（今は公開プロフィールの URL。承認のあと更新できる合図に替える・2026-11-12 owner）
/// - 読み取る: アプリの中のカメラ。**journey-photo.com の人の URL なら、この画面の上にその人の頁を開く**
///   （`UserProfileView`）。ほかの QR は開かない（外のサイトへ連れ出さない）。自分の QR は「あなたの QR です」と言うだけ
///
/// 第2段（iPhone のカメラで読んだらアプリが開く・Associated Domains・Team ID・CloudFront）は作らない——Apple の設定が要る
struct ProfileQRView: View {

    enum Mode: Hashable { case show, scan }

    let profile: UserProfile
    /// QR の中身を作る所（`ProfileQRSources.current`・試験と画面写真で替えられる）
    let source: any ProfileQRSource
    @State private var mode: Mode
    /// 見せる QR の中身（読み込み中・失敗・できた）
    @State private var code: CodeState = .loading
    /// 読み取って開く人（この画面の上に積む）
    @State private var opened: OpenedPerson?

    enum CodeState: Equatable { case loading, failed, ready(URL) }

    init(profile: UserProfile, source: any ProfileQRSource = ProfileQRSources.current, startsWith mode: Mode = .show) {
        self.profile = profile
        self.source = source
        _mode = State(initialValue: mode)
    }

    struct OpenedPerson: Hashable { let userId: String }

    var body: some View {
        VStack(spacing: JPSpace.l) {
            modePicker
            Group {
                switch mode {
                case .show:
                    showPane
                case .scan:
                    ProfileQRScanPane(myUserId: profile.userId, source: source) { userId in
                        opened = OpenedPerson(userId: userId)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, JPSpace.l)
        .padding(.top, JPSpace.s)
        .webScreen()
        .navigationTitle(ProfileQRText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
        }
        .navigationDestination(item: $opened) { person in
            UserProfileView(userId: person.userId)
        }
    }

    // MARK: - 切り替え

    /// 見せる／読み取る（繋がったセグメント・行った県の地図の `modePicker` と同じ形）
    private var modePicker: some View {
        HStack(spacing: 2) {
            segment(.show, title: ProfileQRText.showTab, id: "profileQR.mode.show")
            segment(.scan, title: ProfileQRText.scanTab, id: "profileQR.mode.scan")
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: JPRadius.field))
    }

    private func segment(_ value: Mode, title: String, id: String) -> some View {
        Button { mode = value } label: {
            Text(title)
                .font(mode == value ? JPFont.bodyEmphasis : JPFont.body)
                .foregroundStyle(mode == value ? WebTheme.foreground : WebTheme.text2)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .background(mode == value ? WebTheme.surface8 : Color.clear,
                            in: RoundedRectangle(cornerRadius: JPRadius.s))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    // MARK: - 見せる

    private var showPane: some View {
        VStack(spacing: JPSpace.l) {
            switch code {
            case .ready(let url):
                if let image = ProfileQRImage.make(url.absoluteString) {
                    codeImage(image)
                } else {
                    failedNote
                }
            case .loading:
                // 白い札と同じ大きさの空き（できたときに下の名前が跳ねない）
                RoundedRectangle(cornerRadius: JPRadius.l)
                    .fill(WebTheme.surface8)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: ProfileQRText.codeSide)
                    .overlay { ProgressView().tint(WebTheme.text2) }
                    .accessibilityLabel(ProfileQRText.loading)
                    .accessibilityIdentifier("profileQR.loading")
            case .failed:
                failedNote
            }
            VStack(spacing: JPSpace.xxs) {
                Text(profile.name)
                    .font(JPFont.cardTitle)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                if let username = profile.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                }
            }
            Text(ProfileQRText.showHint)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // ここに「QR コードを更新」（古い QR は使えなくなる）を置く——**承認のあとに作る**（2026-11-12 owner の要望・
            // `ProfileQRSource.canRenew`）。今の仮の中身（公開プロフィールの URL）は取り替えられないので出さない
        }
        .frame(maxWidth: .infinity)
        .padding(.top, JPSpace.m)
        .task(id: profile.userId) { await loadCode() }
    }

    /// 中身を作る（`ProfileQRSource`）。承認のあとはサーバーに聞くので、読み込み中と失敗を持つ
    private func loadCode() async {
        code = .loading
        do {
            code = .ready(try await source.code(for: profile.userId))
        } catch {
            code = .failed
        }
    }

    private func codeImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            // 読み取りの決まり（明るい地に暗い点・周りに余白）。写真ではないので白い面のまま
            .padding(JPSpace.m)
            .background(Color.white, in: RoundedRectangle(cornerRadius: JPRadius.l))
            .frame(maxWidth: ProfileQRText.codeSide)
            .accessibilityLabel(ProfileQRText.codeLabel(profile.name))
            .accessibilityIdentifier("profileQR.code")
    }

    /// 作れなかった（id が URL に入れられない形・承認のあとは電波など）。空の白い四角を出さず、もう一度の口を置く
    private var failedNote: some View {
        VStack(spacing: JPSpace.s) {
            Text(ProfileQRText.cannotMake)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text2)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadCode() }
            } label: {
                Text(ProfileQRText.retry)
                    .jpPillButton(.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profileQR.retry")
        }
        .padding(.top, JPSpace.emptyTop)
        .accessibilityIdentifier("profileQR.failed")
    }
}

/// QR の画面の文（英語も）。試験が同じ文を見る
enum ProfileQRText {
    static var title: String { L("プロフィールの QR", "Profile QR code") }
    static var showTab: String { L("自分の QR", "My QR code") }
    static var scanTab: String { L("読み取る", "Scan") }
    static var entryLabel: String { L("プロフィールの QR", "Profile QR code") }
    static var showHint: String {
        L("相手に読み取ってもらうと、あなたのページが開きます", "When someone scans this, your page opens")
    }
    static var scanHint: String {
        L("Journey Photo の QR を枠の中に入れてください", "Fit a Journey Photo QR code inside the frame")
    }
    static var notOurs: String {
        L("Journey Photo の人の QR ではありません", "This isn't a Journey Photo profile QR code")
    }
    static var yours: String { L("あなたの QR です", "That's your own QR code") }
    static var denied: String {
        L("カメラの使用が許可されていません。iPhone の設定から許可すると読み取れます",
          "Camera access is off. Allow it in iPhone Settings to scan")
    }
    static var openSettings: String { L("設定を開く", "Open Settings") }
    static var unavailable: String { L("この端末ではカメラを使えません", "The camera isn't available on this device") }
    static var cannotMake: String { L("QR を作れませんでした", "Couldn't make the QR code") }
    static var retry: String { L("もう一度", "Try again") }
    static var loading: String { L("QR を用意しています", "Preparing your QR code") }
    static var passNotValid: String {
        L("この QR は使えなくなっています", "This QR code is no longer valid")
    }
    static func codeLabel(_ name: String) -> String {
        L("\(name) のプロフィールの QR", "Profile QR code for \(name)")
    }
    /// QR の白い札の幅の上限（画面の幅が広くても大きくしすぎない）
    static let codeSide: CGFloat = 280
}

/// URL から QR の絵を作る（Core Image の `CIQRCodeGenerator`・端末の中だけ）。点1つが1画素の小さい絵で返し、
/// 画面が `.interpolation(.none)` で引き伸ばす（にじまない）
enum ProfileQRImage {
    static func make(_ text: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        // 誤り訂正は「M」（15%）。画面に出して読ませるので、点を細かくしすぎない
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 読み取る

/// 読み取りの面（カメラの映像・白い枠・一言）。人の URL を読んだら `onFound` で id を渡す
struct ProfileQRScanPane: View {
    let myUserId: String
    /// 合図（`/qr?t=<合図>`）を人に引く所（`ProfileQRSource.resolve`）
    let source: any ProfileQRSource
    let onFound: (String) -> Void

    @StateObject private var scanner = ProfileQRScanner()
    @Environment(\.openURL) private var openURL
    /// 読んだものが人の QR ではなかった・自分の QR だった（一言を替える）
    @State private var note: String?

    var body: some View {
        VStack(spacing: JPSpace.m) {
            ZStack {
                Color.black
                switch scanner.state {
                case .running:
                    ProfileQRPreview(session: scanner.session)
                case .preparing:
                    ProgressView()
                        .tint(WebTheme.text2)
                case .denied:
                    VStack(spacing: JPSpace.s) {
                        Text(ProfileQRText.denied)
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Text(ProfileQRText.openSettings)
                                .jpPillButton(.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profileQR.openSettings")
                    }
                    .padding(JPSpace.l)
                case .unavailable:
                    Text(ProfileQRText.unavailable)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.text2)
                        .multilineTextAlignment(.center)
                        .padding(JPSpace.l)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: ProfileQRText.codeSide + 40)
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
            // 枠（映像の上なので白・CLAUDE.md「写真の上は白」）
            .overlay {
                RoundedRectangle(cornerRadius: JPRadius.l)
                    .stroke(Color.white.opacity(scanner.state == .running ? 0.9 : 0.14), lineWidth: JPStroke.emphasis)
            }
            .accessibilityIdentifier("profileQR.camera")
            Text(note ?? ProfileQRText.scanHint)
                .font(JPFont.caption)
                .foregroundStyle(note == nil ? WebTheme.text2 : WebTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("profileQR.scanNote")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, JPSpace.m)
        .task { await scanner.start() }
        .onDisappear { scanner.stop() }
        .onChange(of: scanner.lastCode) { _, code in
            guard let code else { return }
            switch ProfileQRScanResult.of(code, myUserId: myUserId) {
            case .person(let userId):
                note = nil
                // 読みは空けない——人の頁から戻ったとき、まだ同じ QR が映っていてもすぐ開き直さない
                // （別の QR を読むと開く。同じ人をもう一度開くのは、いったん外して写し直す）
                onFound(userId)
            case .mine:
                note = ProfileQRText.yours
            case .other:
                note = ProfileQRText.notOurs
            case .pass(let pass):
                // 更新できる QR の合図（承認のあと）。引けたら人として扱い、引けない（古い・取り消された）なら一言
                Task { @MainActor in
                    let userId = try? await source.resolve(pass: pass)
                    // 待つ間に別の QR を読んでいたら、古い答えは使わない
                    guard scanner.lastCode == code else { return }
                    switch ProfileQRScanResult.resolved(userId, myUserId: myUserId) {
                    case .person(let id):
                        note = nil
                        onFound(id)
                    case .mine:
                        note = ProfileQRText.yours
                    case .other, .pass:
                        note = ProfileQRText.passNotValid
                    }
                }
            }
        }
    }
}

/// 読み取った文字の扱い（試験で見る）
enum ProfileQRScanResult: Equatable {
    case person(String)
    case mine
    case other
    /// 更新できる QR の合図。人に引いてから `resolved` で決める
    case pass(String)

    /// 見分けるのは `ProfileQRLink.parse`（1か所）
    static func of(_ text: String, myUserId: String?, base: URL = AppConfig.siteBaseURL) -> ProfileQRScanResult {
        switch ProfileQRLink.parse(text, base: base) {
        case .person(let userId)?: return resolved(userId, myUserId: myUserId)
        case .pass(let pass)?: return .pass(pass)
        case nil: return .other
        }
    }

    /// 人の id が決まったあと（合図を引いた結果も同じ所を通る）。引けなかった（nil）は `.other`
    static func resolved(_ userId: String?, myUserId: String?) -> ProfileQRScanResult {
        guard let userId else { return .other }
        return userId == myUserId ? .mine : .person(userId)
    }
}

/// カメラの映像（撮る画面の `CameraPreview.PreviewView` を使う）。四角い枠に**切って敷く**（`.resizeAspectFill`）——
/// 読み取りは枠いっぱいに映した方が QR を入れやすい
struct ProfileQRPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreview.PreviewView {
        let view = CameraPreview.preparedView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreview.PreviewView, context: Context) {}
}

/// アプリの中のカメラで QR を読む（`AVCaptureMetadataOutput`・後ろのカメラ）。撮る画面のカメラ（`ComposeCamera`）と同じく、
/// 組み立て・開始・停止は主スレッドの外の列で行う
@MainActor
final class ProfileQRScanner: NSObject, ObservableObject {

    enum State: Equatable { case preparing, running, denied, unavailable }

    @Published private(set) var state: State = .preparing
    /// いちばん新しく読んだ文字（同じものを読み続けている間は変わらない）
    @Published private(set) var lastCode: String?

    let session = AVCaptureSession()
    private let output = AVCaptureMetadataOutput()
    private let queue = DispatchQueue(label: "photo.journey.profile-qr")
    private var configured = false
    private var starting = false

    func start() async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
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
        // 2026-11-12 確かめ役: 許可を待つ間・カメラを組む間に画面を離れた（「自分の QR」へ切り替え・閉じる）とき、
        // `.task` は取り消され `onDisappear` の `stop()` は先に走り終わっている。そのまま点けると見えない所でカメラが動き続ける。
        // 点ける前と点けたあとに取り消しを見て、離れていたら点けない・止める
        guard !Task.isCancelled else { return }
        let ok = await run()
        if Task.isCancelled {
            stop()
            return
        }
        state = ok ? .running : .unavailable
    }

    func stop() {
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func run() async -> Bool {
        let session = session, output = output, alreadyConfigured = configured
        let ok: Bool = await withCheckedContinuation { continuation in
            queue.async {
                if !alreadyConfigured {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let input = try? AVCaptureDeviceInput(device: device) else {
                        continuation.resume(returning: false)
                        return
                    }
                    session.beginConfiguration()
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        continuation.resume(returning: false)
                        return
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    // 読める種類は出力を足したあとで決まる（本物の決まり）
                    guard output.availableMetadataObjectTypes.contains(.qr) else {
                        session.commitConfiguration()
                        continuation.resume(returning: false)
                        return
                    }
                    output.metadataObjectTypes = [.qr]
                    session.commitConfiguration()
                }
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: true)
            }
        }
        if ok, !configured {
            configured = true
            // 知らせは主スレッドで受ける（`lastCode` を画面が読む）
            output.setMetadataObjectsDelegate(self, queue: .main)
        }
        return ok
    }
}

extension ProfileQRScanner: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let text = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first
        else { return }
        // 知らせの列は主スレッド（`setMetadataObjectsDelegate(_:queue: .main)`）
        MainActor.assumeIsolated {
            if lastCode != text { lastCode = text }
        }
    }
}
