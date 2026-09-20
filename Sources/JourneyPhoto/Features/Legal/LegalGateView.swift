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
                Label("旅の写真を投稿して共有できます。", systemImage: "camera")
                // **この一文が審査で効く。** 「不適切な内容を許さない」と
                // 明示し、通報とブロックの導線があることを先に伝える
                Label("いやがらせ・わいせつ・権利を侵す投稿は認めません。見つけたら各写真から通報でき、相手をブロックできます。", systemImage: "hand.raised")
                Label("撮影情報（EXIF）は端末で取り除いてから送ります。撮影地は約1kmに丸めて保存します。", systemImage: "location.slash")
            }
            .font(.callout)
            .padding(.horizontal, 8)

            HStack(spacing: 16) {
                Link("利用規約", destination: LegalConsent.termsURL)
                Link("プライバシーポリシー", destination: LegalConsent.privacyURL)
            }
            .font(.footnote)

            Spacer()

            Button {
                consent.accept()
            } label: {
                Text("同意してはじめる")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}
