import SwiftUI

/// 人の一覧の「名前で探す」の欄（板 39: 高さ 44・角 12・surface-2 の地・白 8% の縁）。
/// 表示名と @ユーザー名で絞る（`ListIdentity.filter`）。親しい友達と、メッセージの「新しいメッセージ」で使う
/// （2026-11-10 判断: 親しい友達の画面の中にあったものを部品に出した。写しを作らない）
struct PeopleSearchField: View {

    @Binding var query: String
    var placeholder: String = L("名前で探す", "Search by name")
    var identifier: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WebTheme.faint)
                .accessibilityHidden(true)
            JPTextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(WebTheme.foreground)
                .accessibilityIdentifier(identifier ?? "people.search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    // 押せる幅は 44pt（探す口の「×」と同じ・bd98adc）
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WebTheme.faint)
                        .webTappable()
                }
                .buttonStyle(.plain)
                // 見た目の位置は前のまま（右端から 14）。44 の枠で印が中央に寄ったぶん
                // （(44 − 印の幅 約18) / 2 ≈ 13）を右の余白へ張り出して戻す。押せる範囲は欄の地の中
                .padding(.trailing, -13)
                .accessibilityLabel(L("消す", "Clear"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: WebTheme.minTapTarget)
        // v2: 入力欄の地は surface-2（#161617）・縁は白 8%（板 CloseFriends・Components 02）
        .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.field).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }
}
