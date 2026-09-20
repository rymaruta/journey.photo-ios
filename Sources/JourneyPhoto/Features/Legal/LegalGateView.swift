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
                Text(L("同意してはじめる", "Agree and continue"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}
