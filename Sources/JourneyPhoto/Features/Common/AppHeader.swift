import SwiftUI

/// タブの画面の見出し。**右は どの画面も通知 ＋ 自分のアイコン**。
///
/// 左（中央）は画面ごと（アーティファクト「journey.photo iOS」＝ iOS の正・2026-09-25）:
///
/// | 画面 | 見出し |
/// |---|---|
/// | ホーム | ロゴ（`.logo`） |
/// | 探す | 明朝の題「探す」（`.title`） |
/// | マップ | 何も置かない（`.none`）——検索窓が画面の頭になる |
///
/// 以前は、モック1・3・9・10（サイトの一次資料）に合わせて**全部ロゴ**に
/// 揃えていた（揃える前は字だけの題がばらばらで、タブを移るたびに別の
/// アプリに見えていた・run 37）。いまの題は**明朝で書体を揃える**ので、
/// その問題は書体の統一で受ける。
///
/// **ホームにあった地図のアイコンは外した。** 下のタブに「マップ」が
/// あるので、同じ場所への入口が2つあった（モックにも無い）。
// `ToolbarContent` は `View` と違って主アクタに縛られていないので、
// 中で SwiftUI の部品を組むには自分で名乗る
@MainActor
struct AppHeaderItems: ToolbarContent {

    /// 見出しの左（中央）に何を置くか
    enum Leading: Equatable {
        case logo
        case title(String)
        case none
    }

    var leading: Leading = .logo
    let unread: Int
    /// 自分のアイコン。**値で受け取る**——`ToolbarContent` は `View` では
    /// ないので、`@EnvironmentObject` が注ぎ込まれる保証が無い
    /// （注がれないと実機で「見つからない」と言って落ちる。手元の模型は
    /// 素通しするので、ここでは絶対に出ない）
    let avatarURL: URL?
    let onOpenNotifications: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        switch leading {
        case .logo:
            // ロゴ。**`navigationTitle` の文字の代わりに置く**
            ToolbarItem(placement: .principal) {
                AppLogo()
            }
        case .title(let text):
            // 画面の題（明朝）。**左寄せ**——アーティファクトの題は左上に立つ
            ToolbarItem(placement: .topBarLeading) {
                Text(text)
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            // 中央は空で埋める。埋めないと `navigationTitle` の字が
            // 中央にも出て、題が2つ並ぶ
            ToolbarItem(placement: .principal) {
                EmptyView()
            }
        case .none:
            // 置かない。空で埋めないと `navigationTitle` の字が中央に出る
            ToolbarItem(placement: .principal) {
                EmptyView()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onOpenNotifications) {
                Image(systemName: "bell")
                    .webToolbarIcon()
                    .overlay(alignment: .topTrailing) {
                        // 未読があることだけ伝える（数は開けば分かる）
                        if unread > 0 {
                            // 真鍮＝合図。黒の縁で、どの地の上でも点が割れない
                            Circle().fill(WebTheme.accent).frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(WebTheme.background, lineWidth: 2)
                                    .padding(-2))
                                .offset(x: -8, y: 10)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("お知らせ", "Activity"))
            .accessibilityIdentifier("header.notifications")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // **押すとマイページの札へ移る。** 同じ画面をこの中に
                // もう1つ積まない（戻る先が2通りになる）
                TabRouter.shared.openMyPage()
            } label: {
                avatar
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("マイページ", "My page"))
        }
    }

    /// 自分のアイコン。**未ログインなら人型**（誰かの顔を借りない）
    @ViewBuilder
    private var avatar: some View {
        if let url = avatarURL {
            RemoteImage(url: url, placeholderSymbol: "person.crop.circle.fill")
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
        } else {
            Image(systemName: "person.crop.circle")
                .webToolbarIcon()
        }
    }
}
