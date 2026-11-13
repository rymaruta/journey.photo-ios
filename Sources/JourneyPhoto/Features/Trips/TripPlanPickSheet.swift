import SwiftUI
import UIKit

/// 場所を足すシートの日の見出し
struct TripPlanSheetDay: Equatable {
    /// 「1日目」
    let label: String
    /// 眉に添える日付（「12月24日」）。日付の無いプランは nil
    let date: String?
}

/// 場所を足す（キャンバス「17c 行きたい場所から選ぶ」・v2 の板 TripPlanPick・資料「みんなで埋める旅行プラン」の場面5）。
///
/// **2026-11-12 判断（1.1.85・札 #570・owner「場所を検索して追加できたり…簡単に操作できるように」）:**
/// - シートの上端に**探す欄を1つ**。空のときは今までどおり行きたい場所が並び、打つと「行きたい場所」と
///   「観光スポット」（台帳。ひらがな・別名でも当たる）の2つの組が出る（`TripPlanSearch`）
/// - **押せばすぐ入る。** 行は「入れました」に変わり、シートは開いたままで続けて足せる。もう一度押すと取り消す。
///   以前は選んでから下の「N か所を追加」をもう1回押していた（押す回数 3 → 2）。確かめは出さない（取り消せるので）
/// - 入れる日はシートの上の「1日目 | 2日目」で替えられる。開いたときは押した日の追加の行の日
/// - **打った字そのものは日程に入れない**（自由入力を置かない・綴りの揺れが `/location/*` と噛み合わない）。
///   入るのは結果から選んだ場所だけ
/// - 地図の場所（店・駅・宿）は 1.1.86。ここでは出さない
/// - 前から日程に入っている場所は「N日目に入っています」で押せない（同じ場所を2つ入れない）
struct TripPlanPickSheet: View {

    /// 開いたときの日（押した追加の行の日）
    let startDay: Int
    /// 今の日程（親の下書き。足すたびに親が書き換え、ここへ届き直す）
    let days: [TripDay]
    /// 日ごとの見出し
    let dayLabels: [TripPlanSheetDay]
    /// 候補の材料を取れなかった（圏外など）。**「まだ保存していない」と混ぜない**
    var sourcesFailed = false
    /// 行きたい場所（`TripPlanText.choices`）
    let choices: [TripPlanText.Choice]
    /// 撮影スポットの索引と別名（打った字で観光スポットを探す）
    var index: [OfficialSpot] = []
    var aliases: [String: [String]] = [:]
    /// 候補の季節の一文（その日の月の季節の案内がある行だけ・板 TripPlanPick F30）
    var seasonLine: (TripPlanText.Choice, Int) -> String? = { _, _ in nil }
    /// 入れる（入ったら true）
    let onAdd: (TripItem, Int) -> Bool
    /// このシートで入れた場所を取り消す
    let onUndo: (TripItem, Int) -> Void

    @State private var query = ""
    @State private var chosenDay: Int?
    /// このシートで入れた場所（取り消せるのはこれだけ）
    @State private var addedHere: [TripPlanSearch.Added] = []

    private var day: Int {
        let d = chosenDay ?? startDay
        return days.indices.contains(d) ? d : max(0, min(d, days.count - 1))
    }

    private var groups: TripPlanSearch.Groups {
        TripPlanSearch.groups(query: query, wanted: choices, index: index, aliases: aliases)
    }

    private var searching: Bool { !OfficialSpotIndex.spotName(query).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    // 眉（板: 「1日目 12月24日」の真鍮）→ 明朝の題
                    Text(Self.eyebrow(dayIndex: day, date: dayLabels.indices.contains(day) ? dayLabels[day].date : nil))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(L("場所を足す", "Add places"))
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .accessibilityAddTraits(.isHeader)
                }

                // 探す欄（シートの上端・親指で届く高さ）。人の一覧と同じ部品（高さ 44・角 12・surface-2）
                PeopleSearchField(query: $query, placeholder: TripPlanSearch.placeholder, identifier: "trips.pick.search")

                if days.count > 1 { daySegment }

                Text(TripPlanSearch.hint(dayCount: days.indices.contains(day) ? days[day].items.count : 0))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)

                results
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .webScreen()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
        }
    }

    @ViewBuilder
    private var results: some View {
        let g = groups
        if searching {
            if g.isEmpty {
                Text(TripPlanSearch.noResults(query))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trips.pick.noResults")
            }
            group(L("行きたい場所", "Saved places"), g.wanted)
            group(L("観光スポット", "Photo spots"), g.spots)
        } else if choices.isEmpty && sourcesFailed {
            ErrorBanner(title: L("行きたい場所を読み込めませんでした", "Couldn't load your saved places"),
                        message: L("通信を確かめて、開き直してください", "Check your connection and try again."))
        } else if choices.isEmpty {
            EmptyState(icon: nil, title: L("行きたい場所はまだありません", "No saved places yet"),
                       message: L("上の欄で観光スポットを探して足せます", "Search for photo spots above to add them."))
        } else {
            // **どこから来た候補かを書く。** 「行きたい」はログイン中はサーバーの一覧（`WishlistStore`）
            group(L("行きたい場所", "Saved places"), g.wanted)
        }
    }

    /// 入れる日（板 TripPlanDays の日の見出しと同じ数え方。日が多いときは横に送る）
    private var daySegment: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { di, label in
                    let on = di == day
                    Button {
                        chosenDay = di
                    } label: {
                        Text(label.label)
                            .font(on ? JPFont.footnote.weight(.semibold) : JPFont.footnote)
                            .foregroundStyle(on ? WebTheme.foreground : WebTheme.text2)
                            .padding(.horizontal, JPSpace.m)
                            .frame(minWidth: 72, minHeight: 38)
                            .background(on ? WebTheme.surface8 : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            // 当たりは 44（見た目は 38・板 Components のセグメント）
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(label.label)に入れる", "Add to \(label.label)"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("trips.pick.day.\(di)")
                }
            }
            .padding(.horizontal, 3)
            .background(WebTheme.surface3, in: RoundedRectangle(cornerRadius: JPRadius.field))
        }
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
        let state = TripPlanSearch.state(of: choice.item, days: days, selectedDay: day, addedHere: addedHere)
        let locked = state == .full || { if case .inPlan = state { return true } else { return false } }()
        let season = seasonLine(choice, day)
        let stateText = TripPlanSearch.stateLine(state)
        return Button {
            tap(choice, state: state)
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
                        // 撮影スポットは明朝（台帳の場所）、撮影地は SF の太字（板 TripPlanPick）。大きな文字では折り返す
                        Text(choice.name)
                            .font(choice.isOfficial ? JPFont.rowTitle : JPFont.bodyEmphasis)
                            .foregroundStyle(WebTheme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        // 🔴 **「公式」と書かない**（`OfficialSpot` の注記）。下書きのときだけ「下書き」の札
                        if choice.isDraft {
                            Text(L("下書き", "Draft"))
                                .font(JPFont.caption.weight(.semibold))
                                .foregroundStyle(WebTheme.text2)
                                .padding(.horizontal, 6)
                                .overlay(RoundedRectangle(cornerRadius: JPRadius.xs + 2)
                                    .strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                        }
                    }
                    Text(choice.regionLabel ?? (choice.isOfficial ? L("観光スポット", "Photo spot") : L("撮影地", "Photo location")))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                    // 季節の一文を薄く添える（無い行には出さない・2026-11-10 札 #521）
                    if let season {
                        Text(season)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.faint)
                            .lineLimit(2)
                    }
                    // 入れた・入っている（色だけで伝えない・字で言う）
                    if let stateText {
                        Text(stateText)
                            .font(JPFont.caption.weight(.semibold))
                            .foregroundStyle(state == .added ? WebTheme.accent : WebTheme.text3)
                            .accessibilityIdentifier("trips.pick.state")
                    }
                }
                Spacer(minLength: JPSpace.xs)
                TripAddMark(state: state)
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
        // 名前だけにしない（札の語と県・市も読む）。入れたかは「入れました」で言う
        .accessibilityLabel(L("\(choice.name)\(choice.isDraft ? "、下書き" : "")\(choice.regionLabel.map { "、" + $0 } ?? "")\(season.map { "、" + $0 } ?? "")",
                              "\(choice.name)\(choice.isDraft ? ", draft" : "")\(choice.regionLabel.map { ", " + $0 } ?? "")\(season.map { ", " + $0 } ?? "")"))
        .accessibilityValue(stateText ?? "")
        .accessibilityAddTraits(state == .added ? .isSelected : [])
        .accessibilityHint(state == .added ? L("押すと取り消します", "Tap to undo")
                           : L("押すと\(day + 1)日目に入ります", "Tap to add to day \(day + 1)"))
        .accessibilityIdentifier("trips.pick.row")
    }

    /// 押した。開いていれば入れ、このシートで入れた場所なら取り消す
    private func tap(_ choice: TripPlanText.Choice, state: TripPlanSearch.RowState) {
        let key = SavedSpotsTrip.itemKey(choice.item)
        switch state {
        case .open:
            guard onAdd(choice.item, day) else { return }
            addedHere.append(TripPlanSearch.Added(key: key, day: day))
            announce(L("「\(choice.name)」を\(day + 1)日目に入れました", "Added \(choice.name) to day \(day + 1)"))
        case .added:
            onUndo(choice.item, day)
            if let at = addedHere.lastIndex(of: TripPlanSearch.Added(key: key, day: day)) { addedHere.remove(at: at) }
            announce(L("「\(choice.name)」を取り消しました", "Removed \(choice.name)"))
        case .inPlan, .full:
            return
        }
    }

    private func announce(_ text: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    // MARK: - 計算（Linux で試す）

    /// 眉「1日目 12月24日」
    nonisolated static func eyebrow(dayIndex: Int, date: String?) -> String {
        let day = L("\(dayIndex + 1)日目", "Day \(dayIndex + 1)")
        guard let date, !date.isEmpty else { return day }
        return "\(day)\u{2002}\(date)"
    }
}

/// 入れる印（板 TripPlanPick: 26 の丸）。入れた・入っている は真鍮の塗りに墨のチェック、まだなら白 30% の線に ＋
struct TripAddMark: View {
    let state: TripPlanSearch.RowState

    var body: some View {
        switch state {
        case .added, .inPlan:
            TripPickMark(isOn: true)
        case .open, .full:
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WebTheme.text2)
            }
            .frame(width: TripStyle.pickMark, height: TripStyle.pickMark)
            .accessibilityHidden(true)
        }
    }
}

/// 選んだ印（板 TripPlanPick: 26 の丸。選ぶと真鍮の塗りに墨のチェック、選ばないと白 30% の線）
struct TripPickMark: View {
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
