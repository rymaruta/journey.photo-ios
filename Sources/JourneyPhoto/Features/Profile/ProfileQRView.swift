import ImageIO
import SwiftUI
import UIKit

/// プロフィールの QR（札 #545・段1・2026-11-11）。**出す・読むを1つの画面に**。
///
/// 2026-11-11 判断（owner「他のアプリは QR を読む所と出す所を分けているので『どこだっけ？』となる」）:
/// 上に自分の QR、その下に相手の QR を読むカメラの小窓。会った2人がどちらもこの画面を開けば、見せる・読むの
/// どちらでもつながる。入口は1つ（設定の「公開範囲とプライバシー」の「プロフィールの QR」）。
///
/// - QR の中身は Web の人の頁（`ProfileQR.url`）。アプリが無い人もカメラで読めば Web で開ける
/// - 開いている間は画面を明るくする（`ProfileQRBrightness`・離れる・裏に回ると戻す）。押さなくても上がる
/// - 共有（共有シートで URL）・保存（黒地に白の板の QR の1枚を写真に足す）
/// - 小窓: **開いただけでは許可を聞かない**。許可済みならそのまま読む。読めたら相手のプロフィールを開く
///
/// 色: 写真の無い画面（黒地）。QR は白の板に黒（読み取りの決まり。白黒を逆にすると読めない読み取り機がある）、
/// 板の外の角に真鍮の飾り・眉ラベルは真鍮（黒地の上だけ）。主ボタン（「カメラを使う」）は真鍮の塗りに墨
struct ProfileQRView: View {

    /// 設定が読んだ自分のプロフィール（無ければここで公開の形を読む）
    var profile: UserProfile?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var scanner = ProfileQRScanner()
    @State private var loaded: UserProfile?
    @State private var code: CGImage?
    @State private var brightness = ProfileQRBrightness()
    @State private var saveMessage: String?
    @State private var isSaving = false
    @State private var readMessage: String?
    /// 読めた相手（押し込んで相手のプロフィールを開く）
    @State private var openUserId: String?

    private var shown: UserProfile? { profile ?? loaded }

    private var link: URL? {
        auth.userId.flatMap { ProfileQR.url(userId: $0, base: AppConfig.siteBaseURL) }
    }

    var body: some View {
        SettingsPage(ProfileQRText.title) {
            mine
            reader
        }
        .navigationDestination(item: $openUserId) { id in
            UserProfileView(userId: id)
        }
        .task(id: auth.userId) { await load() }
        // 画面に出るたび（相手の頁から戻ったときも）流し直す。離れたら止める（`onDisappear`）
        .task {
            await scanner.prepare { text in read(text) }
        }
        .onAppear { raiseBrightness() }
        .onDisappear {
            restoreBrightness()
            scanner.stop()
        }
        // 裏に回ったら明るさを戻し、前に戻ったらまた上げる
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { raiseBrightness() } else { restoreBrightness() }
        }
    }

    // MARK: - 自分の QR

    private var mine: some View {
        VStack(spacing: JPSpace.m) {
            ZStack {
                QRCornerMarks()
                    .fill(WebTheme.accent)
                    .frame(width: ProfileQRText.plateSide + 28, height: ProfileQRText.plateSide + 28)
                    .accessibilityHidden(true)
                plate
            }
            .frame(maxWidth: .infinity)
            .padding(.top, JPSpace.xs)
            VStack(spacing: JPSpace.xxs) {
                if let shown {
                    Text(shown.name)
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    if let handle = ProfileLine.handleAndHome(username: shown.username, home: nil)?.handle {
                        Text(handle)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                    }
                }
                if let link {
                    Text(ProfileQR.shortLabel(link))
                        .font(JPFont.meta)
                        .foregroundStyle(WebTheme.text3)
                }
            }
            .frame(maxWidth: .infinity)
            actions
            if let saveMessage {
                Text(saveMessage)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("profileQR.saveMessage")
            }
        }
    }

    /// 白の板に黒の QR（補わずに広げて角を立てる）
    private var plate: some View {
        Group {
            if let code {
                Image(uiImage: UIImage(cgImage: code))
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            } else {
                Color.white
            }
        }
        .padding(ProfileQRText.plateInset)
        .frame(width: ProfileQRText.plateSide, height: ProfileQRText.plateSide)
        .background(Color.white, in: RoundedRectangle(cornerRadius: JPRadius.l))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProfileQRText.codeLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("profileQR.code")
    }

    /// 共有・保存（線の副ボタン 44 を2つ並べる。主ボタンは下の小窓の「カメラを使う」だけ）
    private var actions: some View {
        HStack(spacing: JPSpace.s) {
            if let link {
                ShareLink(item: link, preview: SharePreview(ProfileQRText.sharePreview(shown?.name))) {
                    Label(ProfileQRText.share, systemImage: "square.and.arrow.up")
                        .jpOutlineButton(fullWidth: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profileQR.share")
            }
            Button { Task { await save() } } label: {
                Label(isSaving ? ProfileQRText.saving : ProfileQRText.save, systemImage: "square.and.arrow.down")
                    .jpOutlineButton(fullWidth: true)
            }
            .buttonStyle(.plain)
            .disabled(code == nil || isSaving)
            .accessibilityIdentifier("profileQR.save")
        }
    }

    // MARK: - 相手の QR を読む

    private var reader: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            Text(ProfileQRText.readEyebrow)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .accessibilityAddTraits(.isHeader)
            window
            if let readMessage {
                Text(readMessage)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .accessibilityIdentifier("profileQR.readMessage")
            }
        }
    }

    /// カメラの小窓。流している間は映像に真鍮の角（映す所の合図）、それ以外は案内とボタン
    private var window: some View {
        ZStack {
            WebTheme.card
            if scanner.state == .scanning {
                QRCameraPreview(session: scanner.session)
                    .accessibilityHidden(true)
                QRCornerMarks(arm: 22, line: 3)
                    .fill(WebTheme.accent)
                    .padding(ProfileQRText.windowHeight * 0.18)
                    .accessibilityHidden(true)
            } else {
                VStack(spacing: JPSpace.s) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(WebTheme.text2)
                        .accessibilityHidden(true)
                    if let note = ProfileQR.cameraNote(scanner.state) {
                        Text(note)
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let action = ProfileQR.cameraAction(scanner.state) {
                        Button { cameraAction() } label: {
                            Text(action).jpPillButton(.accent, height: JPHeight.secondaryButton)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 220)
                        .accessibilityIdentifier("profileQR.camera")
                    }
                }
                .padding(JPSpace.m)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: ProfileQRText.windowHeight)
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .contentShape(RoundedRectangle(cornerRadius: JPRadius.l))
        // UI テストの見本（Debug だけ）: 小窓を押すと、カメラで読んだのと同じ道で渡す
        .onTapGesture {
            if let fixture = PreviewSession.qrScanFixture { scanner.deliverFixture(fixture) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ProfileQRText.windowLabel)
        .accessibilityIdentifier("profileQR.scanner")
    }

    // MARK: - 動き

    private func load() async {
        guard let userId = auth.userId else { return }
        if let link, code == nil { code = ProfileQRCode.image(for: link.absoluteString) }
        guard profile == nil, loaded == nil else { return }
        loaded = try? await environment.profiles.publicProfile(userId: userId)
    }

    private func read(_ text: String) {
        let result = ProfileQR.read(text, base: AppConfig.siteBaseURL, viewerId: auth.userId)
        readMessage = ProfileQR.message(for: result)
        switch result {
        case .profile(let id):
            openUserId = id
        case .mine, .other:
            // 一言を見せたあと、また読めるように（同じ QR を映したままでも何度も出ない間を置く）
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                scanner.resume()
            }
        }
    }

    private func cameraAction() {
        switch scanner.state {
        case .needsPermission:
            Task { @MainActor in await scanner.requestAccess() }
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        case .scanning, .unavailable:
            break
        }
    }

    private func save() async {
        guard let code, let link else { return }
        isSaving = true
        defer { isSaving = false }
        let name = shown?.name
        let handle = ProfileLine.handleAndHome(username: shown?.username, home: nil)?.handle
        let label = ProfileQR.shortLabel(link)
        let data = ProfileQRCode.card(qr: code, name: name, handle: handle, link: label)
        let outcome = await ComposeCamera.save(data)
        saveMessage = ComposeGuide.message(for: outcome)
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }

    private func raiseBrightness() {
        guard let screen, let target = brightness.raise(current: Double(screen.brightness)) else { return }
        screen.brightness = CGFloat(target)
    }

    private func restoreBrightness() {
        guard let original = brightness.restore() else { return }
        screen?.brightness = CGFloat(original)
    }
}

/// 画面の言葉と寸法（テストで見張る）
enum ProfileQRText {
    static var title: String { L("プロフィールの QR", "Profile QR code") }
    static var rowDetail: String { L("自分の QR を見せる・相手の QR を読んでつながる",
                                     "Show your QR code or scan someone else's") }
    static var readEyebrow: String { L("相手の QR を読む", "Scan a QR code") }
    static var share: String { L("共有", "Share") }
    static var save: String { L("保存", "Save") }
    static var saving: String { L("保存しています…", "Saving…") }
    static var codeLabel: String { L("あなたのプロフィールの QR コード", "Your profile QR code") }
    static var windowLabel: String { L("相手の QR を映すカメラ", "Camera for scanning a QR code") }
    static func sharePreview(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "Journey Photo" }
        return L("\(name) · Journey Photo", "\(name) · Journey Photo")
    }
    /// 白の板の一辺（読み取りやすさと、下の小窓が1画面に入る大きさの間）と内側の白い縁
    static let plateSide: CGFloat = 220
    static let plateInset: CGFloat = 12
    /// 小窓の高さ
    static let windowHeight: CGFloat = 220
}

/// 四隅の L 字（ファインダーの角）。塗りで描く（線ではなく形にする・模型と本物で同じに描ける）
struct QRCornerMarks: Shape {
    var arm: CGFloat = 28
    var line: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (rect.minX, rect.minY, 1, 1), (rect.maxX, rect.minY, -1, 1),
            (rect.minX, rect.maxY, 1, -1), (rect.maxX, rect.maxY, -1, -1),
        ]
        for (x, y, dx, dy) in corners {
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * arm, y: y))
            path.addLine(to: CGPoint(x: x + dx * arm, y: y + dy * line))
            path.addLine(to: CGPoint(x: x + dx * line, y: y + dy * line))
            path.addLine(to: CGPoint(x: x + dx * line, y: y + dy * arm))
            path.addLine(to: CGPoint(x: x, y: y + dy * arm))
            path.closeSubpath()
        }
        return path
    }
}
