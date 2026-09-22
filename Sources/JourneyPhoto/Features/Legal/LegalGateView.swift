import SwiftUI

/// 初回に一度だけ出す同意画面。
struct LegalGateView: View {

    @EnvironmentObject private var consent: LegalConsent

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Journey Photo")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                Label(L("旅の写真を投稿して共有できます。", "Post and share your travel photos."), systemImage: "camera")
                // **この一文が審査で効く。** 「不適切な内容を許さない」と
                // 明示し、通報とブロックの導線があることを先に伝える
                Label(L("いやがらせ・わいせつ・権利を侵す投稿は認めません。見つけたら各写真から通報でき、相手をブロックできます。", "Harassment, obscene content and rights violations are not allowed. You can report any photo and block its poster."), systemImage: "hand.raised")
                Label(L("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地は約1kmに丸めて保存します。", "Photo metadata is removed on your device; places are rounded to about 1 km."), systemImage: "location.slash")
            }
            .font(.callout)
            .padding(.horizontal, 8)

            HStack(spacing: 16) {
                Link(L("利用規約", "Terms of Use"), destination: LegalConsent.termsURL)
                Link(L("プライバシーポリシー", "Privacy Policy"), destination: LegalConsent.privacyURL)
            }
            .font(.footnote)

            Spacer()

            Button {
                consent.accept()
            } label: {
                // 🔴 **`.borderedProminent` を使わない。** `RootView` が
                // `.tint(WebTheme.foreground)`（白）を配っているので、
                // 白地に**白い字**が乗って**ただの白い帯**になる。
                // run 60 の実機の絵で、**誰もが最初に見る画面の唯一の
                // ボタンが読めなく**なっていた（Shims の模型は修飾子を
                // 素通しするので、手元では一生見えない）。
                // Web は白地に**黒い字**（`--accent-text: #07090a`）で、
                // その形は `webPrimaryButton()` に在る
                Text(L("同意してはじめる", "Agree and continue"))
                    .frame(maxWidth: .infinity)
                    .webPrimaryButton()
            }
            .buttonStyle(.plain)
            // **スモークから指すための名札。** 文字で探すと、CI の
            // シミュレータが英語なので日本語では当たらないし、
            // 上に並ぶ「利用規約」のリンクを先に掴んで Safari が開く
            .accessibilityIdentifier("legal.agree")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WebTheme.background)
    }
}
