import SwiftUI

/// 日程の上の「組み直す」（札 #667・案のページ「AI のほかの使いみち」の案1の模型）。
///
/// 板 Components の chip（`PillChip`・34、左右 14、字 13、選ぶと白の塗りとチェック）を2つ（「雨なら」「もっとゆっくり」）と、
/// 「書いて頼む」（押すと欄が開く・`TripAICard` の書く欄と同じ形）。押すと AI が組んだ案が日程の所に出る（`TripReplanPreview`）。
/// 押す回数: チップ → 「この案にする」の2回（今は AI で作ったプランの札を開く → チップで上書き。ふつうのプランには無かった）
struct TripReplanBar: View {
    /// 組んでいる条件（その間はチップを止め、押したチップを選んだ形にする）
    let working: String?
    /// 案を出している条件
    let proposed: String?
    /// AI で組めなかった回の1行（真鍮 8% の案内の帯）。nil なら出さない
    let notice: String?
    /// 帯から Pro の案内を開けるか
    let noticeOpensPro: Bool
    /// 置き換えたあと、元に戻せるか（画面を開いている間）
    let canUndo: Bool
    /// 「書いて頼む」の欄の下に、打った文をサーバーへ送ることの知らせを出すか（`AskServerNotice.shows`・2026-11-22 判断）
    var serverNotice: Bool = false
    let run: (_ label: String, _ request: String, _ typed: Bool) -> Void
    let undo: () -> Void
    let openPro: () -> Void

    @State private var writing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            HStack(spacing: JPSpace.xs) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JPSpace.xs) {
                        ForEach(TripAITweak.allCases) { t in
                            PillChip(title: t.title, selected: working == t.title || proposed == t.title) {
                                run(t.title, t.request, false)
                            }
                            .accessibilityIdentifier("tripReplan.chip.\(t.rawValue)")
                        }
                        PillChip(title: L("書いて頼む", "Write your own"), selected: writing) {
                            writing.toggle()
                            focused = writing
                        }
                        .accessibilityIdentifier("tripReplan.write")
                    }
                }
                .padding(.vertical, -PillChip.tapSlack)
                if canUndo {
                    Button(action: undo) {
                        Label(L("元に戻す", "Undo"), systemImage: "arrow.uturn.backward")
                            .font(JPFont.footnote.weight(.semibold))
                            .foregroundStyle(WebTheme.text)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityIdentifier("tripReplan.undoApplied")
                }
            }
            .disabled(working != nil)
            .opacity(working != nil ? TripStyle.disabledOpacity : 1)

            if writing {
                writeField
                // 送る前に見える所（欄のすぐ下）に、AI に頼むと同じ部品で出す
                if serverNotice { AskServerNoticeText(id: "tripReplan.serverNotice") }
            }

            if let working {
                HStack(spacing: JPSpace.xs) {
                    ProgressView().tint(WebTheme.text2)
                    Text(L("「\(working)」で組み直しています", "Rearranging: \(working)"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                }
                .frame(minHeight: WebTheme.minTapTarget)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tripReplan.working")
            } else if let notice {
                Button { if noticeOpensPro { openPro() } } label: {
                    HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                        Image(systemName: "sparkles").accessibilityHidden(true)
                        Text(notice)
                            .font(JPFont.footnote.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, JPSpace.s)
                    .padding(.vertical, JPSpace.xs)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!noticeOpensPro)
                .accessibilityIdentifier("tripReplan.notice")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tripReplan.bar")
    }

    /// 自由に打つ欄（120 字まで・打った文は AI を呼ぶ前に `TripReplan.refusesTyped` で見る）
    private var writeField: some View {
        HStack(spacing: JPSpace.xs) {
            JPTextField(L("例: 子どもと一緒、歩く距離を短く", "e.g. With kids, less walking"), text: $text)
                .focused($focused)
                .onChange(of: text) { _, new in
                    if new.count > TripReplan.typedMax { text = String(new.prefix(TripReplan.typedMax)) }
                }
                .submitLabel(.send)
                .onSubmit(submit)
                .accessibilityIdentifier("tripReplan.field")
            Button(action: submit) {
                Image(systemName: "arrow.up").font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(WebTheme.accentText)
                    .background(WebTheme.accentFill, in: Circle())
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(working != nil || text.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(L("組み直す", "Rearrange"))
            .accessibilityIdentifier("tripReplan.send")
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .frame(minHeight: 48)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.outline, lineWidth: 1))
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, working == nil else { return }
        text = ""
        writing = false
        focused = false
        run(t, t, true)
    }
}

/// 組み直した案（日程の所に出す・読むだけ）。上に「今 | 組み直した案」の切り替え、案の行は入れ替えた所に真鍮の点と淡い地
/// （案1の模型の `.row.new`: 真鍮 6% の地・8 の真鍮の点）。下の帯の「元に戻す」「この案にする」は画面が `safeAreaInset` で置く
struct TripReplanPreview: View {
    let proposal: TripReplan.Proposal
    /// 案を見ているか（false なら今の日程）
    @Binding var showingAfter: Bool
    let heading: (Int, TripDay) -> String
    let resolve: (TripItem) -> TripDraft.Place

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            HStack(spacing: JPSpace.xs) {
                PillChip(title: L("今", "Now"), selected: !showingAfter) { showingAfter = false }
                    .accessibilityIdentifier("tripReplan.showBefore")
                PillChip(title: L("組み直した案", "New plan"), selected: showingAfter) { showingAfter = true }
                    .accessibilityIdentifier("tripReplan.showAfter")
            }
            .padding(.vertical, -PillChip.tapSlack)

            if showingAfter, !proposal.reason.isEmpty {
                Text(proposal.reason)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tripReplan.reason")
            }

            let days = showingAfter ? proposal.after : proposal.before
            let numbers = TripStyle.stopNumbers(days.map(\.items.count))
            ForEach(Array(days.enumerated()), id: \.offset) { di, day in
                VStack(alignment: .leading, spacing: 0) {
                    JPEyebrowLine(heading(di, day))
                        .padding(.bottom, JPSpace.xxs)
                    if day.items.isEmpty {
                        Text(L("まだ何も入っていません。", "Nothing planned."))
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text3)
                            .frame(maxWidth: .infinity, minHeight: JPHeight.row, alignment: .leading)
                    }
                    ForEach(Array(day.items.enumerated()), id: \.offset) { ii, item in
                        let place = resolve(item)
                        let changed = showingAfter && proposal.isChanged(day: di, index: ii)
                        row(place, number: numbers.indices.contains(di) && numbers[di].indices.contains(ii) ? numbers[di][ii] : ii + 1,
                            changed: changed)
                    }
                    if showingAfter {
                        let out = proposal.dropped.filter { $0.day == di }.map { resolve($0.item).name }
                        if !out.isEmpty {
                            Text(L("外す所: ", "Removed: ") + out.joined(separator: L("、", ", ")))
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text3)
                                .padding(.top, JPSpace.xs)
                                .accessibilityIdentifier("tripReplan.dropped")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tripReplan.preview")
    }

    private func row(_ place: TripDraft.Place, number: Int, changed: Bool) -> some View {
        HStack(alignment: .center, spacing: JPSpace.s) {
            TripStopLabel(number: number, name: place.name, isSpot: place.isSpot)
            Spacer(minLength: 0)
            if changed {
                Circle().fill(WebTheme.accent).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, JPSpace.s)
        .padding(.horizontal, changed ? JPSpace.xs : 0)
        .frame(maxWidth: .infinity, minHeight: JPHeight.row, alignment: .leading)
        .background(changed ? WebTheme.accent.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
        .accessibilityElement(children: .combine)
        // 色だけで伝えない（読み上げで「入れ替えた」）
        .accessibilityValue(changed ? L("入れ替えた", "Changed") : "")
        .accessibilityIdentifier(changed ? "tripReplan.changedRow" : "tripReplan.row")
    }
}

/// 案の下の帯（案1の模型: 線のボタンと、写真の無い画面の主ボタン「この案にする」＝真鍮の塗りに墨）。
/// 2026-11-20 判断（札 #667 の確かめ役）: 線のボタンは「今のままにする」（模型の「元に戻す」は、置き換えたあとの
/// 「元に戻す」と同じ言葉で紛れる）。別の条件で組み直している間は「この案にする」を止める（古い案を選ばせない）
struct TripReplanActions: View {
    /// 別の条件で組み直している
    let working: Bool
    let discard: () -> Void
    let accept: () -> Void

    var body: some View {
        HStack(spacing: JPSpace.s) {
            Button(action: discard) {
                Text(L("今のままにする", "Keep current")).jpPillButton(.outline, height: JPHeight.primaryButton)
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("案をやめて、今の日程のままにします", "Keeps your current plan"))
            .accessibilityIdentifier("tripReplan.discard")
            Button(action: accept) {
                Text(L("この案にする", "Use this plan")).jpPillButton(.main(onPhoto: false))
            }
            .buttonStyle(.plain)
            .disabled(working)
            .opacity(working ? TripStyle.disabledOpacity : 1)
            .accessibilityIdentifier("tripReplan.accept")
        }
        .jpBottomBar()
    }
}
