import SwiftUI

/// 確認コードの6桁の箱（模型 NL2x「登録の確認コード」・2026-11-23 owner「これでいいよ」）。
/// **登録の確認とパスワードの再設定の両方がこれを使う**（画面ごとに見た目を割らない）。
///
/// - 箱は見せ方だけ。中身は**1つの欄**（`.oneTimeCode`・数字のキーボード）なので、キーボードの上の
///   「メールから」の候補も、長押しの貼り付けも、6桁がそのまま入る（整え方は `VerificationCodeEntry.normalize`）
/// - 6つの箱を3つずつ2組（間 16）、1つ 高さ 58・角 12・地 surface-2（#161617）・縁 outline（#666）。
///   いま打つ箱は真鍮の縁と 18% の外光（板の入力欄のフォーカスと同じ）。黒地の上だけに置く（真鍮は写真の上に置かない）
/// - 数字は SF 600 28pt の等幅数字（`JPFont.number`）
/// - 違うコード: 縁と字を危険の色にし、0.32 秒だけ左右に揺らす。**動きを減らす設定では揺らさない**
/// - 確かめ中・圏外: 箱を薄くする。成功: 真鍮の縁
struct VerificationCodeField: View {

    /// 欄の字（打った字そのまま。整えた6桁は `entry.code`）
    @Binding var text: String
    let entry: VerificationCodeEntry
    var focus: FocusState<AuthFieldFlow.Field?>.Binding
    /// 違うコードのたびに1つ増える（揺らす合図）
    var shakeCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake: CGFloat = 0

    private var isFocused: Bool { focus.wrappedValue == .code }

    var body: some View {
        ZStack {
            // 1つの欄。字と打つ印は透かし、上の箱で見せる（押せば欄に焦点が当たる・長押しで貼り付け）
            JPTextField("", text: $text)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(focus, equals: .code)
                .foregroundStyle(Color.clear)
                .tint(Color.clear)
                .frame(maxWidth: .infinity, minHeight: VerificationCodeLayout.boxHeight)
                .accessibilityLabel(L("確認コード、6桁", "Verification code, 6 digits"))
                .accessibilityValue(spokenValue)
                .accessibilityIdentifier("signin.code")
            boxes
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .offset(x: shake)
        .onChange(of: shakeCount) { _, _ in
            guard !reduceMotion else { return }
            Task { @MainActor in
                for x in VerificationCodeLayout.shakeOffsets {
                    withAnimation(.linear(duration: VerificationCodeLayout.shakeStep)) { shake = x }
                    try? await Task.sleep(nanoseconds: UInt64(VerificationCodeLayout.shakeStep * 1_000_000_000))
                }
            }
        }
    }

    /// 読み上げの値（入った数字を1つずつ）
    private var spokenValue: String {
        entry.code.isEmpty ? L("空", "Empty") : entry.code.map(String.init).joined(separator: " ")
    }

    private var boxes: some View {
        HStack(spacing: VerificationCodeLayout.groupGap) {
            group(0)
            group(VerificationCodeEntry.groupSize)
        }
        .opacity(entry.phase == .checking || entry.phase == .offline ? VerificationCodeLayout.waitingOpacity : 1)
    }

    private func group(_ start: Int) -> some View {
        HStack(spacing: VerificationCodeLayout.boxGap) {
            ForEach(start..<(start + VerificationCodeEntry.groupSize), id: \.self) { index in
                box(index)
            }
        }
    }

    private func box(_ index: Int) -> some View {
        let current = isFocused && entry.currentIndex == index
        let wrong = entry.phase == .wrong && !entry.code.isEmpty
        let shape = RoundedRectangle(cornerRadius: VerificationCodeLayout.boxCorner)
        return ZStack {
            if let digit = entry.digit(at: index) {
                Text(String(digit))
                    .font(JPFont.number(VerificationCodeLayout.digitSize, weight: .semibold, relativeTo: .title))
                    .foregroundStyle(wrong ? WebTheme.danger : WebTheme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else if current {
                VerificationCodeCaret()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: VerificationCodeLayout.boxHeight)
        .background(WebTheme.sheet, in: shape)
        .overlay {
            shape.strokeBorder(borderColor(current: current, wrong: wrong), lineWidth: current ? 1.5 : 1)
        }
        // 板の入力欄のフォーカス: 真鍮の縁と 18% の外光
        .background {
            if current {
                RoundedRectangle(cornerRadius: VerificationCodeLayout.boxCorner + 3)
                    .stroke(WebTheme.accent.opacity(0.18), lineWidth: 3)
                    .padding(-1.5)
            }
        }
    }

    private func borderColor(current: Bool, wrong: Bool) -> Color {
        if wrong { return WebTheme.danger }
        if current || entry.phase == .verified { return WebTheme.accent }
        return WebTheme.outline
    }
}

/// いま打つ箱の印（真鍮の縦線）。**動きを減らす設定では点滅させない**
private struct VerificationCodeCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(WebTheme.accent)
            .frame(width: 2, height: 28)
            .opacity(visible ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { visible = false }
            }
    }
}

extension View {
    /// 箱の下の1行の字（14pt・白 72%・高さ 44。模型 NL2x の `.cline`）
    func codeLineStyle() -> some View {
        self
            .jpSystemFont(14)
            .foregroundStyle(WebTheme.muted2)
            .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("signin.code.line")
    }
}
