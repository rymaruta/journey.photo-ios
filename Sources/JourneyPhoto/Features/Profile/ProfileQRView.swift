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
///   中身は `ProfileQRSource` が作る（更新できる合図・`/qr?t=<合図>`・2026-11-12 owner 承認・札 #545）。
///   QR の下に「QR コードを更新」→ 確かめ（前の QR に戻せないので聞く）→ 新しい QR と知らせ（資料 第10章・押す回数 2）
/// - 読み取る: アプリの中のカメラ。**journey-photo.com の人の URL なら、この画面の上にその人の頁を開く**
///   （`UserProfileView`）。ほかの QR は開かない（外のサイトへ連れ出さない）。自分の QR は「あなたの QR です」と言うだけ
///
/// 第2段（iPhone のカメラで読んだらアプリが開く・Associated Domains・Team ID・CloudFront）は作らない——Apple の設定が要る
struct ProfileQRView: View {

    enum Mode: Hashable { case show, scan }

    let profile: UserProfile
    /// QR の中身を作る所（無ければ `ProfileQRSources.current(api:)`・試験で替えられる）
    private let given: (any ProfileQRSource)?
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: Mode
    /// 見せる QR の中身（読み込み中・失敗・できた）
    @State private var code: CodeState = .loading
    /// 中身を作れなかった理由（読み上げの値にだけ出す。UI テストが落ちたときに事実を取るため・2026-11-12）
    @State private var failure = ""
    /// 読み取って開く人（この画面の上に積む）
    @State private var opened: OpenedPerson?
    /// 「QR コードを更新しますか？」を出している
    @State private var confirmingRenew = false
    /// 更新している（2回押しで2度替えない）
    @State private var renewing = false

    enum CodeState: Equatable { case loading, failed, ready(URL) }

    init(profile: UserProfile, source: (any ProfileQRSource)? = nil, startsWith mode: Mode = .show) {
        self.profile = profile
        self.given = source
        _mode = State(initialValue: mode)
    }

    /// 使う中身の作り手（渡されなければ更新できる合図・`ProfileQRSources.current(api:)`）
    private var source: any ProfileQRSource { given ?? ProfileQRSources.current(api: environment.api) }

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
        // シートの中なので、知らせはこの画面の上に出す（「新しい QR コードにしました」）
        .overlay(alignment: .bottom) { ToastOverlay().padding(.bottom, JPSpace.l) }
        // **前の QR に戻せない操作なので一度聞く**（資料 第10章・「直感的で簡単に」の物差しで確かめを出す所）
        .confirmationDialog(ProfileQRText.renewTitle, isPresented: $confirmingRenew, titleVisibility: .visible) {
            Button(ProfileQRText.renewConfirm) { Task { await renew() } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(ProfileQRText.renewMessage)
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
                        // 更新したら新しい QR にふわっと替える（中身の URL が替わったときだけ・`renew()` の withAnimation）
                        .id(url)
                        .transition(.opacity)
                } else {
                    failedNote(reason: "QR の絵を作れなかった: \(url.absoluteString)")
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
                failedNote(reason: failure)
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
            // QR の下に「QR コードを更新」（2026-11-12 owner 承認・札 #545）。止めたい人だけが押す1行で、
            // 主ボタンにはしない（既定は何もしなくても使える）。QR が出ているときだけ出す
            if source.canRenew, case .ready = code {
                renewButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, JPSpace.m)
        .task(id: profile.userId) { await loadCode() }
        // アプリが前に戻ったら読み直す（別の端末で更新していたら、前の QR を見せ続けない・2026-11-12 確かめ役）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshCode() } }
        }
    }

    /// 中身を作る（`ProfileQRSource`）。承認のあとはサーバーに聞くので、読み込み中と失敗を持つ
    private func loadCode() async {
        code = .loading
        do {
            code = .ready(try await source.code(for: profile.userId))
        } catch {
            failure = String(describing: error)
            code = .failed
        }
    }

    /// 今の QR を出したまま読み直す（前に戻ったとき・更新が別の画面とぶつかったとき）。
    /// 読めたら差し替え、読めなければ今の QR のまま（読み込み中の空きにしない）
    private func refreshCode() async {
        guard case .ready(let shown) = code else { return await loadCode() }
        guard let url = try? await source.code(for: profile.userId), url != shown else { return }
        withAnimation(.easeInOut(duration: 0.25)) { code = .ready(url) }
    }

    /// 「QR コードを更新」（資料 第10章の模型: 回る矢印と下線の文字・地の色は付けない・押せる高さ 44pt）
    private var renewButton: some View {
        Button { confirmingRenew = true } label: {
            HStack(spacing: JPSpace.xxs) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(JPFont.caption)
                Text(ProfileQRText.renew)
                    .font(JPFont.caption)
                    .underline(color: Color.white.opacity(0.25))
            }
            .foregroundStyle(WebTheme.text2)
            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            .padding(.horizontal, JPSpace.xs)
            .contentShape(Rectangle())
            .opacity(renewing ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(renewing)
        .accessibilityIdentifier("profileQR.renew")
    }

    /// 新しい合図にする。うまくいったら QR を差し替え（ふわっと入れ替える）、知らせを出す。
    /// 失敗したら今の QR はそのまま（前の QR はまだ使える）で、失敗の知らせだけ
    private func renew() async {
        guard !renewing else { return }
        renewing = true
        defer { renewing = false }
        do {
            let url = try await source.renew(for: profile.userId)
            withAnimation(.easeInOut(duration: 0.25)) { code = .ready(url) }
            toasts.show(ProfileQRText.renewed)
        } catch {
            toasts.show(ProfileQRText.renewFailed, kind: .failure)
            // 別の画面・端末が先に更新していた（409）。出している QR はもう使えないので、今の合図を読み直す
            if ProfileQRRenewFailure.shouldReload(error) { await refreshCode() }
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
    private func failedNote(reason: String) -> some View {
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
            // 作れなかった理由（目に見えない字・UI テストが事実を取る所。2026-11-12）。
            // **UI テストのときだけ**（見本の利用者で起動したとき）。ふだんは出さない——VoiceOver が内部の言葉と合図を読む
            if ProfileQRDiagnostics.showsFailureReason {
                Text(reason.isEmpty ? "-" : reason)
                    .font(.system(size: 1))
                    .foregroundStyle(Color.clear)
                    .frame(height: 1)
                    .accessibilityIdentifier("profileQR.failureReason")
            }
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
    /// 使えない合図を読んだとき（資料 第10章「古い QR を読んだとき」。Web の `/qr` の頁と同じ言葉）
    static var passNotValid: String {
        L("この QR コードは使えません。相手に新しい QR コードを出してもらってください",
          "This QR code can't be used. Ask them to show you a new one")
    }
    /// 合図を確かめられなかった（圏外など）。「使えません」とは言わない
    static var passCheckFailed: String {
        L("QR コードを確かめられませんでした。電波のよい所でもう一度読み取ってください",
          "Couldn't check this QR code. Try scanning again with a better connection")
    }
    static var renew: String { L("QR コードを更新", "Update QR code") }
    static var renewTitle: String { L("QR コードを更新しますか？", "Update your QR code?") }
    static var renewMessage: String {
        L("今の QR コードとリンクは使えなくなります", "Your current QR code and link will stop working")
    }
    static var renewConfirm: String { L("更新する", "Update") }
    static var renewed: String { L("新しい QR コードにしました", "Your QR code has been updated") }
    static var renewFailed: String {
        L("QR コードを更新できませんでした。もう一度お試しください", "Couldn't update your QR code. Please try again")
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
    /// 一言が失敗の知らせか（使えない合図・確かめられなかった）。失敗は起きた所（小窓）のすぐ下に danger の字で出す
    @State private var noteIsFailure = false

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
            Group {
                if noteIsFailure, let note {
                    // 板の「失敗の知らせの置き場所」: 起きた所のすぐ下に danger の字（印つき）
                    Label {
                        Text(note)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .foregroundStyle(WebTheme.danger)
                } else {
                    Text(note ?? ProfileQRText.scanHint)
                        .foregroundStyle(note == nil ? WebTheme.text2 : WebTheme.text)
                }
            }
            .font(JPFont.caption)
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
            noteIsFailure = false
            switch ProfileQRScanResult.of(code, myUserId: myUserId) {
            case .person(let userId):
                apply(.open(userId), code: code)
            case .mine:
                note = ProfileQRText.yours
            case .other:
                note = ProfileQRText.notOurs
            case .pass(let pass):
                // 更新できる QR の合図。引けたら人として扱い、引けない（古い・取り消された）なら一言
                Task { @MainActor in
                    let outcome = await ProfileQRScanFlow.resolve(pass: pass, code: code, myUserId: myUserId,
                                                                  source: source, currentCode: { scanner.lastCode })
                    apply(outcome, code: code)
                }
            }
        }
    }

    /// 読み取りの答えを画面に出す。**失敗したときと人の頁を開いたときは読みを空ける**（同じ QR をもう一度読める・
    /// 2026-11-12 確かめ役）。すぐ読み直して同じ答えを繰り返さないよう、同じ字は少しのあいだ読まない（`ProfileQRReadGate`）
    private func apply(_ outcome: ProfileQRScanFlow.Outcome, code: String) {
        switch outcome {
        case .stale:
            return
        case .open(let id):
            note = nil
            noteIsFailure = false
            scanner.release(code)
            onFound(id)
        case .mine:
            note = ProfileQRText.yours
            noteIsFailure = false
        case .unusable:
            note = ProfileQRText.passNotValid
            noteIsFailure = true
            scanner.release(code)
        case .checkFailed:
            note = ProfileQRText.passCheckFailed
            noteIsFailure = true
            scanner.release(code)
        }
    }
}

/// 合図を人に引いて、何を出すかを決める（画面から分けた・試験で見る・2026-11-12）
enum ProfileQRScanFlow {
    enum Outcome: Equatable {
        case open(String)
        case mine
        /// 使えない合図（更新された・退会した）
        case unusable
        /// 確かめられなかった（圏外・口の不調）。「使えません」とは言わない
        case checkFailed
        /// 待つ間に別の QR を読んだ。古い答えは使わない
        case stale
    }

    @MainActor
    static func resolve(pass: String, code: String, myUserId: String?, source: any ProfileQRSource,
                        currentCode: @MainActor () -> String?) async -> Outcome {
        let userId: String?
        do {
            userId = try await source.resolve(pass: pass)
        } catch {
            guard currentCode() == code else { return .stale }
            return .checkFailed
        }
        // 待つ間に別の QR を読んでいたら、古い答えは使わない
        guard currentCode() == code else { return .stale }
        switch ProfileQRScanResult.resolved(userId, myUserId: myUserId) {
        case .person(let id): return .open(id)
        case .mine: return .mine
        case .other, .pass: return .unusable
        }
    }
}

/// 同じ QR を読み直せるようにする門（2026-11-12 確かめ役）。読みを空けた字は `holdOff` 秒のあいだ読まない
/// ——カメラは映っている間ずっと同じ字を渡すので、すぐ読み直すと同じ答え（と口への問い合わせ）を繰り返す
struct ProfileQRReadGate {
    static let holdOff: TimeInterval = 2
    private var held: (text: String, until: Date)?

    /// この字を読んでよいか
    func accepts(_ text: String, now: Date = Date()) -> Bool {
        guard let held, held.text == text else { return true }
        return now >= held.until
    }

    /// この字を少しのあいだ読まない
    mutating func hold(_ text: String, now: Date = Date()) {
        held = (text, now.addingTimeInterval(Self.holdOff))
    }
}

/// 作れなかった理由を目に見えない字で出すか（UI テストのときだけ・見本の利用者で起動したとき）
enum ProfileQRDiagnostics {
    static var showsFailureReason: Bool { PreviewSession.userId != nil }
}

/// 更新が失敗したときに読み直すか（409 = 別の画面・端末が先に更新した）
enum ProfileQRRenewFailure {
    static func shouldReload(_ error: Error) -> Bool {
        if case .server(409, _)? = error as? APIError { return true }
        return false
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
    /// 読みを空けた字を少しのあいだ読まない門（`release`）
    private var gate = ProfileQRReadGate()

    /// 読みを空ける（同じ QR をもう一度読める）。すぐには読み直さない（`ProfileQRReadGate.holdOff`）
    func release(_ text: String) {
        gate.hold(text)
        if lastCode == text { lastCode = nil }
    }

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
            if lastCode != text, gate.accepts(text) { lastCode = text }
        }
    }
}
