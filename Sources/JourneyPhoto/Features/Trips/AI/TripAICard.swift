import SwiftUI

/// AI で作ったプランの「並べた理由」と「外しました　戻す」（札 #621）。
/// **アプリを開いている間だけ**持つ（サーバーのプランの形は変えない・理由の文はサーバーに残さない）
struct TripAINote: Equatable {
    var reason: String
    var removed: [TripAIRouteCheck.Removed]
    var fallbackNote: String?
    /// 作った直後（「〜を作りました　元に戻す」の知らせを1回だけ出す）
    var fresh: Bool
}

@MainActor
final class TripAINotes: ObservableObject {
    static let shared = TripAINotes()
    @Published private(set) var notes: [String: TripAINote] = [:]

    func set(_ planId: String, _ note: TripAINote) { notes[planId] = note }
    func note(_ planId: String) -> TripAINote? { notes[planId] }
    func markSeen(_ planId: String) { notes[planId]?.fresh = false }
    func restored(_ planId: String, _ removed: TripAIRouteCheck.Removed) { notes[planId]?.removed.removeAll { $0 == removed } }
}

/// 日程の画面の上に置く札（板 TripPlanDays の札の地・眉ラベルは真鍮）
struct TripAICard: View {
    let note: TripAINote
    @ObservedObject var composer: TripAIComposerModel
    let restore: (TripAIRouteCheck.Removed) -> Void
    let revise: (String) -> Void

    @State private var request = ""

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            if !note.reason.isEmpty {
                Text(L("並べた理由", "Why this order"))
                    .font(JPFont.eyebrow)
                    .foregroundStyle(WebTheme.accent)
                Text(note.reason)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tripAI.reason")
            }
            if let line = note.fallbackNote {
                Text(line)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(note.removed, id: \.spot.spotId) { r in
                HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                    Text(L("移動が4時間を超えるので、\(r.spot.name)を外しました", "Over 4 hours of travel, so \(r.spot.name) was left out"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(L("戻す", "Put back")) { restore(r) }
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.accent)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("\(r.spot.name)を戻す", "Put \(r.spot.name) back"))
                        .accessibilityIdentifier("tripAI.restore")
                }
            }
            HStack(spacing: JPSpace.xs) {
                JPTextField(L("直したいことを書く", "What to change"), text: $request)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .accessibilityIdentifier("tripAI.revise")
                Button(action: submit) {
                    Group {
                        if composer.phase == .working {
                            ProgressView().tint(WebTheme.accentText)
                        } else {
                            Image(systemName: "arrow.up").font(.body.weight(.semibold))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .foregroundStyle(WebTheme.accentText)
                    .background(WebTheme.accentFill, in: Circle())
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(composer.phase == .working || request.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(L("直す", "Change"))
                .accessibilityIdentifier("tripAI.reviseSend")
            }
            .padding(.leading, 14)
            .padding(.trailing, 2)
            .frame(minHeight: 48)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.outline, lineWidth: 1))
        }
        .padding(JPSpace.m)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tripAI.card")
    }

    private func submit() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, composer.phase != .working else { return }
        request = ""
        revise(text)
    }
}
