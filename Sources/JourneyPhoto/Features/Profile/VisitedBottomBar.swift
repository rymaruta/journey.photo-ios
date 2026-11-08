import SwiftUI

/// 行った県マップの下の帯（同じ日の確かめ・直前の変更の「取り消す」・上限の知らせ）。
///
/// 🔴 画面（`VisitedMapScreen`）の下に重ねるだけだと、県の札（シート）が開いている間は札の下に隠れ、
/// 札の ＋ を押しても確かめも「取り消す」も見えなかった。**札の中にも同じ帯を重ねる**
/// （札が開いている間は画面側の帯を出さない）。確かめが先、なければ直前の変更。
/// 祝いが出ている間は「取り消す」の帯を出さない（祝いの札が下に出る）
struct VisitedBottomBar: View {

    @ObservedObject var model: VisitedMapModel

    var body: some View {
        if let name = model.pendingSameDay {
            HStack(spacing: JPSpace.xs) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(VisitedMapText.sameDayTitle).font(JPFont.footnote.weight(.semibold))
                    Text("\(name) · \(VisitedMapText.sameDayQuestion)").font(JPFont.caption)
                }
                .foregroundStyle(WebTheme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                barButton(VisitedMapText.cancel, id: "visitedMap.sameDay.cancel") { model.cancelSameDay() }
                barButton(VisitedMapText.sameDayAdd, id: "visitedMap.sameDay.add") { model.confirmSameDay() }
            }
            .modifier(BarFace())
            .padding(.horizontal, JPSpace.m)
            .padding(.bottom, JPSpace.m)
            .accessibilityElement(children: .contain)
        } else if let toast = model.toast, model.celebration == nil {
            HStack(spacing: JPSpace.xs) {
                Text(toast.message)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if toast.offersUndo {
                    barButton(VisitedMapText.undo, id: "visitedMap.undo") { model.undo() }
                }
            }
            .modifier(BarFace())
            .padding(.horizontal, JPSpace.m)
            .padding(.bottom, JPSpace.m)
            .accessibilityElement(children: .contain)
        }
    }

    private func barButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.accent)
                .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// 帯の地（トーストの板: 角 14・縁は白 12%）
    private struct BarFace: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(.leading, JPSpace.s)
                .padding(.trailing, JPSpace.xxs)
                .frame(minHeight: 48)
                .background(WebTheme.surface5, in: RoundedRectangle(cornerRadius: JPRadius.m))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.border, lineWidth: JPStroke.hairline))
        }
    }
}
