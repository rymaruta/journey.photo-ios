import SwiftUI

/// AI で作ったプランの控え（札 #621）。**アプリを開いている間だけ**持つ
/// （サーバーのプランの形は変えない・理由の文はサーバーに残さない。残すならプランの形を変えるので owner に聞く）
struct TripAINote: Equatable {
    var reason: String
    var mode: TripAIResult.Mode
    /// 移動が無理で外した場所（開いたときに日の下の「外しました　戻す」へ移す）
    var removed: [TripAIRouteCheck.Removed]
    /// 候補（「替える」の残り）
    var candidates: [OfficialSpot]
    /// 行き先を選ばずに作り、アプリが決めた行き先（「行き先はおまかせで、○○にしました」・2026-11-23 owner）
    var autoPlace: String? = nil

    static func == (a: TripAINote, b: TripAINote) -> Bool {
        a.reason == b.reason && a.mode == b.mode && a.removed == b.removed && a.autoPlace == b.autoPlace
            && a.candidates.map(\.spotId) == b.candidates.map(\.spotId)
    }
}

@MainActor
final class TripAINotes: ObservableObject {
    static let shared = TripAINotes()
    @Published private(set) var notes: [String: TripAINote] = [:]

    func set(_ planId: String, _ note: TripAINote) { notes[planId] = note }
    /// ログアウト・退会（次の人に前の人の候補と理由を残さない）
    func removeAll() { notes = [:] }
    func note(_ planId: String) -> TripAINote? { notes[planId] }
    /// 外した場所を日の下の棚へ移した（2度移さない）
    func takeRemoved(_ planId: String) -> [TripAIRouteCheck.Removed] {
        let r = notes[planId]?.removed ?? []
        notes[planId]?.removed = []
        return r
    }
}

/// 日程の画面の上の札（板 Components 05 の札と案内の帯・TripPlanDays の地）。
/// 並べた理由 → AI なしで組んだ理由の帯。
///
/// 2026-11-20 判断（札 #667）: 押すだけの直し（ゆっくり、雨でも、朝を早く、書いて直す）は、どのプランにも出る
/// 日程の上の「組み直す」（`TripReplanBar`）にまとめた。ここから外し、入口を1つにする（同じ画面にチップの列を2つ置かない）
struct TripAICard: View {
    let note: TripAINote
    let usage: TripAIService.Usage?
    let working: Bool
    let online: Bool
    /// AI なしで組んだ理由の帯を出すか（組み直しの帯を出している間は出さない・帯を2本重ねない・札 #667）
    var showsBand = true
    let redo: () -> Void
    let openPro: () -> Void
    /// 開いているか（2026-11-16 判断・使い勝手の見直し A6）。**はじめは1行に畳む**——開いた札は理由の数行と
    /// 直しのチップで日程を1画面ぶん下へ押していた（最初に見える場所 約1.5か所）。押すと開き、もう一度押すと畳む
    @State private var open = false


    /// 畳んだ行の眉と1行。**理由が空なら行ごと出さない**（nil）。
    /// 2026-11-20 判断（札 #667 の確かめ役）: 前は理由が空のとき札の中の押すだけの直しの名前を並べていたが、
    /// その直しは日程の上の「組み直す」へ移したので、もう無いチップを案内していた
    nonisolated static func foldedLine(reason: String) -> (eyebrow: String, text: String)? {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (L("並べた理由", "Why this order"), trimmed)
    }

    /// 畳んだ行の読み上げ（眉と1行。区切りは日本語「、」・英語「, 」）
    nonisolated static func foldedSpoken(reason: String) -> String? {
        foldedLine(reason: reason).map { $0.eyebrow + L("、", ", ") + $0.text }
    }

    /// 札に出す物があるか（理由か、AI なしで組んだ理由の帯）。無ければ画面は札を置かない
    nonisolated static func hasContent(_ note: TripAINote) -> Bool {
        foldedLine(reason: note.reason) != nil || note.mode != .ai
    }

    var body: some View {
        if open { openCard } else { foldedCard }
    }

    /// 畳んだ姿（模型 A6: 高さ 44・札の面・角 12。真鍮の眉「並べた理由」→ 13 の text-2 の1行 → 下向きの印）。
    /// AI なしで組んだ回の帯（つながったら整える・やり直す）は押せる一手なので、畳んでも下に残す
    private var foldedCard: some View {
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            if let line = Self.foldedLine(reason: note.reason) {
            Button { open = true } label: {
                HStack(spacing: 10) {
                    Text(line.eyebrow)
                        .font(JPFont.eyebrow)
                        .foregroundStyle(WebTheme.accent)
                        .fixedSize()
                    Text(line.text)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if working { ProgressView().tint(WebTheme.text2) }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WebTheme.text3)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
                .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.field))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.field).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.foldedSpoken(reason: note.reason) ?? "")
            // 子を畳む（`.ignore`）とボタンの印が落ちる（Mac run 1420 で `tripAI.folded` が Button として見つからなかった。
            // 同じ件の手本: DMSpotCard の run 1096・PhotoDetailView の run 1322）。印を付け直す
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L("押すと開きます", "Opens the details"))
            .accessibilityIdentifier("tripAI.folded")
            }
            band
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tripAI.card")
    }

    private var openCard: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                // 理由が空なら見出しも出さない
                if !note.reason.isEmpty {
                    Text(L("並べた理由", "Why this order"))
                        .font(JPFont.eyebrow)
                        .foregroundStyle(WebTheme.accent)
                }
                Spacer(minLength: 0)
                // 畳む（開いた札の右上・当たり 44）
                Button { open = false } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WebTheme.text3)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("畳む", "Collapse"))
                .accessibilityIdentifier("tripAI.fold")
            }
            if !note.reason.isEmpty {
                Text(note.reason)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tripAI.reason")
            }

            band
        }
        .padding(JPSpace.m)
        .jpCardFace()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tripAI.card")
    }

    /// AI なしで組んだ理由（真鍮 8% の案内の帯）。組み直しの帯を出している間は出さない
    @ViewBuilder
    private var band: some View {
        if showsBand { bandContent }
    }

    @ViewBuilder
    private var bandContent: some View {
        switch note.mode {
        case .ai:
            EmptyView()
        case .usedUp:
            bandRow(icon: "sparkles",
                    title: TripAIText.remainingLine(remaining: 0, resetsOn: usage?.resetsOn ?? TripAIText.nextReset()),
                    sub: usage?.tier == "pro" || usage?.tier == "admin" ? nil
                        : L("Pro なら月\(TripAILimits.pro)回", "Pro: \(TripAILimits.pro) a month"),
                    action: usage?.tier == "pro" || usage?.tier == "admin" ? nil : openPro,
                    id: "tripAI.band.usedUp")
        case .offline:
            bandRow(icon: "wifi.slash", title: L("つながっていないので、AI なしで組みました", "No connection, so this was planned without AI"),
                    sub: online ? L("AI で整える", "Tidy up with AI") : L("つながったら AI で整えられます", "Tidy up with AI once you're online"),
                    action: online ? redo : nil, id: "tripAI.band.offline")
        case .silent:
            bandRow(icon: "exclamationmark.circle", title: L("AI が答えなかったので、AI なしで組みました", "AI didn't answer, so this was planned without AI"),
                    sub: L("AI でやり直す", "Try AI again"), action: redo, id: "tripAI.band.silent")
        case .declined:
            // 2026-11-22 判断: 同意のシートで「やめる」と答えた。押せばもう一度聞いてから AI で整える
            bandRow(icon: "hand.raised", title: L("AI に送らなかったので、AI なしで組みました", "Not sent to AI, so this was planned without AI"),
                    sub: online ? L("AI で整える", "Tidy up with AI") : nil, action: online ? redo : nil, id: "tripAI.band.declined")
        case .limited(let reason):
            // 札 #652: 429 の理由で言い分ける（今日の分、今月の分、1人の止め、全体の止め・`AskLimitText.band`）
            let isPro = usage?.tier == "pro" || usage?.tier == "admin"
            let b = AskLimitText.band(reason: reason, usage: nil, answeredByTable: false, kind: .trip, isPro: isPro)
            bandRow(icon: "sparkles", title: b.title + (b.detail.isEmpty ? "" : "\n" + b.detail), sub: b.proLine,
                    action: b.proLine == nil ? nil : openPro, id: "tripAI.band.limited")
        case .proOnly:
            // 2026-11-20（札 #652）: 端末の AI が無い iPhone の無料の人。サーバーの AI は Pro だけ
            bandRow(icon: "iphone", title: L("この iPhone では AI で組めないため、AI なしで組みました", "AI isn't available on this iPhone, so this was planned without AI"),
                    sub: L("Pro ならサーバーの AI で組めます", "With Pro, our server's AI can plan it"),
                    action: openPro, id: "tripAI.band.proOnly")
        }
    }

    private func bandRow(icon: String, title: String, sub: String?, action: (() -> Void)?, id: String) -> some View {
        Button { action?() } label: {
            HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                Image(systemName: icon).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(JPFont.footnote.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let sub {
                        Text(sub).font(JPFont.caption).underline(action != nil)
                    }
                }
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
        .disabled(action == nil || working)
        .accessibilityIdentifier(id)
    }
}

/// 1か所を替える（AI を使わない・回数0）。近い順に3つ。選ぶと替わる
struct TripAISwapSheet: View {
    let spot: OfficialSpot
    let choices: [OfficialSpot]
    let pick: (OfficialSpot) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("\(spot.name)の代わりに", "Instead of \(spot.name)"))
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .padding(.bottom, JPSpace.xs)
                    if choices.isEmpty {
                        Text(L("近くにほかの候補がありません", "No other places nearby"))
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text3)
                    }
                    ForEach(choices, id: \.spotId) { c in
                        Button {
                            pick(c)
                            dismiss()
                        } label: {
                            HStack(spacing: JPSpace.s) {
                                Group {
                                    if let image = c.photo {
                                        SpotThumbImage(image: image)
                                    } else {
                                        Rectangle().fill(WebTheme.surface3)
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).font(JPFont.rowTitle).foregroundStyle(WebTheme.foreground)
                                    if let hint = c.seasonKeys.compactMap(SpotBodyText.seasonLabel).first ?? c.timeKeys.compactMap(SpotBodyText.timeLabel).first {
                                        Text(hint).font(JPFont.caption).foregroundStyle(WebTheme.text2)
                                    }
                                }
                                Spacer(minLength: 0)
                                if let d = TripAISwap.distanceLabel(spot, c) {
                                    Text(d).font(JPFont.caption).foregroundStyle(WebTheme.text2)
                                }
                            }
                            .frame(minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
                        .accessibilityIdentifier("tripAI.swapChoice")
                    }
                }
                .padding(.horizontal, JPSpace.gutter)
                .padding(.top, JPSpace.xs)
            }
            .webScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
            }
        }
        .presentationDetents([.medium])
    }
}
