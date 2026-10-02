import SwiftUI

/// 「誰に見せる？」のシート（ストーリー作成のかんたん版・owner 2026-10-02）。
///
/// 前は投稿画面の下に「フォロワーが見られます」の行と、スイッチ2つ（自分用に残す・返信を許可）が
/// 並んでいた。**それをここへ移した。** 値は投稿画面の状態そのもの（`keepInArchive`・`allowReplies`）で、
/// このシートは新しい値を持たない。
///
/// 🔴 **親しい友達には、まだ絞れない。** ストーリーはフォロワーだけが見る作りで
/// （2026-09-22・owner の判断。`api-user/src/storyVisibility.ts`）、サーバーは公開範囲を受け取らない
/// （`StoryService.createRecord`）。選べる形にすると、親しい友達だけに出したつもりのストーリーが
/// フォロワー全員に届く。だから行は見せるが押せず、そう書く。サーバーが受けるようになったら、
/// ここを選べるようにして `CloseFriendsView` へつなぐ。
///
/// 地は黒、行の面は #121212 相当（`WebTheme.surface`）。トグルのオンは暗い真鍮（#796440）。
/// 写真の無い画面なので、主ボタン「決める」は白（写真の無い画面の主ボタンは真鍮でもよいが、
/// 投稿画面の「シェアする」と同じ白に揃える）。
struct StoryAudienceSheet: View {

    @Binding var allowReplies: Bool
    @Binding var keepInArchive: Bool
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("誰に見せる？", "Who can see it?"))
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .padding(.top, 24)

            VStack(spacing: 0) {
                radioRow(title: L("フォロワー", "Followers"),
                         detail: L("あなたをフォローしている人", "People who follow you"),
                         selected: true)
                Divider().overlay(WebTheme.border)
                radioRow(title: L("親しい友達", "Close friends"),
                         detail: L("ストーリーはまだ親しい友達だけに絞れません。いまはフォロワー全員に届きます",
                                   "Stories can't be limited to close friends yet. They go to all your followers"),
                         selected: false)
                    .opacity(0.5)
            }
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))

            VStack(spacing: 0) {
                toggleRow(title: L("返信を受け取る", "Receive replies"), detail: nil, isOn: $allowReplies)
                Divider().overlay(WebTheme.border)
                // **ハイライトに入れられるのは残したものだけ**（`api-user/src/highlights.ts`）。既定は残さない
                toggleRow(title: L("24時間後も自分用に残す", "Keep for me after 24 hours"),
                          detail: L("ハイライトに入れられます", "You can add it to highlights"),
                          isOn: $keepInArchive)
            }
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))

            Spacer(minLength: 8)

            Button(action: onDone) {
                Text(L("決める", "Done"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WebTheme.accentBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WebTheme.background)
    }

    private func radioRow(title: String, detail: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(selected ? WebTheme.accent : WebTheme.faint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WebTheme.text)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.muted2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleRow(title: String, detail: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(WebTheme.text)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted2)
                }
            }
        }
        // **軌道は暗い真鍮。** 既定（白）だと白い軌道に白いつまみが乗る
        .tint(WebTheme.accentDeep)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }
}
