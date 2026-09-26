import SwiftUI

/// 初回に一度だけ出す同意画面（板 42「はじめる前に」）。
///
/// 上に写真を敷き、左上にロゴ、明朝の見出し、3つの約束を札のアイコンで並べ、
/// 下に固定した白いカプセルで同意する。
struct LegalGateView: View {

    @EnvironmentObject private var consent: LegalConsent
    @EnvironmentObject private var environment: AppEnvironment

    /// 上に敷く写真。**同梱しない**——公開一覧の先頭を借りる。取れなければ
    /// 黒のまま（圏外の初回起動でも同意はできる）
    @State private var heroURL: URL?

    var body: some View {
        ZStack(alignment: .top) {
            WebTheme.background.ignoresSafeArea()
            hero
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
        .task { await loadHero() }
    }

    /// 上の写真（板: 高さ250・下170 を黒へ溶かす）。写真の無いときは何も描かない
    private var hero: some View {
        Color.clear
            .frame(height: 250)
            .overlay {
                if let heroURL {
                    RemoteImage(url: heroURL)
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color.black.opacity(0), Color.black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
            }
            .ignoresSafeArea()
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

    /// 公開一覧の先頭の写真を借りる。**失敗しても黙る**（飾りなので）
    private func loadHero() async {
        guard heroURL == nil,
              let photos = try? await environment.gallery.fetchPhotos() else { return }
        heroURL = photos.lazy.compactMap(\.detailImageURL).first
    }
}
