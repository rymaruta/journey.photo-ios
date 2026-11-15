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

    static func == (a: TripAINote, b: TripAINote) -> Bool {
        a.reason == b.reason && a.mode == b.mode && a.removed == b.removed
            && a.candidates.map(\.spotId) == b.candidates.map(\.spotId)
    }
}

@MainActor
final class TripAINotes: ObservableObject {
    static let shared = TripAINotes()
    @Published private(set) var notes: [String: TripAINote] = [:]

    func set(_ planId: String, _ note: TripAINote) { notes[planId] = note }
    func note(_ planId: String) -> TripAINote? { notes[planId] }
    /// 外した場所を日の下の棚へ移した（2度移さない）
    func takeRemoved(_ planId: String) -> [TripAIRouteCheck.Removed] {
        let r = notes[planId]?.removed ?? []
        notes[planId]?.removed = []
        return r
    }
}

/// 日程の画面の上の札（板 Components 05 の札と案内の帯・TripPlanDays の地）。
/// 並べた理由 → AI なしで組んだ理由の帯 → 押すだけの直し（ゆっくり、雨でも、朝を早く、書いて直す）
struct TripAICard: View {
    let note: TripAINote
    let usage: TripAIService.Usage?
    let working: Bool
    let canUndo: Bool
    let online: Bool
    let tweak: (String) -> Void
    let redo: () -> Void
    let undo: () -> Void
    let openPro: () -> Void

    @State private var writing = false
    @State private var text = ""

    private var usedUp: Bool { note.mode == .usedUp || (usage?.remaining ?? 1) <= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("並べた理由", "Why this order"))
                    .font(JPFont.eyebrow)
                    .foregroundStyle(WebTheme.accent)
                Spacer(minLength: 0)
                if canUndo {
                    Button(action: undo) {
                        Label(L("元に戻す", "Undo"), systemImage: "arrow.uturn.backward")
                            .font(JPFont.footnote.weight(.semibold))
                            .foregroundStyle(WebTheme.text)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tripAI.undo")
                }
            }
            Text(note.reason)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tripAI.reason")

            band

            tweaks
            if writing { writeField }
        }
        .padding(JPSpace.m)
        .jpCardFace()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tripAI.card")
    }

    /// AI なしで組んだ理由（真鍮 8% の案内の帯）
    @ViewBuilder
    private var band: some View {
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

    /// 押すだけの直し（AI を1回使う）。使い切ったら PRO の印を付け、押すと Pro の案内
    private var tweaks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JPSpace.xs) {
                ForEach(TripAITweak.allCases) { t in
                    chip(t.title, id: "tripAI.tweak.\(t.rawValue)") { usedUp ? openPro() : tweak(t.request) }
                }
                chip(L("書いて直す", "Write a change"), id: "tripAI.tweak.write") {
                    if usedUp { openPro() } else { writing.toggle() }
                }
            }
        }
        .disabled(working)
        .opacity(working ? TripStyle.disabledOpacity : 1)
    }

    private func chip(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if usedUp {
                    Text("PRO")
                        .font(JPFont.eyebrow)
                        .foregroundStyle(WebTheme.accent)
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(WebTheme.accent, lineWidth: 1))
                }
            }
            .jpOutlineButton(.inline)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var writeField: some View {
        HStack(spacing: JPSpace.xs) {
            JPTextField(L("直したいことを書く", "What to change"), text: $text)
                .submitLabel(.send)
                .onSubmit(submit)
                .accessibilityIdentifier("tripAI.revise")
            Button(action: submit) {
                Image(systemName: "arrow.up").font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(WebTheme.accentText)
                    .background(WebTheme.accentFill, in: Circle())
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(working || text.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(L("直す", "Change"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .frame(minHeight: 48)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.outline, lineWidth: 1))
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !working else { return }
        text = ""
        writing = false
        tweak(t)
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
