import SwiftUI

/// 初回に一度だけ出す同意画面（板 42「はじめる前に」）。
///
/// 上に写真を敷き、左上にロゴ、明朝の見出し、3つの約束を札のアイコンで並べ、
/// 下に固定した白いカプセルで同意する。
struct LegalGateView: View {

    @EnvironmentObject private var consent: LegalConsent
    @EnvironmentObject private var hidden: ModerationStore

    /// 上に敷く写真。**同梱しない・同意の前に通信しない**——前に取れた
    /// 公開一覧の控え（`PhotoSnapshotStore`）の先頭を借りる。控えが無ければ
    /// （初めての起動）黒のまま。
    ///
    /// 同意の前に一覧を取りにいくと、管理 API（Lambda・同時実行はアカウントで10）を
    /// インストールのたびに叩き、原寸の画像を落とし、しかも絞り込み
    /// （ブロック・通報）が入る前の一覧の先頭を出しうる（2026-09-26 のレビュー）
    @State private var hero: Photo?

    var body: some View {
        ZStack(alignment: .top) {
            WebTheme.background.ignoresSafeArea()
            // **画面の上端に貼る**（板は上端 0 から 250）。VStack で上へ寄せてから
            // 上の安全域へ伸ばす
            VStack(spacing: 0) {
                heroImage
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    AppLogo()
                        .padding(.top, 6)
                        .padding(.bottom, 58)
                    heading
                    promise(L("旅の写真を投稿して共有できます。", "Post and share your travel photos."),
                            systemImage: "camera")
                    // **この一文が審査で効く。** 「不適切な内容を許さない」と
                    // 明示し、通報とブロックの導線があることを先に伝える
                    promise(L("いやがらせ・わいせつ・権利を侵す投稿は認めません。見つけたら各写真から通報でき、相手をブロックできます。", "Harassment, obscene content and rights violations are not allowed. You can report any photo and block its poster."),
                            systemImage: "shield")
                    promise(L("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地は約1kmに丸めて保存します。", "Photo metadata is removed on your device; places are rounded to about 1 km."),
                            systemImage: "lock")
                    links
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .safeAreaInset(edge: .bottom) { agreeButton }
        .onAppear { pickHero() }
    }

    /// 上の写真（板: 高さ250・下170 を黒へ溶かす）。
    ///
    /// **読めたときだけ描く。** `RemoteImage` は読み込み中に回転、失敗で写真の
    /// 記号を灰色の地に出すので、飾りの背景には使わない（黒のままにする）
    private var heroImage: some View {
        Color.clear
            .frame(height: 250)
            .overlay {
                if let hero {
                    AsyncImage(url: hero.gridImageURL,
                               transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if case .success(let image) = phase {
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hero.gridAlignment)
                        }
                    }
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color.black.opacity(0), Color.black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
            }
            .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEFORE YOU START")
                .font(JPFont.mono(10))
                .tracking(1.6)
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
            Text(L("はじめる前に", "Before you start"))
                .font(JPFont.display(32, relativeTo: .largeTitle))
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// 約束の1行（板: 44pt・角丸14 の札に真鍮のアイコン、本文 14px・行間ゆったり）
    private func promise(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(WebTheme.accent)
                .frame(width: 44, height: 44)
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.border, lineWidth: 1))
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .lineSpacing(6)
                .foregroundStyle(WebTheme.text)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 規約とプライバシー（板: 13px・下線・白72%）
    private var links: some View {
        HStack(spacing: 20) {
            Link(destination: LegalConsent.termsURL) {
                Text(L("利用規約", "Terms of Use")).underline()
            }
            Link(destination: LegalConsent.privacyURL) {
                Text(L("プライバシーポリシー", "Privacy Policy")).underline()
            }
        }
        .font(.footnote)
        .foregroundStyle(WebTheme.muted2)
        .frame(minHeight: 32)
    }

    private var agreeButton: some View {
        Button {
            consent.accept()
        } label: {
            // 🔴 **`.borderedProminent` を使わない。** `RootView` が
            // `.tint(WebTheme.foreground)`（白）を配っているので、
            // 白地に**白い字**が乗って**ただの白い帯**になる（run 60 の実機の絵）。
            // 白地に墨の字の形は `jpPillButton()` に在る
            Text(L("同意してはじめる", "Agree and continue"))
                .jpPillButton()
        }
        .buttonStyle(.plain)
        // **スモークから指すための名札。** 文字で探すと、CI の
        // シミュレータが英語なので日本語では当たらないし、
        // 上に並ぶ「利用規約」のリンクを先に掴んで Safari が開く
        .accessibilityIdentifier("legal.agree")
        .jpBottomBar()
    }

    /// 端末の控えから1枚選ぶ。**ブロックした人・通報した写真は選ばない**
    /// （規約の版上げで、ログイン中の人にもう一度出すときがある）
    private func pickHero() {
        guard hero == nil, let photos = PhotoSnapshotStore().load() else { return }
        hero = photos.first { photo in
            photo.gridImageURL != nil
                && !hidden.reportedPhotoIds.contains(photo.id)
                && !(photo.userId.map { hidden.blockedUserIds.contains($0) } ?? false)
        }
    }
}
