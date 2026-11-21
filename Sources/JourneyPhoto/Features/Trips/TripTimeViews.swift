import SwiftUI

// 旅行プランの時刻の部品（札 #677・案A・2026-11-21）。AI の画面の流れ（`AskPlanTimeline`）と旅行プランの頁
// （`TripPlanDetailView`）で同じものを使う。模型: Artifact「旅行プランの時刻」（MkvXR9c17WhfyvQ6Y1BwyC）。

/// 時刻の列の決まり
enum TripTimeStyle {
    /// 時刻の列の幅（字の大きさの設定で伸ばす・`@ScaledMetric(relativeTo: .body)`）
    nonisolated static let columnWidth: CGFloat = 46
    /// 時刻と番号の丸の間
    nonisolated static let columnGap: CGFloat = 10
    /// 時刻の字（SF の等幅数字・15 の medium・本文に追従）
    static var font: Font { JPFont.mono(15, medium: true, relativeTo: .body) }
    /// あきの行・終わりの行の時刻（13・text-3）
    static var minorFont: Font { JPFont.mono(13, relativeTo: .footnote) }
}

/// 時刻の列の1つ（「9:00」）。大きな字でも1行を保つ（板の「等幅の数字は1行を保つ」）
struct TripTimeText: View {
    let minutes: Int?
    var minor = false

    var body: some View {
        Text(minutes.map(TripTimes.clock) ?? "")
            .font(minor ? TripTimeStyle.minorFont : TripTimeStyle.font)
            .foregroundStyle(minor ? WebTheme.text3 : WebTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityHidden(true)
    }
}

/// 日の見出しの右の「出発 9:00 ▾」（押すと下に時刻のチップが開く。押す、選ぶの2回）
struct TripStartButton: View {
    let start: Int
    @Binding var open: Bool
    var identifier = "trip.time.start"

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(TripTimes.startLabel(start))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                Text(TripTimes.clock(start))
                    .font(TripTimeStyle.font.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .fixedSize()
            // 丸いボタンの面は `jpCapsuleFace` を通す（板の模型の .dep: 地 surface-2、縁 白 14%、高さ 32、内側 10）
            .jpCapsuleFace(font: JPFont.footnote, text: WebTheme.text2, fill: WebTheme.sheet, border: WebTheme.line,
                           fullWidth: false, minHeight: 32, textInset: 10)
            // 見た目は 32、当たりは 44
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TripTimes.startSpoken(start))
        .accessibilityHint(TripTimes.startHint)
        .accessibilityValue(open ? L("開いています", "Expanded") : "")
        .accessibilityIdentifier(identifier)
    }
}

/// 出発の時刻のチップ（7:00〜12:00）。選んだものは真鍮の縁と字（黒地の上）＋読み上げの「選択中」
struct TripStartChips: View {
    let start: Int
    let pick: (Int) -> Void

    var body: some View {
        TripChipFlow {
            ForEach(TripTimes.startChoices, id: \.self) { m in
                let on = m == start
                Button {
                    pick(m)
                } label: {
                    Text(TripTimes.clock(m))
                        .font(JPFont.mono(13, medium: on, relativeTo: .footnote))
                        .foregroundStyle(on ? WebTheme.accent : WebTheme.chipText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Color.white.opacity(0.07), in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? WebTheme.accent : WebTheme.hairline, lineWidth: JPStroke.hairline))
                        // 見た目 34、当たり 44
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TripTimes.spokenClock(m))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("trip.time.choice")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("出発の時刻を選ぶ", "Choose a start time"))
    }
}

/// チップを並べる（入りきらなければ2行・大きな字では縦に）
struct TripChipFlow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: JPSpace.xs) { content() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: JPSpace.xs, alignment: .leading)],
                      alignment: .leading, spacing: 0) { content() }
        }
    }
}

/// あきの行・終わりの行（旅行プランの頁・左の列に小さな時刻、右に字）
struct TripTimeMinorRow: View {
    let time: Int
    let text: String
    var spoken: String? = nil
    let inColumn: Bool
    let width: CGFloat
    var identifier = "trip.time.minor"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: inColumn ? TripTimeStyle.columnGap : 6) {
            if inColumn {
                TripTimeText(minutes: time, minor: true)
                    .frame(width: width, alignment: .trailing)
                Color.clear.frame(width: TripStyle.stopNumberSide, height: 1)
            } else {
                TripTimeText(minutes: time, minor: true)
            }
            Text(text)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? (TripTimes.spokenClock(time) + L("、", ", ") + text))
        .accessibilityIdentifier(identifier)
    }
}

/// 時刻の上の一行「時刻は目安です（滞在は場所の種類から）」
struct TripTimeNote: View {
    var body: some View {
        Text(TripTimes.note)
            .font(JPFont.caption)
            .foregroundStyle(WebTheme.text3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("trip.time.note")
    }
}
