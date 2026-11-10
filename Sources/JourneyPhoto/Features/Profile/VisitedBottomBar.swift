import SwiftUI

/// 行った県マップの下の帯（押した県の帯・直前の変更の「取り消す」・上限の知らせ）。
///
/// 🔴 画面（`VisitedMapScreen`）の下に重ねるだけだと、県の札（シート）が開いている間は札の下に隠れ、
/// 札の ＋ を押しても「取り消す」が見えなかった。**札の中にも同じ帯を重ねる**
/// （札が開いている間は画面側の帯を出さない）。押した県の帯が先、なければ直前の変更。
/// 祝いが出ている間は帯を出さない（祝いの札が下に出る。戻すのは右上の「ひとつ戻す」）
///
/// 2026-11-10 判断（札 #510・案 A）: 同じ日の確かめの帯はなくした（押すたびに 1 回足す）
struct VisitedBottomBar: View {

    @ObservedObject var model: VisitedMapModel

    var body: some View {
        if model.quickBar != nil, model.celebration == nil {
            VisitedQuickBar(model: model)
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

/// 押した県の小さな帯（案 A・札 #510。モック: https://claude.ai/artifact/8SCDZoffPx8xW9wZVukher の A の端末）。
/// 「東京都 3 回 ［−］［＋］［詳しく］」と、5 秒の残りを示す 2pt の線。
///
/// - 地はモックどおり surface-2（`WebTheme.sheet`）・縁は白 12%・角 16。黒地の上なので［詳しく］は真鍮の字
/// - ［−］と［＋］は**同じ大きさ（44pt の丸）・同じ縁・同じ字の太さ**（owner 2026-11-10「消すときも簡単に」）。
///   0 回では［−］、上限（99）では［＋］を押せない見た目（字を text-3）にして止める
/// - 県名は明朝 18（Title 3・明朝の下限）、数は SF の等幅数字 20 semibold＋「回」13（モック）
/// - 指で触っている間は消さない（`setQuickBarHeld`）。数が変わったら数を小さく弾ませる（「視差効果を減らす」では動かさない）
/// - 読み上げは帯を1つのまとまりにし、数は「東京都、3 回」と読む
struct VisitedQuickBar: View {

    @ObservedObject var model: VisitedMapModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 指が帯に触れている間（`onEnded` が来なくても離せば戻る `@GestureState`）
    @GestureState private var touching = false
    @State private var bump: Double = 1

    var body: some View {
        if let bar = model.quickBar {
            let name = bar.prefecture
            let count = model.record.count(name)
            HStack(spacing: JPSpace.xs) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(JPFont.rowTitle)
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(count)")
                            .font(JPFont.number(JPTypeScale.figureMedium, weight: .semibold, relativeTo: .title3))
                            .foregroundStyle(WebTheme.foreground)
                            .scaleEffect(bump)
                        Text(L("回", count == 1 ? "time" : "times"))
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VisitedMapText.prefectureAccessibility(name, count: count, isCandidate: false))
                .accessibilityIdentifier("visitedMap.quick.count")
                stepButton(systemName: "minus", label: VisitedMapText.removeOne, enabled: count > 0,
                           id: "visitedMap.quick.minus") { model.quickRemove() }
                stepButton(systemName: "plus", label: VisitedMapText.addVisit,
                           enabled: count < VisitedPrefectures.maxCount,
                           id: "visitedMap.quick.plus") { model.quickAdd() }
                Button { model.openCard(name) } label: {
                    Text(VisitedMapText.details)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.accent)
                        .padding(.horizontal, JPSpace.xxs)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("visitedMap.quick.details")
            }
            .padding(.leading, JPSpace.s)
            .padding(.trailing, JPSpace.xs)
            .padding(.vertical, JPSpace.xs)
            .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.l))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.border, lineWidth: JPStroke.hairline))
            .overlay(alignment: .bottom) { timerLine(bar) }
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.l))
            // 触っている間は消さない（ボタンの押下を邪魔しないよう同時に受ける）
            .simultaneousGesture(DragGesture(minimumDistance: 0).updating($touching) { _, state, _ in state = true })
            .onChange(of: touching) { _, held in model.setQuickBarHeld(held) }
            .onChange(of: count) { old, new in
                guard !reduceMotion, old != new else { return }
                bump = 1.18
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.22)) { bump = 1 }
                }
            }
            .padding(.horizontal, JPSpace.s)
            .padding(.bottom, JPSpace.m)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("visitedMap.quickBar")
        }
    }

    /// 残りの線（モック: 左右 14・下 3・高さ 2。地は白 12%、残りは白 50%）。消える時刻（`deadline`）から
    /// 描くたびに読む（ストーリーの進み具合と同じ `TimelineView`。長い `withAnimation` は UI テストの待ちを延ばす）。
    /// 触っている間（`deadline` が nil）は満ちたまま止める。動かさない設定でも縮める（動きではなく残り時間の表示）
    private func timerLine(_ bar: VisitedMapModel.QuickBar) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: bar.deadline == nil)) { context in
            let remaining = bar.deadline.map { max(0, min(1, $0.timeIntervalSince(context.date) / bar.seconds)) } ?? 1
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Color.white.opacity(0.5))
                    .scaleEffect(x: remaining, y: 1, anchor: .leading)
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 14)
        .padding(.bottom, 3)
        .accessibilityHidden(true)
    }

    private func stepButton(systemName: String, label: String, enabled: Bool, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(enabled ? WebTheme.foreground : WebTheme.text3)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .background(Circle().strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
