import SwiftUI

/// 行きたい場所から選ぶ（キャンバス「17c 行きたい場所から選ぶ」）。
///
/// **自由入力の欄は置かない。** 綴りの違う地名が増えて `/location/*` と
/// 噛み合わなくなる（Web がタグで同じことを踏んで、固定の選択肢に直した経緯）。
/// 1つ押すと、その日に足して閉じる（Web の `<select>` と同じく1回で1か所）。
struct TripPlanPickSheet: View {

    let dayIndex: Int
    /// 候補の材料を取れなかった（圏外など）。**「まだ保存していない」と混ぜない**
    var sourcesFailed = false
    let choices: [TripPlanText.Choice]
    let onPick: (TripPlanText.Choice) -> Void

    @Environment(\.dismiss) private var dismiss

    private var spots: [TripPlanText.Choice] { choices.filter(\.isOfficial) }
    private var locations: [TripPlanText.Choice] { choices.filter { !$0.isOfficial } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("行きたい場所から追加", "Add a saved place"))
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                    Text(L("\(dayIndex + 1) 日目", "Day \(dayIndex + 1)"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                    // **どこから来た候補かを書く。** 「行きたい」はこの端末にだけ
                    // 覚えている（`WishlistStore`）ので、Web で押したものは出ない
                    Text(L("この端末で「行きたい」に入れた場所から選べます",
                           "Places you marked “Want to go” on this device"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
                .padding(.horizontal, 4)

                if choices.isEmpty && sourcesFailed {
                    Text(L("行きたい場所を読み込めませんでした。通信を確かめて、開き直してください",
                           "Couldn't load your saved places. Check your connection and try again."))
                        .font(.callout)
                        .foregroundStyle(WebTheme.muted2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if choices.isEmpty {
                    Text(L("先に「行きたい場所」に保存してください", "Save places first"))
                        .font(.callout)
                        .foregroundStyle(WebTheme.muted2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    group(L("撮影スポット", "Photo spots"), spots)
                    group(L("撮影地", "Places"), locations)
                }
            }
            .padding(16)
        }
        .webScreen()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [TripPlanText.Choice]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .padding(.horizontal, 4)
                ForEach(rows) { choice in
                    row(choice)
                }
            }
        }
    }

    private func row(_ choice: TripPlanText.Choice) -> some View {
        Button {
            onPick(choice)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: choice.isOfficial ? "mappin.and.ellipse" : "map")
                    .foregroundStyle(WebTheme.muted2)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(choice.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WebTheme.foreground)
                            .lineLimit(1)
                        if choice.isOfficial {
                            Text(L("公式", "Official"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WebTheme.muted)
                                .webChip()
                        }
                    }
                    if let region = choice.regionLabel {
                        Text(region)
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .foregroundStyle(WebTheme.muted2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 名前だけにしない（「公式」と県・市も読む）
        .accessibilityLabel(L("\(choice.name)\(choice.isOfficial ? "・公式" : "")\(choice.regionLabel.map { "・" + $0 } ?? "") を追加",
                              "Add \(choice.name)\(choice.regionLabel.map { ", " + $0 } ?? "")"))
    }
}
