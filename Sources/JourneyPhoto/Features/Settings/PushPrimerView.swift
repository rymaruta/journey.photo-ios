import SwiftUI

/// 通知を受け取るかの、アプリの中の短い説明（2026-10-11）。**初めての投稿が上がったとき**に1回だけ
/// （決まりは `PushPrimer`・出す頃合いは `PushPrimerStore`・出すのは `RootView`）。
///
/// 先に「なぜ通知か」を言ってから、「通知を受け取る」でシステムのダイアログへ進む。
/// 「あとで」は閉じるだけ（二度と出さない・設定の「プッシュ通知を受け取る」からいつでも）。
///
/// 写真の無い画面なので、板（DesignSystem「黒塗りの真鍮」）どおり: 黒地・眉ラベルは真鍮・
/// 見出しは明朝・主ボタンは真鍮の塗り（`accentFill`）に墨・印は白（`LibraryTripIntroView` と同じ形）
struct PushPrimerView: View {

    @EnvironmentObject private var push: PushCenter
    @EnvironmentObject private var environment: AppEnvironment
    /// Pro か（サーバーのプロフィールで決める。読めない間・読めなければ Pro の項目は出さない）
    @State private var isPro = false
    @Environment(\.dismiss) private var dismiss
    /// 許可を尋ねている最中（二度押しで重ねて尋ねない）
    @State private var isAsking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTIFICATIONS")
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(L("写真への反応を、すぐに知らせます", "Know when people respond to your photos"))
                        .font(JPFont.screenTitle)
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(PushPrimerPoint.shown(isPro: isPro)) { item in
                        point(item.systemImage, item.text)
                    }
                }
                Text(L("あとから設定の「プッシュ通知を受け取る」でいつでも変えられます。",
                       "You can change this anytime in Settings → Push notifications."))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button {
                    guard !isAsking else { return }
                    isAsking = true
                    Task {
                        // システムのダイアログへ。答え（許可・拒否）はどちらでも閉じる
                        // ——断られたら設定の行が「許可されていません」を出す（`SettingsView`）
                        await push.enable()
                        isAsking = false
                        dismiss()
                    }
                } label: {
                    Text(L("通知を受け取る", "Turn on notifications"))
                        .jpPillButton(.accent)
                }
                .buttonStyle(.plain)
                .disabled(isAsking)
                .accessibilityIdentifier("push.primer.allow")
                Button { dismiss() } label: {
                    Text(L("あとで", "Not now"))
                        .font(.callout)
                        .foregroundStyle(WebTheme.muted2)
                        // 48: 半分の高さのシートは iOS 26 で約 96% に縮めて描かれ、44 だと
                        // 当たりが 42.4pt になっていた（run 407・408 の画面で主ボタンの幅も 0.962 倍）
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("push.primer.later")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background(WebTheme.background)
        }
        .webScreen()
        .task { isPro = (try? await environment.profiles.myProfile())?.isPro ?? false }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func point(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                // 真鍮は眉ラベルと主ボタンだけ。印は白（`LibraryTripIntroView` と同じ）
                .foregroundStyle(WebTheme.foreground)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 説明に並べる項目（2026-10-11）。
///
/// 2026-10-11 判断: **「Pro: 行きたい場所が晴れそうなとき」は Pro の人にだけ出す。**
/// 初めての投稿をした人の多くは Pro でなく、その人には届かない通知を約束することになる
/// （Pro の案内はここでしない——通知の許可を尋ねる画面で売り込まない）
struct PushPrimerPoint: Identifiable, Equatable {
    let systemImage: String
    let text: String
    var id: String { systemImage }

    static func shown(isPro: Bool) -> [PushPrimerPoint] {
        var points = [
            PushPrimerPoint(systemImage: "heart",
                            text: L("いいね・コメント・フォローが届いたとき", "When you get likes, comments and follows")),
            PushPrimerPoint(systemImage: "bubble.left",
                            text: L("ストーリーに返信が来たとき", "When someone replies to your story")),
        ]
        if isPro {
            points.append(PushPrimerPoint(systemImage: "sunrise",
                                          text: L("Pro: 行きたい場所が明日の朝に晴れそうなとき（前の晩に）",
                                                  "Pro: when a wishlist place looks clear tomorrow morning (the evening before)")))
        }
        return points
    }
}
