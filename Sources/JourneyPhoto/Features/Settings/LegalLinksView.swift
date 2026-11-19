import SwiftUI

/// 利用規約とプライバシーポリシー、データの出典。設定の1行（アーティファクト 43 の
/// 「利用規約、プライバシーポリシー」）から開く。規約の**中身はサイトのページ**
/// （`LegalConsent` の URL・同意画面と同じ宛先）。
///
/// 2026-11-19: 「データの出典」の節を足した（`DataSources`・国土数値情報と総務省のコードの CC BY などの出典の表示）。
/// 形は設定の下の画面と同じ（`SettingsPage`・`SettingsGroup`。板 Settings の `.grp`: 真鍮の眉ラベル＋札の行）。
/// リンクは黒地の上の外へ出るリンクなので真鍮（同意画面 `LegalGateView.links` と同じ）、右に外へ出る矢印（板の ↗）
struct LegalLinksView: View {
    var body: some View {
        SettingsPage(L("利用規約、プライバシーポリシー", "Terms & Privacy")) {
            SettingsGroup(nil) {
                Link(destination: LegalConsent.termsURL) {
                    LegalLinkRow(title: L("利用規約", "Terms of Use"))
                }
                .buttonStyle(JPRowButtonStyle())
                .accessibilityIdentifier("legal.terms")
                JPCardDivider()
                Link(destination: LegalConsent.privacyURL) {
                    LegalLinkRow(title: L("プライバシーポリシー", "Privacy Policy"))
                }
                .buttonStyle(JPRowButtonStyle())
                .accessibilityIdentifier("legal.privacy")
            }
            SettingsGroup(L("データの出典", "Data sources")) {
                ForEach(Array(DataSources.all.enumerated()), id: \.element.id) { index, source in
                    if index > 0 { JPCardDivider() }
                    Link(destination: source.url) {
                        LegalLinkRow(title: source.title, detail: source.detail)
                    }
                    .buttonStyle(JPRowButtonStyle())
                    .accessibilityIdentifier("legal.source.\(source.id)")
                    // 決まりの本文（CC BY 4.0）。説明のすぐ下に、別に押せる行で（行の中にリンクを入れ子にしない）
                    if let license = source.license {
                        Link(destination: license.url) {
                            LegalLicenseRow(label: license.label)
                        }
                        .buttonStyle(JPRowButtonStyle())
                        .accessibilityIdentifier("legal.license.\(source.id)")
                    }
                }
            }
        }
    }
}

/// 外へ出るリンクの行（寸法は `JPRowLabel` と同じ: 最小 54・左右 14・縦 13）。名前は真鍮、説明は 12pt の薄い字
struct LegalLinkRow: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.accent)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("ブラウザで開きます", "Opens in the browser"))
    }
}

/// 出典の行の下の、決まりの本文へのリンク（真鍮の 12pt・下線・当たりは 44pt）
struct LegalLicenseRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(WebTheme.accent)
                .underline()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("ブラウザで開きます", "Opens in the browser"))
    }
}
