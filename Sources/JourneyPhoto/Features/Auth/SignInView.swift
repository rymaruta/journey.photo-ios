import SwiftUI
// 失敗の文の読み上げ（`UIAccessibility.post`）
import UIKit
// 「Apple でサインイン」のボタン（`SignInWithAppleButton`・札 #601）
import AuthenticationServices

/// Google のボタンの暗い形の色（Google のブランドの決まりの値。板の色ではないので `WebTheme` に置かない・札 #715）
enum GoogleButtonColors {
    static let fill = Color(red: 0x13 / 255, green: 0x13 / 255, blue: 0x14 / 255)
    static let stroke = Color(red: 0x8E / 255, green: 0x91 / 255, blue: 0x8F / 255)
    static let text = Color(red: 0xE3 / 255, green: 0xE3 / 255, blue: 0xE3 / 255)
}

/// ログイン・新規登録・パスワードの再設定。1画面で切り替える。
///
/// **行き止まりを作らない。** 確認コードが届かない／パスワードを忘れた、の
/// 出口が無いと、その人はアカウントを作り直すしかなくなる。
///
/// **v2（2026-10-14・板 SignIn）**: 写真のタイルを4列×3段で斜め（-4°）に敷き、上で黒へ溶かす。
/// ワードマークの下の一文は明朝 18 の text-2。主ボタンは**白**（写真のある画面・CLAUDE.md の owner の好み。
/// v2 の板は真鍮の案）、「アカウントを作る」は線のボタン
struct SignInView: View {

    var reason: String?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @State private var mode: Mode = .signIn
    @State private var email = SignInView.previewCodeScreen?.email ?? ""
    @State private var password = SignInView.previewCodeScreen?.password ?? ""
    /// 登録のときの表示名。**入れないと、しばらく ID の頭8文字で呼ばれる**
    /// ——プロフィール行は登録時に作られるが、名前は入らない
    /// （`api/src/cognitoTrigger.ts` は `userId` と `createdAt` だけ書く）
    @State private var displayName = ""
    @State private var code = ""
    /// signUp が返す UUID。確認コードの送り先を指す
    @State private var pendingUsername: String? = SignInView.previewCodeScreen?.username
    /// **端末に残る控え。** これが無いと、確認前にアプリを閉じた人が
    /// 二度と入れない（`PendingVerification` の長い注記）
    private let pending = PendingVerificationStore()
    /// 案内（送りました、など）。エラーとは別に出す
    @State private var notice: String?
    /// 「まだ確認していない」ことが分かったので、確認への入口を出す
    @State private var offerVerification = false
    /// 上に敷く写真のタイル（板 41 の 3×3）。取れなければ地の色のまま
    @State private var tiles: [Photo] = []
    /// いま打っている欄。**右下のキーで次の欄へ進め、最後の欄で送る**（2026-11-14 判断・`AuthFieldFlow`）
    @FocusState private var focusedField: AuthFieldFlow.Field?
    /// 「Apple でサインイン」をサーバーで使えるか（`GET /auth/apple/status`）。鍵の入っていない環境・口がまだ無い本番では
    /// ボタンを出さない（押しても進めないボタンを置かない）。**最初は前回の答えで描く**（`ExternalSignInMemory`・2026-11-23 判断。
    /// 答えを待ってから出すと、来たときに画面が組み変わっていた）。覚えが無ければ出さない形から
    @State private var appleAvailable = ExternalSignInMemory().initiallyShown(.apple)
    /// いま開いている Apple の頼みの nonce（Apple には SHA-256、サーバーには元の値を渡す・`SignInNonce`）。
    /// 開いている間はボタンを止め、2つ目の頼みでも同じ nonce を使う（上書きして照らせなくなるのを防ぐ・2026-11-23 確かめ役の指摘）
    @State private var appleNonce: SignInNonce?
    /// 「Google でログイン」をサーバーで使えるか（`GET /auth/google/status`・札 #715）。最初は前回の答えで描く（Apple と同じ）
    @State private var googleAvailable = ExternalSignInMemory().initiallyShown(.google)
    /// 前回の答えの置き場（ログアウト・退会で消える）
    private let externalMemory = ExternalSignInMemory()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// この画面が見せられる高さ（キーボードの出ていないとき）と、下の欄の段（Apple と Google から下の切り替えの一行まで）の高さ。
    /// **画面の下から積み、上の写真とロゴは残った高さに合わせて縮む**——送らずに全部が1画面に収まり、ボタンや失敗の文が
    /// 出ても欄は動かない（`SignInLayout`・2026-11-23 owner「新規会員登録やログイン画面でスクロールしないといけないのが嫌だ」、
    /// 模型 NL2x の案）
    @State private var viewportHeight: CGFloat = 0
    @State private var formHeight: CGFloat = 0
    /// Google の画面を開いている間（ボタンを止める。2つ目の頼みを開かない）
    @State private var googleOpen = false
    /// 電波の有無（確認コードの画面の「電波が届いていません」の帯と、戻ったら確かめ直す）
    @EnvironmentObject private var connectivity: Connectivity
    /// 確認コードの6桁の箱の状態（入力中・確かめ中・違う・期限切れ・圏外・成功・`VerificationCodeEntry`）。
    /// 欄の字そのものは `code`（数字以外や7桁目は、ここで整えて欄へ書き戻す）
    @State private var codeEntry = VerificationCodeEntry()
    /// 送り直しの待ち時間（送った直後から 60 秒）と、それを数える今の時刻
    @State private var cooldown = ResendCooldown(sentAt: SignInView.previewCodeScreen == nil ? nil : Date())
    @State private var now = Date()
    /// 違うコードのたびに1つ増える（箱を揺らす合図）
    @State private var shakeCount = 0
    /// 再設定: 6桁そろったら新しいパスワードの欄を出す（一度出したら、コードを直しても消さない）
    @State private var resetPasswordShown = false

    /// - Parameter entry: 開いたときの側。お願いの「新規登録」から来たら登録の側で開く（札 #630・2026-11-15）。
    ///   **画面の見た目と流れは変えない**——今の「アカウントを作る」を押した後と同じ状態から始めるだけ
    init(reason: String?, entry: SignInEntry = .signIn) {
        self.reason = reason
        _mode = State(initialValue: entry == .signUp ? .signUp : .signIn)
    }

    /// UI テストだけ: 登録の確認コードの画面から開く（`PreviewSession.opensVerificationCode`・見本のメールとパスワード）。
    /// Release ではどれも空（ふつうのログイン画面）
    private static var previewCodeScreen: (email: String, password: String, username: String)? {
        #if DEBUG
        guard PreviewSession.opensVerificationCode else { return nil }
        return (PreviewBackend.email, PreviewBackend.password, PreviewBackend.signUpUsername)
        #else
        return nil
        #endif
    }

    enum Mode {
        case signIn
        case signUp
        /// パスワードの再設定：コード待ち
        case resetRequested
        /// パスワードの再設定：新しいパスワードを決める
        case resetConfirm
    }

    var body: some View {
        // 入れ物は1つのまま（中身を替えても、下の写真と Apple・Google の答えを読み直さない）
        ZStack {
            if showsCodeScreen {
                codeScreen
            } else {
                formScreen
            }
        }
        // 確認コードの画面の間は上のバー（シートの「閉じる」）を隠す。戻るは左上のガラスの丸だけ（2つ並べない）
        .toolbar(showsCodeScreen ? .hidden : .automatic, for: .navigationBar)
        // **黒地にする。** 付け忘れていたので、ここだけ既定の灰色の
        // 段が並び、アプリの中で1枚だけ別のアプリに見えていた
        // （実機の絵で確認・run 38）
        .webScreen()
        .task { await loadTiles() }
        .task { await refreshExternal(.apple) }
        .task { await refreshExternal(.google) }
        // 失敗の文は出たら読み上げにも伝える（目で見ていない人にも「失敗した」が届く）
        .onChange(of: auth.errorMessage) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
        // Google の画面から戻ってきた URL（URL の型 `GoogleSignInConfig.urlScheme`）を部品に渡す
        .onOpenURL { url in _ = GoogleSignInClient.handle(url) }
        // 確認への入口は、失敗したときのメールアドレスについての案内——打ち直したら下げる
        .onChange(of: email) { _, _ in offerVerification = false }
    }

    /// 確認コードの画面か（登録の確認・パスワードの再設定のコードと新しいパスワード）
    private var showsCodeScreen: Bool {
        pendingUsername != nil || mode == .resetConfirm
    }

    /// ログイン・新規登録・再設定のメールアドレス（写真のタイルとロゴの画面）
    private var formScreen: some View {
        // 板 41 と模型 NL2x の案（2026-11-23）: 上に写真のタイルとロゴ（残った高さに合わせて縮む）、下から積んだ欄の段
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tileHeader
                        .overlay(alignment: .bottomLeading) {
                            brand
                                .padding(.horizontal, JPSpace.xl)
                                .padding(.bottom, SignInLayout.headBottom)
                        }
                    VStack(alignment: .leading, spacing: metrics.gap) {
                        if let reason {
                            Text(reason).font(.callout).foregroundStyle(WebTheme.muted2)
                                .lineLimit(density == .regular ? nil : 2)
                        }
                        switch mode {
                        case .signIn, .signUp:
                            credentialsSection
                        case .resetRequested, .resetConfirm:
                            resetSection
                        }
                        if !showsCredentials {
                            // パスワードの再設定（コードを送る前）は今までどおり節の下（主ボタンのすぐ下）
                            messages
                        }
                        if offerVerification && pendingUsername == nil && mode == .signIn {
                            verificationOffer
                        }
                    }
                    .padding(.horizontal, JPSpace.xl)
                    .padding(.bottom, SignInLayout.bottomMargin)
                    // 下の段の高さ（上の写真とロゴの高さ＝見せられる高さ − これ）
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { formHeight = $0 }
                }
            }
            // キーボードが出たら、打っている欄と主ボタンがキーボードの上に見えるよう、主ボタンを見える所の下端へ送る
            .onChange(of: focusedField) { _, field in
                guard field != nil else { return }
                withAnimation(ExternalSignInMemory.changeDuration(reduceMotion: reduceMotion).map { .easeOut(duration: $0) }) {
                    proxy.scrollTo(SignInLayout.submitAnchor, anchor: .bottom)
                }
            }
        }
        // 詰めた形では字の大きさの上限を「特大（xxxLarge）」に留める（アクセシビリティの大きい字では欄と説明が
        // 何倍にもなり、主ボタンと失敗の文が1画面の外へ出る。手本は写真の編集、パスの画面の `typeLimit`）。
        // それでも収まらないときは送れる（2026-11-23 判断: 主ボタンと失敗の文が見えるのを優先）
        .dynamicTypeSize(...(density == .regular ? .accessibility5 : SignInLayout.compactTypeLimit))
        .scrollDismissesKeyboard(.interactively)
        // 見せられる高さは、キーボードの出ていないときだけ測る（打ち始めて形が替わり、欄が跳ねないように）
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if focusedField == nil { viewportHeight = height }
        }
        // 実機の絵の道しるべ（`ScreenshotTests`）。**この画面が出ている回は、
        // 絵の名前にそう書く**——「14-マイページ」という名前で**ログイン画面**を
        // 撮っていた（run 55 まで）。名前と中身が食い違うと、見た人が
        // 「マイページはこういう画面だ」と誤読する。確認コードの画面も同じ名前（`codeScreen`）
        .accessibilityIdentifier("signin.form")
    }

    // MARK: - 上の写真とロゴ

    /// 4×3 の写真（板 v2: 1枚 120・隙間 3 を -4° 傾けて左右に 20 はみ出させ、上へ 30 ずらす。
    /// 高さ 380 の中で 上 20% → 40% で 40% → 92% で黒 と溶かす）。飾りなので読み上げない
    private var tileHeader: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: SignInLayout.tileGap),
                            count: SignInLayout.tileColumns)
        return Color.clear
            // 見せられる高さから下の段を引いた残り（ロゴが入る高さより低くはしない）
            .frame(height: SignInLayout.headHeight(viewport: viewportHeight, form: formHeight, density: density))
            .overlay(alignment: .top) {
                LazyVGrid(columns: columns, spacing: SignInLayout.tileGap) {
                    ForEach(0..<SignInLayout.tileCount, id: \.self) { index in
                        tile(index < tiles.count ? tiles[index] : nil)
                    }
                }
                .padding(.horizontal, -SignInLayout.tileBleed)
                .rotationEffect(.degrees(SignInLayout.tileTilt))
                .offset(y: SignInLayout.tileShift)
            }
            .clipped()
            .overlay {
                LinearGradient(stops: SignInLayout.fadeStops.map { .init(color: Color.black.opacity($0.opacity), location: $0.location) },
                               startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
    }

    /// 1枚。**読めたときだけ描く**（読み込み中の回転や壊れた記号を並べない）
    private func tile(_ photo: Photo?) -> some View {
        WebTheme.surface
            .frame(height: SignInLayout.tileHeight)
            .overlay {
                if let photo {
                    AsyncImage(url: StoreDemo.imageURL(photo.gridImageURL),
                               transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if case .success(let image) = phase {
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: photo.gridAlignment)
                        }
                    }
                }
            }
            .clipped()
    }

    /// 大きいロゴと一文（板: マーク＋serif。一文は 2026-10-16 にアプリの一言 `Labels.Brand.tagline` にそろえた）。
    /// 板 v2: 一文は明朝 18（段の下限）の text-2。溶けの下の方（黒 70% 以上）に乗るので灰は透過の `muted2`
    ///
    /// **どの画面の大きさでも見出しと一文を出す**（2026-11-25 owner「タイトルとかも小さいし、サブタイトルも消えるの嫌だ」）。
    /// 見出しの大きさは形で 40・32・28（`SignInLayout.Metrics.brand`）。前は小さい画面で一文を消し、見出しを 22 にしていた
    private var brand: some View {
        VStack(alignment: .leading, spacing: SignInLayout.brandGap) {
            AppLogo(size: .points(metrics.brand))
                .accessibilityAddTraits(.isHeader)
            Text(Labels.Brand.tagline)
                .font(JPFont.rowTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // 写真が下まで見えるようにしたので、一文は写真の上＝白（灰は写真の上で読めない）
                .foregroundStyle(WebTheme.foreground.opacity(0.9))
        }
        // 写真の上でも読めるよう、字の周りだけ薄く沈める
        .shadow(color: Color.black.opacity(SignInLayout.brandShadowOpacity), radius: 6, y: 1)
    }

    /// いまの形。見せられる高さと、出すもの（欄の数、Apple と Google、上の一文、字の大きさ）で決める
    private var density: SignInLayout.Density {
        SignInLayout.density(viewport: viewportHeight, signUp: mode == .signUp,
                             externalCount: (appleAvailable ? 1 : 0) + (googleAvailable ? 1 : 0),
                             hasReason: reason != nil, largeText: typeSize > .large)
    }

    private var metrics: SignInLayout.Metrics { SignInLayout.metrics(density) }

    /// 公開一覧の先頭9枚（端末で落とした人・写真は一覧の側で除かれている）。
    /// **失敗しても黙る**（飾りなので、地の色のまま）
    private func loadTiles() async {
        guard tiles.isEmpty, let photos = try? await environment.gallery.fetchPhotos() else { return }
        tiles = Self.tiles(from: photos)
    }

    /// 敷く9枚。**公開範囲を絞った写真は敷かない**——ログアウトの直後は、読み出し口の
    /// 入れ替え（`JourneyPhotoApp.applyRestrictedFeed`）より先にここが読むことがあり、
    /// 前の人あての「フォロワーのみ」「親しい友達」が混ざる
    nonisolated static func tiles(from photos: [Photo]) -> [Photo] {
        Array(photos.filter { $0.gridImageURL != nil && !RestrictedFeed.isRestricted($0) }.prefix(SignInLayout.tileCount))
    }

    private var verificationOffer: some View {
        VStack(alignment: .leading, spacing: 10) {
            // **「確認がまだ」と言い切らない。** ログインの失敗の理由（打ち間違いか未確認か）は
            // 分からない。この端末で登録して確認が済んでいなければ、ここから続けられる
            Text(L("この端末で登録して、まだメールの確認をしていない場合は、確認コードを入力できます。",
                   "If you signed up on this device and haven't verified your email yet, you can enter the code."))
                .font(.callout)
            Button {
                Task { await resumeVerification(knownUnconfirmed: false, fromOffer: true) }
            } label: {
                // 形は**中身の側**に付ける（`.plain` は外の枠を押せる範囲にしない）
                Text(L("確認コードを入力、再送する", "Enter or resend the code"))
                    .jpPillButton(.outline)
            }
            .buttonStyle(.plain)
            .disabled(auth.isWorking)
            .opacity(auth.isWorking ? 0.4 : 1)
        }
    }

    // MARK: - ログイン・新規登録

    private var canSubmit: Bool {
        !auth.isWorking && !email.isEmpty && !password.isEmpty
    }

    /// ログイン・新規登録の欄を出している（登録の確認・パスワードの再設定ではない）
    private var showsCredentials: Bool {
        pendingUsername == nil && (mode == .signIn || mode == .signUp)
    }

    /// 案内と失敗の文（板 06「失敗の知らせの置き場所」: 起きた所のすぐ上・danger・13pt・丸に！の印・トーストにしない）。
    ///
    /// 2026-11-23 判断: ログイン・新規登録では**主ボタンのすぐ上**（欄の下）に置く。前はいちばん下のボタンの下にあり、
    /// 1画面の下端より下に押し出されて見えなかった（模型 NL2x の「Apple が失敗」）。主ボタンのすぐ下に Apple・Google の
    /// 段が続くので、どのボタンで失敗しても押した所の近くに出る。失敗の文の高さは形を決める見積もりに先に入れてあるので、出ても全部が
    /// 1画面に収まる（`SignInLayout.density`）
    @ViewBuilder
    private var messages: some View {
        if let notice {
            Text(notice).font(.callout).foregroundStyle(WebTheme.muted2)
        }
        if let error = auth.errorMessage {
            errorLine(error, identifier: "signin.error")
        }
    }

    /// 失敗の文の1行（板 06: danger・13pt・丸に！の印）。確認コードの画面も同じ形を使う
    private func errorLine(_ text: String, identifier: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .font(JPFont.footnote)
        .foregroundStyle(WebTheme.danger)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    /// 欄（いちばん詰めた形では欄の名前の行を出さず、名前を欄の中の見本の字にする。読み上げの名前は同じ）
    @ViewBuilder
    private func authField<Content: View>(_ title: String, group: String? = nil,
                                          @ViewBuilder content: () -> Content) -> some View {
        Group {
            if metrics.fieldLabels {
                JPField(title, height: metrics.field, content: content)
            } else {
                content()
                    .font(.subheadline)
                    .accessibilityLabel(title)
                    .jpFieldBox(height: metrics.field)
            }
        }
        // 欄のまとまり（欄の名前の行＋箱）の枠を UI テストが測る（失敗の文から欄の上端までの間・模型 NL2x の 12）。
        // 2026-11-23 判断（Mac run 1769）: 試験は箱の内側の打つ所を測って 47.67pt と出し、間 12 の模型どおりの画面を落としていた
        .modifier(SignInFieldGroup(identifier: group))
    }

    /// 欄の中の見本の字（欄の名前の行が無いときは欄の名前）
    private func placeholder(_ title: String, regular: String) -> String {
        metrics.fieldLabels ? regular : title
    }

    /// ログイン・新規登録（模型 NL2x の案・2026-11-23）: Apple と Google（使えるときだけ）→ 失敗の文 → 欄 → 主ボタン →
    /// 切り替えの一行。**画面の下から積む**ので、上に Apple と Google や失敗の文が出ても、欄と主ボタンは動かない（上の写真とロゴが縮む）。
    /// キーボードの出ていないとき、送らずに全部が1画面に収まる（`SignInLayout.density`）。キーボードが出ている間は、
    /// 主ボタンを見える所の下端へ送り（打っている欄はそのすぐ上）、右下のキーで次の欄へ、最後の欄で送る（`AuthFieldFlow`）
    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: metrics.gap) {
            if appleAvailable || googleAvailable {
                externalSection
                    .transition(.opacity)
            }
            messages
            // **黒地では枠が要る。** 既定の入力欄は下線も背景も無く、
            // 黒の上では**どこを押すのか分からない**（実機の絵で確認）
            authField(L("メールアドレス", "Email"), group: "signin.email.field") {
                JPTextField(placeholder(L("メールアドレス", "Email"), regular: "you@example.com"), text: $email)
                    .keyboardType(.emailAddress)
                    // **`.username`（2026-11-24 判断・札 #661）。** iPhone に保存した journey-photo.com のパスワードを
                    // キーボードの上に候補として出すには、アカウントの欄を `.username` にする（Apple の Password AutoFill の決まり）。
                    // `.emailAddress` のままだと、出るのは連絡先の自分のメールだけで、保存したアカウントは出ない。
                    // 登録（`.newPassword` と組む）でも同じ欄なので、作った強いパスワードがこのメールで保存される
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    // 右下のキーで次の欄へ（2026-11-14 判断・`AuthFieldFlow`）
                    .focused($focusedField, equals: .email)
                    .submitLabel(AuthFieldFlow.key(for: .email, in: flowForm).label)
                    .onSubmit { advance(from: .email) }
                    // UI テストが名指しで打つ（`CriticalFlowTests`・2026-10-22）
                    .accessibilityIdentifier("signin.email")
            }
            authField(L("パスワード", "Password")) {
                JPSecureField(placeholder(L("パスワード", "Password"), regular: ""), text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    // ログインはここが最後の欄（右下のキーでログイン）。登録は表示名へ
                    .focused($focusedField, equals: .password)
                    .submitLabel(AuthFieldFlow.key(for: .password, in: flowForm).label)
                    .onSubmit { advance(from: .password) }
                    .accessibilityIdentifier("signin.password")
            }
            if mode == .signUp {
                authField(L("表示名（あとで変えられます）", "Display name (you can change it later)")) {
                    JPTextField(placeholder(L("表示名（あとで変えられます）", "Display name (you can change it later)"), regular: ""),
                                text: $displayName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .displayName)
                        .submitLabel(AuthFieldFlow.key(for: .displayName, in: flowForm).label)
                        .onSubmit { advance(from: .displayName) }
                        // 登録後にプロフィールへ書く名前。サーバーは 100 を超えたぶんを黙って切るので、
                        // 欄で止める（プロフィール編集と同じ `PostLimits.Profile.displayName`）
                        .onChange(of: displayName) { old, new in
                            let kept = PostLimits.limited(old: old, new: new, limit: PostLimits.Profile.displayName)
                            if kept != new { displayName = kept }
                        }
                }
                Text(AuthMessage.passwordRule)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mode == .signIn {
                // 板: 欄の下に右寄せ・13px・白72%
                Button {
                    mode = .resetRequested
                    // **ログインで打ったパスワードを持ち越さない。** 再設定の
                    // 「新しいパスワード」欄は同じ値に繋がっているので、伏せ字で
                    // 古い文字が入ったまま始まり、続けて打つと「古い＋新しい」が
                    // 新しいパスワードになっていた（本人が知らないパスワード）
                    password = ""
                    code = ""
                    clearMessages()
                } label: {
                    // 押せる範囲は文字の周りの 44pt（外に付けた枠は広げない）
                    Text(L("パスワードを忘れた", "Forgot password?"))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                        .webTappable()
                }
                .buttonStyle(.plain)
                // 送信中は押させない（あとから返った答えで画面が引き戻される）
                .disabled(auth.isWorking)
                .frame(maxWidth: .infinity, alignment: .trailing)
                // 当たりは 44pt のまま、見た目の間だけ詰める（板: 欄の下に margin-top -6）。
                // 詰めないと欄と主ボタンの間が 29pt ずつ空き、ほかの間（9〜17pt）の倍近くになって主ボタンが離れて見えた（2026-11-24 実測）
                .padding(.vertical, -SignInLayout.forgotPull)
            }

            // 主ボタン（カプセル・墨の字）。**2026-10-14 判断: 白**——CLAUDE.md の owner の好み
            // 「写真のある画面の主ボタン（ログインなど）は白」と、v2 の段の指示に合わせた。
            // ⚠️ 2026-10-02 には owner「ログインボタンもテーマカラーの真鍮の色にしたい」で真鍮にしていた
            // （v2 の板の付箋もそれを引く）。食い違いは報告済み——戻すなら `SignInLayout.primaryStyle` の1か所。
            // 同じ画面の続き（登録の完了・コードを送る・パスワードを変える）も揃える。
            // 高さは模型 NL2x の案（2026-11-23）: 小さい画面 48、ほか 52
            Button {
                // **押したらキーボードを下ろす**（右下のキーで送るとき `advance` と同じ）。2026-11-23 判断（Mac run 1771
                // `testSignInFailureIsVisibleAboveFields`「主ボタンが画面の外へ押し出された」）: ボタンで送るとキーボードが残り、
                // 違うパスワードの知らせのあと、主ボタン（y 767〜819）がキーボード（上端 約 652）の下に隠れうる
                focusedField = nil
                Task { await submitCredentials() }
            } label: {
                Text(mode == .signIn ? Labels.Navigation.login : L("登録する", "Create account"))
                    .jpPillButton(SignInLayout.primaryStyle, height: metrics.primary)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.4)
            .accessibilityIdentifier("signin.submit")
            .id(SignInLayout.submitAnchor)

            switchLine
                // 主ボタンとの間は 2（当たり 44 の中に余白がある・模型 NL2x）
                .padding(.top, -(metrics.gap - 2))
        }
    }

    /// 下の切り替えの一行（模型 NL2x の案・2026-11-23）。枠つきのボタン（高さ 44）をやめ、「はじめての方は アカウントを作る」
    /// 「アカウントをお持ちの方は ログイン」の1行（当たり 44・リンクは真鍮。黒地の上なので板の決まりどおり）
    private var switchLine: some View {
        Button {
            mode = mode == .signIn ? .signUp : .signIn
            clearMessages()
        } label: {
            HStack(spacing: 6) {
                Text(mode == .signIn ? L("はじめての方は", "New here?") : L("アカウントをお持ちの方は", "Have an account?"))
                    .foregroundStyle(WebTheme.muted2)
                Text(mode == .signIn ? L("アカウントを作る", "Create an account") : L("ログイン", "Sign in"))
                    .fontWeight(.semibold)
                    .foregroundStyle(WebTheme.accent)
            }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: SignInLayout.switchHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("signin.switch")
    }

    /// 外のアカウントの入口（「Apple でサインイン」札 #601・「Google でログイン」札 #715・2026-11-23）。
    /// 押す回数は Apple が2回（ボタン → Face ID）、Google が2〜3回（ボタン → アカウントを選ぶ（→ 続ける））。
    ///
    /// 🔴 **Apple の標準のボタン（`SignInWithAppleButton`）をそのまま使う**（審査指針 4.8・Apple の HIG。
    /// 形・字・印を作り替えない）。黒地なので白の形（HIG「暗い地には白」）。**Apple がいちばん上、Google と同じ幅と高さ**
    /// （小さい画面 46、ほか 50・模型 NL2x）、角はカプセル。登録の側では「Apple で登録」の字にする（押した後の流れは同じ）。
    ///
    /// 置き場所（2026-11-23 判断・模型 NL2x の案）: 欄の上。前は答えが来てから出るので、出たときにメールの欄が約 150pt
    /// 下へずれた。いまは画面の下から積むので、出し入れで欄は動かず、上の写真とロゴの側が縮む。さらに前回の答えで最初から
    /// 描く（`ExternalSignInMemory`）。いちばん詰めた形では「またはメールアドレスで」の線を消す
    private var externalSection: some View {
        VStack(alignment: .leading, spacing: metrics.externalGap) {
            // いちばん詰めた形（`paired`）だけ横に並べる（Apple が左・同じ幅と高さ。Apple の決まり: ほかのボタンと同じ大きさ）
            if metrics.externalSideBySide {
                HStack(spacing: metrics.externalGap) { externalButtons }
            } else {
                externalButtons
            }
            if metrics.orLine {
                // 「または」の線（区切りは字と余白で。中黒は使わない）
                HStack(spacing: JPSpace.m) {
                    Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                    Text(L("またはメールアドレスで", "or with email"))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted2)
                        .fixedSize()
                    Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Apple と Google（使えるときだけ・Apple が先）
    @ViewBuilder
    private var externalButtons: some View {
        if appleAvailable {
            appleButton
                .transition(.opacity)
        }
        if googleAvailable {
            googleButton
                .transition(.opacity)
        }
    }

    /// サーバーに使えるかを聞き、覚えて、描き方が変わるときだけ替える（動きを減らす設定ならすぐ替える）
    private func refreshExternal(_ provider: ExternalSignInProvider) async {
        let answer: Bool?
        if PreviewSession.forcesExternalSignIn {
            // UI テストの絵だけ: 通信せずに「使える」（Debug のみ・`-JPPreviewExternalSignIn YES`）
            answer = true
        } else {
            switch provider {
            case .apple: answer = await environment.appleSignIn.availability()
            case .google: answer = await environment.googleSignIn.availability()
            }
            externalMemory.remember(answer, for: provider)
        }
        let current = provider == .apple ? appleAvailable : googleAvailable
        let next = ExternalSignInMemory.shown(current: current, answer: answer)
        guard next != current else { return }
        let duration = ExternalSignInMemory.changeDuration(reduceMotion: reduceMotion)
        withAnimation(duration.map { .easeInOut(duration: $0) }) {
            switch provider {
            case .apple: appleAvailable = next
            case .google: googleAvailable = next
            }
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(mode == .signUp ? .signUp : .signIn) { request in
            request.requestedScopes = [.fullName, .email]
            // 開いている頼みがあれば同じ nonce を使う（後の頼みで上書きすると、先に戻った答えが照らせない）
            let nonce = appleNonce ?? SignInNonce.make()
            appleNonce = nonce
            request.nonce = nonce.hashed
        } onCompletion: { result in
            Task { await finishApple(result) }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.external)
        .clipShape(Capsule())
        // 🔴 シートを開いている間も止める（続けて押して頼みを2つ開かない）
        .disabled(auth.isWorking || appleNonce != nil)
        .opacity(auth.isWorking || appleNonce != nil ? 0.4 : 1)
        .accessibilityIdentifier("signin.apple")
        // 2026-11-25 判断（札 #730・Mac run 1808）: Apple のボタンの字は作ったときの値のまま残る（UIKit のボタンを包んだ部品で、
        // 字を後から替えない）。登録とログインを切り替えたら作り直して、字を「Appleで登録」⇄「Appleでサインイン」に替える
        .id(mode == .signUp)
    }

    /// 「Google でログイン」（札 #715・2026-11-23）。Apple のボタンの下（札の決まり: Apple が上）。
    ///
    /// Google のボタンの決まり（Google Identity の「Sign in with Google」のブランドの決まり）の**暗い形**:
    /// 地 #131314・縁 #8E918F・字 #E3E3E3、左に Google の正式な「G」の印（色を変えない・`GoogleG` の素材）。
    /// 形は Apple のボタンにそろえて高さ 50・カプセル（Google の決まりは角の丸い形を許す）。字はシステムの中太
    /// （2026-11-23 判断: 板の決まり「本文はシステム」。Google は Roboto を勧めるが必須ではない）。
    /// 板の黒地に置いて浮かない色で、白の Apple のボタンより一段控えめに見える
    private var googleButton: some View {
        Button {
            Task { await startGoogle() }
        } label: {
            HStack(spacing: 10) {
                Image("GoogleG")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(mode == .signUp ? L("Google で登録", "Sign up with Google") : L("Google でログイン", "Sign in with Google"))
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(GoogleButtonColors.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.external)
            .background(Capsule().fill(GoogleButtonColors.fill))
            .overlay(Capsule().stroke(GoogleButtonColors.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking || googleOpen)
        .opacity(auth.isWorking || googleOpen ? 0.4 : 1)
        .accessibilityIdentifier("signin.google")
    }

    /// Google の画面を出し、受け取った ID トークンでログインする。本人が閉じたら何も言わない
    private func startGoogle() async {
        guard !googleOpen, !auth.isWorking else { return }
        clearMessages()
        googleOpen = true
        defer { googleOpen = false }
        let nonce = SignInNonce.make()
        let got: (idToken: String?, name: String?)
        do {
            got = try await GoogleSignInClient.signIn(nonce: nonce)
        } catch is GoogleSignInClient.Canceled {
            return
        } catch {
            auth.errorMessage = AuthStore.googleSignInFailed
            return
        }
        guard let credential = GoogleSignInCredential(idToken: got.idToken, rawNonce: nonce.raw, displayName: got.name) else {
            auth.errorMessage = AuthStore.googleSignInFailed
            return
        }
        let service = environment.googleSignIn
        let started = await auth.signInWithGoogle(credential) { try await service.start($0) }
        if started?.created == true { auth.noteProfileChanged() }
    }

    /// Apple のシートが閉じた。取り消し（本人が閉じた）は何も言わない
    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        clearMessages()
        // nonce は1回きり（使い終わったら捨てる。次に押したら新しく作る）
        let rawNonce = appleNonce?.raw
        appleNonce = nil
        switch result {
        case .failure(let error):
            if let apple = error as? ASAuthorizationError, apple.code == .canceled { return }
            auth.errorMessage = AuthStore.appleSignInFailed
        case .success(let authorization):
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let credential = AppleSignInCredential(identityToken: apple.identityToken,
                                                         rawNonce: rawNonce,
                                                         authorizationCode: apple.authorizationCode,
                                                         givenName: apple.fullName?.givenName,
                                                         familyName: apple.fullName?.familyName) else {
                auth.errorMessage = AuthStore.appleSignInFailed
                return
            }
            let service = environment.appleSignIn
            let started = await auth.signInWithApple(credential) { try await service.start($0) }
            // 新しいアカウントは、サーバーが名前を入れた。マイページに読み直させる
            if started?.created == true { auth.noteProfileChanged() }
        }
    }

    private func submitCredentials() async {
        clearMessages()
        if mode == .signIn {
            await auth.signIn(email: email, password: password)
            // **未確認のまま戻ってきた人を、確認画面へ送る。**
            // 文言だけ出して入口が無いと、登録し直しても
            // 「すでに登録されています」で詰む（パスワード再設定も効かない）
            if auth.lastFailureWasUnconfirmed { await resumeVerification(knownUnconfirmed: true) }
            // 未確認の別名でのログインは「違います」「見つかりません」で答えることがある。
            // この端末に登録の控えがあれば、確認への入口を出す（`SignInRecovery`）
            offerVerification = SignInRecovery.offersVerification(
                after: auth.lastFailure, hasPendingSignUp: pending.username(for: email) != nil)
            await afterSignIn()
            return
        }

        let username = await auth.signUp(email: email, password: password)
        if let username {
            // **UUID を端末に残す。** 画面の `@State` だけだと、
            // アプリを閉じた時点で送り直す手段が消える
            pending.remember(email: email, username: username,
                             displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines))
            pendingUsername = username
            // 確認コードの画面へ（いま送ったので、送り直しの待ち時間を数える）
            startCodeScreen(sent: true)
            return
        }
        // 「すでに登録されています」＝**確認前の自分**かもしれない
        if auth.lastFailureWasExistingAccount { await resumeVerification(knownUnconfirmed: false) }
    }

    /// ログインが成立したあとの控えの後始末。**ふつうのログインでも、パスワード再設定のあとの
    /// ログインでも通す**（再設定の経路で通していなかったので、aliasExists のあと再設定して入った
    /// 人の控えの ID が重複した登録のまま残り、退会しても後始末が当たらなかった）
    private func afterSignIn() async {
        guard auth.userId != nil else { return }
        // **ログインできたら登録の ID は要らない**（確認が済んでいる）。名前だけ残し、
        // ID はいまのアカウントに書き換える（退会の後始末が ID で探す）
        pending.forgetSignUp(email: email, signedInAs: try? await AuthGateway.currentUsername())
        // **預かったままの表示名を、ふつうのログインでも入れる。**
        // 確認直後のログインが落ちた人・名前を入れ損ねた人は、ここ以外に
        // やり直す場所が無い（控えには「次のログインで試せる」と書いてある）
        // **本人があとで付けた名前は上書きしない**——既に名前があれば控えを捨てるだけ
        // 今の名前を読めなかったら何もしない（控えは次のログインまで残す）
        guard let name = pending.displayName(for: email) else { return }
        let profile = try? await environment.profiles.myProfile()
        guard let profile else { return }
        let current = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            pending.forget(email: email)
        } else if await applyDisplayName(name) {
            pending.forget(email: email)
        }
    }

    /// 預かっていた表示名をプロフィールに入れる。
    ///
    /// **登録時にプロフィール行は作られるが、名前は入らない**
    /// （`api/src/cognitoTrigger.ts` が書くのは `userId` と `createdAt` だけ）。
    /// 入れないと、その人はしばらく ID の頭8文字で呼ばれる。
    /// **失敗してもログインは成功のまま**——あとからプロフィール編集で直せる。
    /// - Returns: 控えを捨ててよいか（入れ終えた／入れるものが無い）。
    @discardableResult
    private func applyDisplayName(_ name: String?) async -> Bool {
        guard let name, !name.isEmpty, auth.userId != nil else { return true }
        do {
            var patch = ProfilePatch()
            patch.displayName = name
            try await environment.profiles.update(patch)
            auth.noteProfileChanged()
            return true
        } catch {
            // 入れられなくてもログインは成功のまま（あとから編集で直せる）。
            // 控えは残すので、次のログインでもう一度試せる
            return false
        }
    }

    /// 控えてある UUID で確認画面に戻る。コードも送り直す。
    /// - Parameter knownUnconfirmed: Cognito が「未確認」と答えた回だけ true。
    ///   「すでに登録されています」の回は**ほとんどが確認済みの人**なので、
    ///   控えが無くても「確認が済んでいません」とは言わない
    /// - Parameter fromOffer: ログインの失敗のあとの入口から押した回
    private func resumeVerification(knownUnconfirmed: Bool, fromOffer: Bool = false) async {
        // 登録で「すでに登録されています」から来た回（入口でも、ログインで未確認と答えた回でもない）
        let fromSignUp = !knownUnconfirmed && !fromOffer
        guard let saved = pending.username(for: email) else {
            // **この端末に登録の控えが無い**（Web・別の端末で登録した）。
            // 確認コードを送り直すには登録時の ID が要り、メールアドレスでは引けない
            if fromSignUp { showExistingAccount() }
            guard knownUnconfirmed else { return }
            notice = Self.unverifiedElsewhereNotice
            return
        }
        if await auth.resendSignUpCode(username: saved) {
            pendingUsername = saved
            startCodeScreen(sent: true)
            notice = L("確認コードを送り直しました。メールをご確認ください。",
                       "We sent a new code. Please check your email.")
            return
        }
        // **捨てるのは「この控えはもう使えない」ときだけ。**
        // 回数制限や圏外で捨てると、唯一の手がかりを失う
        if auth.lastFailure.isPermanent {
            // 登録の ID はもう使えない（確認済み・消えた）。名前は残す
            pending.forgetSignUp(email: email)
            offerVerification = false
            // 送り直しの答えとして意味の通らない文（「メールアドレスの形式か…」「見つかりません」
            // 「違います」）を出さない。Cognito は確認済みの利用者への送り直しを InvalidParameter で断る
            auth.errorMessage = nil
            if fromSignUp {
                showExistingAccount()
            } else if knownUnconfirmed {
                // ログインでは「未確認」と答えたのに、控えの登録には送り直せない（控えが別の登録を
                // 指している）。「確認が済んでいる」とは言わず、登録した所で確認するよう案内する
                notice = Self.unverifiedElsewhereNotice
            } else {
                notice = auth.lastFailure == .invalidParameter
                    ? SignInRecovery.alreadyConfirmedNotice
                    : SignInRecovery.unusableSignUpNotice
            }
            return
        }
        // **送り直せなくても、コードを入れる欄は出す。** 前に届いたコードは
        // まだ使えることがある。欄を出さないと、ログインを押すたびに送り直し
        // → 回数制限、を繰り返すだけで先へ進めなかった。
        // **Cognito が「未確認」と答えた回と、入口から押した回だけ。**「すでに登録されています」の
        // 回は確認済みの人がほとんどで、コードを入れても通らない画面になる。入口の文は
        // 「確認コードを入力できます」と言っているので、回数制限・圏外で送り直せなくても欄を出す。
        // **送り直しが実際に失敗した回だけ**（二度押しで走らなかった2本目は `.none` のまま——
        // 1本目の答えを待たずに欄を出さない）
        guard knownUnconfirmed || fromOffer, auth.lastFailure != .none else {
            // 登録から来て送り直せなかった（回数制限・圏外）回も、在ることを言ってログインの画面へ
            if fromSignUp && auth.lastFailure != .none { showExistingAccount() }
            return
        }
        pendingUsername = saved
        // 送り直せなかったので、待たずにすぐ送り直せる形で開く
        startCodeScreen(sent: false)
        notice = L("確認コードを送り直せませんでした。前に届いたコードがあれば、そのまま入力できます。",
                   "We couldn't send a new code. If you have an earlier code, you can enter it.")
    }

    /// 登録で「すでに登録されています」と言われた人への案内。もう一度登録しても同じ答えになるので、
    /// Web（`app/signup/page.tsx`）と同じく在ることを言い、ログインの画面へ移す（「パスワードを
    /// 忘れた」はログインの画面にしか無い）。**登録の画面にいるときだけ移す**——待つ間に再設定の
    /// 画面などへ移っていたら、引き戻さない
    private func showExistingAccount() {
        // 待つ間に「ログインに戻る」を押していた回も文は出す（黙って終わらない）。
        // 再設定の画面・確認コードの画面へ移っていたら何もしない
        guard mode == .signUp || mode == .signIn, pendingUsername == nil else { return }
        mode = .signIn
        auth.errorMessage = SignInRecovery.existingAccountMessage
    }

    private static let unverifiedElsewhereNotice = L(
        "メールアドレスの確認が済んでいません。登録したときに届いたメールの確認コードを、登録した端末（または Web）で入力してください。",
        "Your email isn't verified yet. Enter the code from the sign-up email on the device (or web) where you signed up.")

    // MARK: - 確認コードの画面（登録の確認・パスワードの再設定）

    /// 確認コードの画面（模型 NL2x「登録の確認コード」「確認コードの状態」「パスワードの再設定」・2026-11-23 owner「これでいいよ」）。
    ///
    /// - **上の写真のタイルを外す**（キーボードが下半分を占め、375×667 で箱が押し出されるため）。戻るは板の「積む画面」の
    ///   左上のガラスの丸（`ログインに戻る`）
    /// - 題（明朝 26）→ 送り先（メールアドレスは白の太字）→「メールアドレスを変える」→ 箱のすぐ上の失敗の文 → 6桁の箱 → 箱の下の1行
    /// - 登録の確認: **6桁そろったら自動で確かめる**（「登録を完了する」のボタンは置かない。押す回数 3回 → 1回）
    /// - 再設定: 6桁そろうと新しいパスワードの欄が出て、焦点が移る（押す回数 3回 → 2回）
    /// - 状態は箱のすぐ上と下の1行だけが替わる（入力中・確かめ中・違う・期限切れ・圏外・成功）。状態が替わったら読み上げる
    private var codeScreen: some View {
        VStack(spacing: 0) {
            if connectivity.isOffline {
                // 板 06 の「電波なし」: 上に帯で出す。画面は閉じない。打ったコードは残す
                JPStateBand(kind: .offline, title: JPStateBand.offlineTitle)
                    .padding(.horizontal, JPSpace.gutter)
                    .padding(.top, JPSpace.xs)
                    .accessibilityIdentifier("signin.code.offline")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    codeBackButton
                        // 丸は画面の端から 12（本文は 24）
                        .padding(.leading, JPSpace.s - JPSpace.xl)
                    Text(isResetCode ? L("パスワードを再設定", "Reset password") : L("確認コードを入力", "Enter the code"))
                        .font(JPFont.screenTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 10)
                    sentLine
                        .padding(.top, JPSpace.xs)
                    changeEmailButton
                    // コード以外の失敗（送り直しの失敗など）も箱の上。再設定でパスワードの節が出ている間は、そちらの主ボタンの上に出す
                    if let error = codeEntry.errorText ?? (resetPasswordVisible ? nil : auth.errorMessage) {
                        // 板 06: 起きた所（箱）のすぐ上。トーストにしない
                        errorLine(error, identifier: "signin.code.error")
                            .padding(.top, JPSpace.s)
                    }
                    VerificationCodeField(text: $code, entry: codeEntry, focus: $focusedField, shakeCount: shakeCount)
                        .padding(.top, JPSpace.s)
                    codeStatusLine
                        .padding(.top, 10)
                    if codeEntry.phase == .expired {
                        // 期限切れ: 新しいコードを送るのを主ボタンに（写真の無い画面なので真鍮の塗り＋墨）
                        Button {
                            Task { await sendNewCode() }
                        } label: {
                            Text(VerificationCodeEntry.newCodeText).jpPillButton(VerificationCodeLayout.primaryStyle)
                        }
                        .buttonStyle(.plain)
                        .disabled(auth.isWorking)
                        .opacity(auth.isWorking ? 0.4 : 1)
                        .accessibilityIdentifier("signin.code.newCode")
                        .padding(.top, JPSpace.xxs)
                    }
                    if resetPasswordVisible {
                        resetPasswordSection
                            .padding(.top, JPSpace.xxs)
                    }
                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(WebTheme.muted2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, JPSpace.xs)
                    }
                }
                .padding(.horizontal, JPSpace.xl)
                .padding(.top, JPSpace.xxs)
                .padding(.bottom, JPSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("signin.form")
        }
        // 開いたらすぐ打てるように（数字のキーボードの上に「メールから」の候補が出る）。画面が替わり終えてから焦点を当てる
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            // 前の画面の焦点（メールの欄など）が残っていても当て直す
            if codeEntry.phase != .verified { focusedField = .code }
        }
        // 送り直しの待ち時間を1秒ずつ数える（送ったときだけ回る）
        .task(id: cooldown) {
            now = Date()
            while !Task.isCancelled && !cooldown.canResend(now: now) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                now = Date()
            }
        }
        .onChange(of: code) { _, raw in codeTyped(raw) }
        .onChange(of: connectivity.isOffline) { _, offline in
            if !offline { reconnected() }
        }
        // 送り直しなどが終わってから6桁がそろっていた回も、自動で確かめる
        .onChange(of: auth.isWorking) { _, working in
            if !working { attemptConfirmIfReady() }
        }
        // 状態が替わったら読み上げる（違う・期限切れ・圏外・確かめ中・成功）
        .onChange(of: codeEntry.phase) { _, _ in
            if let text = codeEntry.announcement {
                UIAccessibility.post(notification: .announcement, argument: text)
            }
        }
    }

    /// パスワードの再設定のコードの画面か（でなければ登録の確認）
    private var isResetCode: Bool { pendingUsername == nil && mode == .resetConfirm }

    /// 再設定の新しいパスワードの節を出しているか
    private var resetPasswordVisible: Bool { isResetCode && (resetPasswordShown || !password.isEmpty) }

    /// 左上のガラスの丸（板「積む画面」・44pt）。今までの「ログインに戻る」と同じ戻り道
    private var codeBackButton: some View {
        Button {
            // 再設定から戻るときは打った新しいパスワードを持ち越さない（mode を変える前に見る）
            let wasReset = isResetCode
            leaveCodeScreen()
            pendingUsername = nil
            mode = .signIn
            if wasReset { password = "" }
            clearMessages()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WebTheme.foreground)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .jpGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking)
        .accessibilityLabel(L("ログインに戻る", "Back to sign in"))
        .accessibilityIdentifier("signin.code.back")
    }

    /// 送り先（「hanako@example.com に／6桁のコードを送りました」。アドレスは白の太字）
    private var sentLine: some View {
        (Text(VerificationCodeEntry.sentBefore)
            + Text(verbatim: email.trimmingCharacters(in: .whitespacesAndNewlines))
                .fontWeight(.semibold).foregroundStyle(WebTheme.foreground)
            + Text(VerificationCodeEntry.sentAfter))
            .font(.subheadline)
            .foregroundStyle(WebTheme.muted2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("signin.code.sent")
    }

    /// 「メールアドレスを変える」（真鍮・当たり 44）。打ち間違えたアドレスへ送った人の戻り道。
    /// 登録の確認は登録（またはログイン）の欄へ、再設定はメールアドレスの欄へ戻り、メールアドレスの欄を打てる状態で開く。
    /// 控え（`pending`）は捨てない——正しいアドレスだったなら、次のログインで「未確認」から同じ画面に戻れる
    private var changeEmailButton: some View {
        Button {
            let reset = isResetCode
            leaveCodeScreen()
            pendingUsername = nil
            if reset { mode = .resetRequested }
            clearMessages()
            focusedField = .email
        } label: {
            Text(VerificationCodeEntry.changeEmailText)
                .jpSystemFont(14, weight: .semibold)
                .foregroundStyle(WebTheme.accent)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking)
        .accessibilityIdentifier("signin.code.changeEmail")
    }

    /// 箱の下の1行（送り直しの待ち時間・送り直す・確かめ中・成功・圏外）
    @ViewBuilder
    private var codeStatusLine: some View {
        let line = VerificationCodeLine.line(for: codeEntry, isOffline: connectivity.isOffline,
                                             remaining: cooldown.remaining(now: now))
        switch line {
        case .resend:
            Button {
                Task { await sendNewCode() }
            } label: {
                Text(VerificationCodeEntry.resendText)
                    .jpSystemFont(14, weight: .semibold)
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(auth.isWorking)
            .accessibilityIdentifier("signin.code.resend")
        case .checking:
            HStack(spacing: JPSpace.xs) {
                ProgressView()
                    .tint(WebTheme.foreground)
                    .controlSize(.small)
                Text(VerificationCodeEntry.checkingText)
            }
            .codeLineStyle()
        case .verified:
            HStack(spacing: JPSpace.xs) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(width: 20, height: 20)
                    .background(WebTheme.accent, in: Circle())
                    .accessibilityHidden(true)
                Text(VerificationCodeEntry.verifiedText)
                    .foregroundStyle(WebTheme.foreground)
            }
            .codeLineStyle()
            .accessibilityIdentifier("signin.code.verified")
        case .wait, .offline:
            Text(line.text ?? "")
                .codeLineStyle()
        case .none:
            EmptyView()
        }
    }

    /// 再設定: 新しいパスワードの欄、短い決まり、失敗の文、「パスワードを変える」（真鍮の塗り）
    private var resetPasswordSection: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            JPField(L("新しいパスワード", "New password")) {
                JPSecureField("", text: $password)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .newPassword)
                    .submitLabel(AuthFieldFlow.key(for: .newPassword, in: flowForm).label)
                    .onSubmit { advance(from: .newPassword) }
                    .accessibilityIdentifier("signin.reset.password")
            }
            Text(AuthMessage.passwordRuleShort)
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
            if let error = auth.errorMessage, codeEntry.errorText == nil {
                // パスワードの決まりなど、コード以外の失敗は押した所のすぐ上
                errorLine(error, identifier: "signin.code.error")
                    .padding(.top, JPSpace.xxs)
            }
            Button {
                confirmReset()
            } label: {
                Text(L("パスワードを変える", "Change password")).jpPillButton(VerificationCodeLayout.primaryStyle)
            }
            .buttonStyle(.plain)
            .disabled(!canConfirmReset)
            .opacity(canConfirmReset ? 1 : 0.4)
            .accessibilityIdentifier("signin.reset.submit")
            .padding(.top, JPSpace.xxs)
        }
    }

    private var canConfirmReset: Bool {
        !auth.isWorking && codeEntry.isComplete && !password.isEmpty && codeEntry.phase != .checking
    }

    /// 確認コードの画面を開いた（コードを送った・送り直せなかったが前のコードで続ける）。空の箱から打つ
    /// - Parameter sent: いまコードを送った（送り直しの待ち時間を数え始める）
    private func startCodeScreen(sent: Bool) {
        codeEntry.restart()
        code = ""
        resetPasswordShown = false
        if sent { cooldown.start(now: Date()) } else { cooldown.clear() }
        now = Date()
        focusedField = .code
    }

    /// 確認コードの画面を離れる（打ったコード・待ち時間を持ち越さない）
    private func leaveCodeScreen() {
        codeEntry.restart()
        code = ""
        resetPasswordShown = false
        cooldown.clear()
    }

    /// 欄の字が変わった。6桁に整えて欄へ書き戻し（数字以外・7桁目は入れない）、そろったら次へ進む
    private func codeTyped(_ raw: String) {
        let wasComplete = codeEntry.isComplete
        codeEntry.input(raw)
        if raw != codeEntry.code { code = codeEntry.code }
        if isResetCode {
            // 再設定は、そろったら新しいパスワードの欄へ（確かめはパスワードと一緒に送る）
            if codeEntry.isComplete && !wasComplete {
                resetPasswordShown = true
                focusedField = .newPassword
            }
        } else {
            attemptConfirmIfReady()
        }
    }

    /// 登録の確認: 6桁そろっていれば自動で確かめる（**二重に送らない**——確かめ中・同じコード・送っている間は出さない）
    private func attemptConfirmIfReady() {
        guard let username = pendingUsername, !auth.isWorking,
              codeEntry.shouldSubmit(isOffline: connectivity.isOffline),
              let sent = codeEntry.beginCheck() else { return }
        Task { await confirmSignUp(username: username, code: sent) }
    }

    /// 電波が戻った。圏外で止めていたコードを確かめ直す（押さなくても）
    private func reconnected() {
        let wasOffline = codeEntry.phase == .offline
        codeEntry.reconnected()
        if pendingUsername != nil {
            attemptConfirmIfReady()
        } else if wasOffline && isResetCode && !password.isEmpty {
            confirmReset()
        }
    }

    /// 違う・期限切れ・圏外・そのほかの失敗を、箱の状態にする
    private func applyCodeFailure(hidesAccount: Bool = false) {
        // 再設定は、無いアカウントを「コードが違います」と同じにする（`AuthStore.confirmPasswordReset`）
        let outcome = VerificationCodeEntry.Outcome.from(auth.lastFailure, isOffline: connectivity.isOffline,
                                                         hidesAccount: hidesAccount)
        codeEntry.finish(outcome)
        switch outcome {
        case .wrong:
            // 文は箱のすぐ上に自前で出す（二重に出さない）。箱を揺らしてから空に戻し、1つ目から打ち直せるように
            auth.errorMessage = nil
            shakeCount += 1
            let delay = reduceMotion ? VerificationCodeLayout.clearDelayReduced : VerificationCodeLayout.clearDelay
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                // その間に送り直した・画面を離れた回は触らない
                guard codeEntry.phase == .wrong else { return }
                codeEntry.clearWrong()
                code = codeEntry.code
                focusedField = .code
            }
        case .expired:
            auth.errorMessage = nil
            code = codeEntry.code
            focusedField = nil
        case .offline:
            auth.errorMessage = nil
        case .failed, .verified:
            break
        }
    }

    /// 「コードを送り直す」「新しいコードを送る」。送れたら空の箱から、待ち時間を数え直す
    private func sendNewCode() async {
        guard !auth.isWorking else { return }
        clearMessages()
        let sent: Bool
        if let username = pendingUsername {
            sent = await auth.resendSignUpCode(username: username)
        } else {
            sent = await auth.startPasswordReset(email: email)
        }
        // 送れなかった（回数の上限・圏外）ときの文は `auth.errorMessage`
        guard sent else { return }
        codeEntry.restart()
        code = ""
        cooldown.start(now: Date())
        now = Date()
        focusedField = .code
        UIAccessibility.post(notification: .announcement,
                             argument: L("新しいコードを送りました。メールをご確認ください。", "We sent a new code. Please check your email."))
    }

    /// 登録の確認（6桁そろったら自動で呼ばれる）
    private func confirmSignUp(username: String, code sent: String) async {
        clearMessages()
        if await auth.confirmSignUp(username: username, code: sent) {
            codeEntry.finish(.verified)
            let verifiedAt = Date()
            let name = pending.displayName(for: email)
            // 確認が済んだので登録の ID は要らない（名前は入れ終えるまで残す）
            pending.forgetSignUp(email: email)
            offerVerification = false
            // 確認が済んだらそのままログインする。
            // **失敗しても行き止まりにしない**——「すでに登録
            // されています」から来た人は、登録欄に打った
            // パスワードが古いものと違うことがある
            await auth.signIn(email: email, password: password)
            // 「確認できました」を少し見せてから進む（模型 NL2x「成功」）
            let shown = Date().timeIntervalSince(verifiedAt)
            if shown < VerificationCodeLayout.verifiedHold {
                try? await Task.sleep(nanoseconds: UInt64((VerificationCodeLayout.verifiedHold - shown) * 1_000_000_000))
            }
            pendingUsername = nil
            // 使い終えたコードを、あとの再設定の欄に残さない
            leaveCodeScreen()
            if auth.userId == nil {
                // **ログインの欄に切り替える。** 登録から来た人は
                // 登録の欄のまま「ログインしてください」と言われ、
                // 押すと「すでに登録されています」に戻っていた
                mode = .signIn
                notice = L("確認できました。パスワードを入れてログインしてください。",
                           "Verified. Please sign in with your password.")
                return
            }
            // **控えを捨てるのは、名前を入れ終えてから。**
            // 先に捨てると、電波が悪くて1回落ちただけで
            // 入れた名前が永久に消える（次のログインでやり直せない）
            if await applyDisplayName(name) {
                pending.forget(email: email)
            }
        } else if auth.lastFailure == .aliasExists {
            // 別のアカウントがこのメールで確認済み。案内（ログインか再設定）に
            // 従えるよう、ログインの欄へ戻す。**登録の ID は捨て、名前だけ残す**——
            // ID を残すと、確認済みのアカウントでの打ち間違いのたびに、確認できない
            // 重複アカウントの確認画面へ誘っていた。名前は、そのアカウントに入った
            // とき名前が空なら入れる（ログイン成功後の処理）
            pending.forgetSignUp(email: email)
            pendingUsername = nil
            mode = .signIn
            leaveCodeScreen()
        } else {
            applyCodeFailure()
        }
    }

    // MARK: - パスワードの再設定

    /// 再設定のコードを送る前（メールアドレスの欄）。コードを送ったら確認コードの画面（`codeScreen`）へ
    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            JPField(L("メールアドレス", "Email")) {
                JPTextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    // 保存したアカウントのメールを候補から選べる（ログインの欄と同じ `.username`・札 #661）
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    // コードを送る前はここだけ。右下のキー（送信）でコードを送る（2026-11-14 判断・`AuthFieldFlow`）
                    .focused($focusedField, equals: .email)
                    .submitLabel(AuthFieldFlow.key(for: .email, in: flowForm).label)
                    .onSubmit { advance(from: .email) }
                    .accessibilityIdentifier("signin.reset.email")
            }
            Text(L("登録したメールアドレスに、確認コードを送ります。",
                   "We'll email a verification code to your address."))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)

            Button {
                requestReset()
            } label: {
                Text(L("コードを送る", "Send code")).jpPillButton(SignInLayout.primaryStyle)
            }
            .buttonStyle(.plain)
            .disabled(auth.isWorking || email.isEmpty)
            .opacity(auth.isWorking || email.isEmpty ? 0.4 : 1)

            Button {
                mode = .signIn
                code = ""
                password = ""
                clearMessages()
            } label: {
                Text(L("ログインに戻る", "Back to sign in")).jpPillButton(.outline)
            }
            .buttonStyle(.plain)
            .disabled(auth.isWorking)
        }
    }

    /// 再設定: 確認コードを送る（ボタンと、メールの欄の右下のキー）
    private func requestReset() {
        guard !auth.isWorking, !email.isEmpty else { return }
        Task {
            clearMessages()
            if await auth.startPasswordReset(email: email) {
                password = ""
                mode = .resetConfirm
                // 届いたコードをすぐ打てるように（数字のキーボードが開いたまま続く）。送り直しの待ち時間を数え始める
                startCodeScreen(sent: true)
            }
        }
    }

    /// 再設定: 新しいパスワードに変えて、そのままログイン（ボタンと、新しいパスワードの欄の右下のキー）
    private func confirmReset() {
        guard canConfirmReset, let sent = codeEntry.beginCheck() else { return }
        Task {
            clearMessages()
            let done = await auth.confirmPasswordReset(
                email: email, code: sent, newPassword: password
            )
            guard done else {
                applyCodeFailure(hidesAccount: true)
                if codeEntry.phase == .expired || codeEntry.phase == .wrong { password = "" }
                return
            }
            codeEntry.finish(.verified)
            // そのままログインまで通す（もう一度打たせない）
            await auth.signIn(email: email, password: password)
            await afterSignIn()
            if auth.userId == nil {
                leaveCodeScreen()
                mode = .signIn
                notice = L("変えました。新しいパスワードでログインしてください。",
                           "Changed. Please sign in with your new password.")
            }
        }
    }

    // MARK: - 右下のキーで進む（2026-11-14 判断・`AuthFieldFlow`）

    /// いまの画面の欄の並び
    private var flowForm: AuthFieldFlow.Form {
        switch mode {
        case .signIn: return .signIn
        case .signUp: return .signUp
        case .resetRequested: return .resetRequest
        case .resetConfirm: return .resetConfirm
        }
    }

    /// 字が入っている欄
    private var filledFields: Set<AuthFieldFlow.Field> {
        var filled: Set<AuthFieldFlow.Field> = []
        if !email.isEmpty { filled.insert(.email) }
        if !password.isEmpty { filled.insert(.password); filled.insert(.newPassword) }
        if !displayName.isEmpty { filled.insert(.displayName) }
        // 確認コードは6桁そろって「入っている」（`VerificationCodeEntry`）
        if codeEntry.isComplete { filled.insert(.code) }
        return filled
    }

    /// 右下のキーを押した。次の欄へ移るか、最後の欄ならボタンと同じことをする
    private func advance(from field: AuthFieldFlow.Field) {
        switch AuthFieldFlow.step(after: field, in: flowForm, filled: filledFields) {
        case .focus(let next):
            focusedField = next
        case .submit:
            focusedField = nil
            switch mode {
            case .signIn, .signUp:
                guard canSubmit else { return }
                Task { await submitCredentials() }
            case .resetRequested:
                requestReset()
            case .resetConfirm:
                confirmReset()
            }
        }
    }

    private func clearMessages() {
        notice = nil
        auth.errorMessage = nil
        // 確認への入口も前の失敗についての案内——画面を移ったら下げる
        offerVerification = false
    }
}

/// ログイン画面の決まり（v2 の板 SignIn・2026-10-14）。テストで見張る
enum SignInLayout {
    /// 主ボタン: 写真のある画面なので白（CLAUDE.md の owner の好み。v2 の板の真鍮の案は取らない）
    static let primaryStyle = JPPillStyle.main(onPhoto: true)
    /// 写真のタイル（板 v2: 4列×3段・1枚 120・隙間 3・-4°・左右に 20 はみ出し・上へ 30）
    static let tileColumns = 4
    static let tileRows = 3
    static var tileCount: Int { tileColumns * tileRows }
    static let tileHeight: CGFloat = 120
    static let tileGap: CGFloat = 3
    static let tileTilt: Double = -4
    static let tileBleed: CGFloat = 20
    static let tileShift: CGFloat = -30
    /// 写真の帯の高さ（板 v2: 380）と、本文がそこへ食い込む量（ワードマークは上から 250）
    static let headerHeight: CGFloat = 380
    static let contentOverlap: CGFloat = 130
    /// 写真の溶け（2026-11-24 owner「写真の下の方がフェードアウトしていて少し悲しい」）。
    /// 板 v2 は 上 20% → 40% で 40% → 92% で黒 だが、ロゴの下で写真がほぼ消えていた。
    /// 写真が下まで見えるよう、暗さを浅くし、黒になるのは帯の下端だけにする（ロゴは影で読ませる）
    static let fadeStops: [(opacity: Double, location: CGFloat)] = [(0.10, 0), (0.22, 0.5), (0.62, 0.82), (1.0, 1.0)]
    /// ロゴと一文の下に敷く影の濃さ
    static let brandShadowOpacity: Double = 0.55
    /// ロゴと一文の間（行の高さが乗るので、前の 10 は見た目で約 26pt 空いていた）
    static let brandGap: CGFloat = 4
    /// 「パスワードを忘れた」の上下を詰める量（当たりの 44pt は残す）
    static let forgotPull: CGFloat = 8
    /// 下の段の下に残す余白（1画面の下端にかからない）
    static let bottomMargin: CGFloat = JPSpace.xs
    /// ロゴの下の余白（上の段の中）、上の余白
    static let headBottom: CGFloat = JPSpace.m
    static let headTop: CGFloat = JPSpace.xs
    /// 切り替えの一行の高さ（当たり 44）
    static let switchHeight: CGFloat = 44
    /// キーボードが出たときに見える所の下端へ送る主ボタンの名前（`ScrollViewReader`）
    static let submitAnchor = "signin.submit.anchor"
    /// 詰めた形の字の大きさの上限（特大。アクセシビリティの大きい字はここで止める）
    static let compactTypeLimit: DynamicTypeSize = .xxxLarge

    /// 4つの形（2026-11-23・模型 NL2x の案と owner「スクロールしないといけないのが嫌だ」）。
    /// - `regular`: 390×844 以上の寸法（Apple と Google 50、欄 50、主ボタン 52、間 12、見出し 40）
    /// - `compact`: 375×667 の寸法（46、44、48、間 10、見出し 32）
    /// - `tight`: シートの見出しや上の一文で `compact` でも入らないとき、欄の名前の行と「またはメールアドレスで」の線を消し、間 8、見出し 28
    /// - `paired`: `tight` でも入らないとき（375×667 の新規登録に Apple と Google と上の一文が全部あるとき）、Apple と Google を横に並べる
    ///
    /// **見出しと一文は、どの形でも必ず出す**（2026-11-25 owner「タイトルとかも小さいし、サブタイトルも消えるの嫌だ」。
    /// 前は小さい画面で一文を消し、見出しを 22 にしていた）。詰めるのは上の写真のタイル（`headHeight`）と、欄の名前の行・
    /// 「または」の線・ボタンの並べ方。見出し・一文・ボタン・欄は削らない
    enum Density: Equatable, CaseIterable { case regular, compact, tight, paired }

    struct Metrics: Equatable {
        let external: CGFloat
        let externalGap: CGFloat
        let field: CGFloat
        let primary: CGFloat
        let gap: CGFloat
        /// 見出し「Journey Photo」の字の大きさ（印はその 0.94 倍の枠・`AppLogo.markRatio`）
        let brand: Double
        let fieldLabels: Bool
        let orLine: Bool
        /// Apple と Google を横に並べる（同じ幅と高さ。Apple が左）
        let externalSideBySide: Bool
    }

    static func metrics(_ density: Density) -> Metrics {
        switch density {
        case .regular:
            return Metrics(external: 50, externalGap: 10, field: 50, primary: 52, gap: 12, brand: 40,
                           fieldLabels: true, orLine: true, externalSideBySide: false)
        case .compact:
            return Metrics(external: 46, externalGap: 8, field: 44, primary: 48, gap: 10, brand: 32,
                           fieldLabels: true, orLine: true, externalSideBySide: false)
        case .tight:
            return Metrics(external: 46, externalGap: 8, field: 44, primary: 48, gap: 8, brand: 28,
                           fieldLabels: false, orLine: false, externalSideBySide: false)
        case .paired:
            return Metrics(external: 46, externalGap: 8, field: 44, primary: 48, gap: 8, brand: 28,
                           fieldLabels: false, orLine: false, externalSideBySide: true)
        }
    }

    // 形を決める見積もりの寸法（標準の字の大きさ。375 幅）
    static let estimate = (fieldLabel: CGFloat(22), rule: CGFloat(48),
                           forgot: CGFloat(44), error: CGFloat(36), orLine: CGFloat(18), reason: CGFloat(20))

    /// 見出しと一文の高さの見積もり: 見出しの行（New York Bold の行の高さ ≈ 字の 1.2 倍）＋間＋一文（明朝 18 の行 ≈ 30）。
    /// 40 なら 82（前の見積もりと同じ）、32 なら 72、28 なら 68
    static func brandHeight(_ density: Density) -> CGFloat {
        (CGFloat(metrics(density).brand) * 1.2).rounded(.up) + brandGap + 30
    }

    /// 上の段（写真とロゴ）の最低の高さ（見出しと一文が入る高さ）
    static func headMin(_ density: Density) -> CGFloat {
        headTop + brandHeight(density) + headBottom
    }

    /// 下の段の高さの見積もり（**失敗の文の分も先に数える**——出たときに形が替わらず、主ボタンと失敗の文が1画面に残る）
    static func formNeed(_ density: Density, signUp: Bool, externalCount: Int, hasReason: Bool) -> CGFloat {
        let m = metrics(density), e = estimate
        let field = m.field + (m.fieldLabels ? e.fieldLabel : 0)
        var items: [CGFloat] = []
        if hasReason { items.append(e.reason) }
        if externalCount > 0 {
            let buttons = m.externalSideBySide
                ? m.external
                : CGFloat(externalCount) * m.external + CGFloat(externalCount - 1) * m.externalGap
            items.append(buttons + (m.orLine ? m.externalGap + e.orLine : 0))
        }
        items += [e.error, field, field]
        items += signUp ? [field, e.rule] : [e.forgot]
        items.append(m.primary)
        let stacked = items.reduce(0, +) + m.gap * CGFloat(items.count - 1)
        return stacked + 2 + switchHeight + bottomMargin
    }

    /// 1画面に要る高さ（上の段の最低＋下の段）
    static func need(_ density: Density, signUp: Bool, externalCount: Int, hasReason: Bool) -> CGFloat {
        headMin(density) + formNeed(density, signUp: signUp, externalCount: externalCount, hasReason: hasReason)
    }

    /// どの形で描くか。大きい順に、1画面に収まる最初の形。大きい字はいつも `tight`（字の上限も掛ける。
    /// 横に並べると字が切れるので `paired` にはしない。入らなければ送れる）。まだ測れていない（0）ときは `regular`
    static func density(viewport: CGFloat, signUp: Bool, externalCount: Int, hasReason: Bool, largeText: Bool) -> Density {
        guard viewport > 0 else { return .regular }
        if largeText { return .tight }
        return Density.allCases.first {
            need($0, signUp: signUp, externalCount: externalCount, hasReason: hasReason) <= viewport
        } ?? .paired
    }

    /// 上の段（写真とロゴ）の高さ: 見せられる高さから下の段を引いた残り。ロゴが入る高さより低くはしない（そのときは送れる）。
    /// まだ測れていない（0）ときは板の 380
    static func headHeight(viewport: CGFloat, form: CGFloat, density: Density) -> CGFloat {
        guard viewport > 0, form > 0 else { return headerHeight }
        return max(headMin(density), viewport - form)
    }
}

/// 欄のまとまりに識別子を付ける（中の欄の読み上げはそのまま・`authField`）
private struct SignInFieldGroup: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
