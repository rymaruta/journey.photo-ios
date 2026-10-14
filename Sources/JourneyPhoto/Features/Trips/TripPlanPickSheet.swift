import SwiftUI

/// 行きたい場所から選ぶ（キャンバス「17c 行きたい場所から選ぶ」・v2 の板 TripPlanPick）。
///
/// **自由入力の欄は置かない。** 綴りの違う地名が増えて `/location/*` と
/// 噛み合わなくなる（Web がタグで同じことを踏んで、固定の選択肢に直した経緯）。
///
/// **v2（2026-10-14）: いくつでも選んでから、下の「N か所を追加」でまとめて足す**（板 TripPlanPick の
/// 「複数選びは真鍮の丸にチェック」）。以前は1つ押すたびに足して閉じていて、3か所入れるのに
/// シートを3回開いていた。選べるのは**その日の残りの数まで**（1日に置ける数はサーバーと対・
/// `TripPlanService.itemsPerDayMax`）——超えて選ばせて、足すときに黙って落とさない。
/// 足す順は選んだ順
struct TripPlanPickSheet: View {

    let dayIndex: Int
    /// 見出しの眉に添える日付（「12月24日」）。日付の無いプランは nil
    var dayDate: String?
    /// この日にあと置ける数
    var capacity: Int = TripPlanService.itemsPerDayMax
    /// 候補の材料を取れなかった（圏外など）。**「まだ保存していない」と混ぜない**
    var sourcesFailed = false
    let choices: [TripPlanText.Choice]
    let onPick: (TripPlanText.Choice) -> Void

    @Environment(\.dismiss) private var dismiss
    /// 選んだ候補（選んだ順）
    @State private var selected: [String] = []

    private var spots: [TripPlanText.Choice] { choices.filter(\.isOfficial) }
    private var locations: [TripPlanText.Choice] { choices.filter { !$0.isOfficial } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    // 眉（板: 「1日目 · 12月24日」の真鍮）→ 明朝の題
                    Text(Self.eyebrow(dayIndex: dayIndex, date: dayDate))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(L("行きたい場所から追加", "Add a saved place"))
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .accessibilityAddTraits(.isHeader)
                    // **どこから来た候補かを書く。** 「行きたい」はログイン中は
                    // サーバーの一覧（`WishlistStore`・`/user/spots`）なので、Web で
                    // 押したものも並ぶ。「この端末で」とは書かない
                    Text(L("「行きたい」に入れた場所から選べます",
                           "Places you marked “Want to go”"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }

                if choices.isEmpty && sourcesFailed {
                    ErrorBanner(message: L("行きたい場所を読み込めませんでした。通信を確かめて、開き直してください",
                                           "Couldn't load your saved places. Check your connection and try again."))
                } else if choices.isEmpty {
                    EmptyState(title: L("行きたい場所はまだありません", "No saved places yet"),
                               message: L("先に「行きたい場所」に保存してください", "Save places first"))
                } else {
                    Text(Self.hint(capacity: capacity))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                    group(L("撮影スポット", "Photo spots"), spots)
                    group(L("撮影地", "Places"), locations)
                }
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xl)
        }
        .webScreen()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
        }
        // 下に固定した主ボタン（写真の無い画面＝真鍮の塗り＋墨・板「3か所を追加」）
        .safeAreaInset(edge: .bottom) {
            if !choices.isEmpty {
                Button(action: addSelected) {
                    Text(Self.addTitle(count: selected.count))
                        .jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? TripStyle.disabledOpacity : 1)
                .accessibilityIdentifier("trips.pick.add")
                .jpBottomBar()
            }
        }
    }

    /// 選んだ順に足して閉じる
    private func addSelected() {
        let picked = selected.compactMap { id in choices.first { $0.id == id } }
        guard !picked.isEmpty else { return }
        picked.forEach(onPick)
        dismiss()
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [TripPlanText.Choice]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                JPEyebrowLine(title)
                    .padding(.bottom, JPSpace.xxs)
                ForEach(rows) { choice in
                    row(choice)
                }
            }
        }
    }

    private func row(_ choice: TripPlanText.Choice) -> some View {
        let isOn = selected.contains(choice.id)
        // 残りがいっぱいなら、選んでいない行は押せない（選んだ行は外せる）
        let locked = !isOn && selected.count >= capacity
        return Button {
            selected = Self.toggled(selected, id: choice.id, capacity: capacity)
        } label: {
            HStack(spacing: JPSpace.s) {
                Image(systemName: choice.isOfficial ? "mappin.and.ellipse" : "map")
                    .font(.system(size: 17))
                    .foregroundStyle(WebTheme.text2)
                    .frame(width: TripStyle.pickThumb, height: TripStyle.pickThumb)
                    .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.s))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: JPSpace.xs) {
                        // 撮影スポットは明朝（台帳の場所）、撮影地は SF の太字（板 TripPlanPick）
                        Text(choice.name)
                            .font(choice.isOfficial ? JPFont.rowTitle : JPFont.bodyEmphasis)
                            .foregroundStyle(WebTheme.foreground)
                            .lineLimit(1)
                        // 🔴 **「公式」と書かない**（`OfficialSpot` の注記）。台帳は運営の下書きを
                        // 含み、人が確かめたものではない。地図のスポット一覧・マイページの行と
                        // 同じく、**下書きのときだけ**「下書き」の札を付ける
                        if choice.isDraft {
                            Text(L("下書き", "Draft"))
                                .font(JPFont.caption.weight(.semibold))
                                .foregroundStyle(WebTheme.text2)
                                .padding(.horizontal, 6)
                                .overlay(RoundedRectangle(cornerRadius: JPRadius.xs + 2)
                                    .strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                        }
                    }
                    if let region = choice.regionLabel {
                        Text(region)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: JPSpace.xs)
                PickMark(isOn: isOn)
            }
            .padding(.vertical, JPSpace.xs)
            .frame(minHeight: TripStyle.pickRowMinHeight)
            .overlay(alignment: .bottom) {
                Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.5 : 1)
        // 名前だけにしない（札の語と県・市も読む）。選んだかは「選択中」で言う
        .accessibilityLabel(L("\(choice.name)\(choice.isDraft ? "・下書き" : "")\(choice.regionLabel.map { "・" + $0 } ?? "")",
                              "\(choice.name)\(choice.isDraft ? ", draft" : "")\(choice.regionLabel.map { ", " + $0 } ?? "")"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isOn ? L("押すと外します", "Tap to deselect") : L("押すと選びます", "Tap to select"))
    }

    // MARK: - 計算（Linux で試す）

    /// 選ぶ・外す。**残りの数を超えては選ばない**（外すのはいつでも）
    nonisolated static func toggled(_ selected: [String], id: String, capacity: Int) -> [String] {
        if let at = selected.firstIndex(of: id) {
            var next = selected
            next.remove(at: at)
            return next
        }
        guard selected.count < max(capacity, 0) else { return selected }
        return selected + [id]
    }

    /// 眉「1日目 · 12月24日」
    nonisolated static func eyebrow(dayIndex: Int, date: String?) -> String {
        let day = L("\(dayIndex + 1)日目", "Day \(dayIndex + 1)")
        guard let date, !date.isEmpty else { return day }
        return "\(day) · \(date)"
    }

    /// 主ボタンの字（「3か所を追加」・0 のときは「追加」）
    nonisolated static func addTitle(count: Int) -> String {
        guard count > 0 else { return L("追加", "Add") }
        return L("\(count)か所を追加", count == 1 ? "Add 1 place" : "Add \(count) places")
    }

    /// 選び方の一言（板「いくつでも選べます。押し直すと外れます」）。残りが少ない日は数を言う
    nonisolated static func hint(capacity: Int) -> String {
        if capacity <= 0 {
            return L("この日はいっぱいです", "This day is full")
        }
        if capacity < TripPlanService.itemsPerDayMax {
            return L("この日はあと \(capacity) か所まで選べます。押し直すと外れます",
                     "You can pick up to \(capacity) more for this day. Tap again to deselect.")
        }
        return L("いくつでも選べます。押し直すと外れます", "Pick as many as you like. Tap again to deselect.")
    }
}

/// 選んだ印（板 TripPlanPick: 26 の丸。選ぶと真鍮の塗りに墨のチェック、選ばないと白 30% の線）
private struct PickMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(WebTheme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WebTheme.accentText)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
            }
        }
        .frame(width: TripStyle.pickMark, height: TripStyle.pickMark)
        .accessibilityHidden(true)
    }
}
