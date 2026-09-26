import SwiftUI

/// 利用規約とプライバシーポリシー。設定の1行（アーティファクト 43 の
/// 「利用規約・プライバシーポリシー」）から開く。**中身はサイトのページ**
/// （`LegalConsent` の URL・同意画面と同じ宛先）。
struct LegalLinksView: View {
    var body: some View {
        List {
            Link(L("利用規約", "Terms of Use"), destination: LegalConsent.termsURL)
            Link(L("プライバシーポリシー", "Privacy Policy"), destination: LegalConsent.privacyURL)
        }
        .webScreen()
        .navigationTitle(L("利用規約・プライバシーポリシー", "Terms & Privacy"))
    }
}
