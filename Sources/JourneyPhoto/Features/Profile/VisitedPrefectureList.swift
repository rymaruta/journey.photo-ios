import SwiftUI

/// 県の一覧（行った県マップの補助・提案書 第2版 案 C）。地方ごとに「関東 5/7」の見出しと県の行。
/// **行は 52pt（押せる 44pt 以上）**。地図が押しにくい小さな県（埼玉・神奈川・滋賀・大阪・奈良・鳥取・香川・佐賀）の
/// 逃げ道で、VoiceOver の人は地図よりこちらが読みやすい。
/// 行を押すと地図と同じ（案 A・2026-11-10: 押す＝1 回足して帯・長押し 0.5 秒＝足さずに帯。画面ごとに操作を割らない）。
/// 段は小さな見本（`VisitedSwatch`）と回数の数字（「9+」まで）で伝え、色だけに頼らない
struct VisitedPrefectureList: View {

    @ObservedObject var model: VisitedMapModel
    /// 長押しで帯を出した行と時刻。指を離したときに来る Button の押下を 1 回だけ飲み込む（足さない）
    @State private var longPressed: VisitedMapTouch.LongPress?

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xl) {
            ForEach(PrefectureRegions.all, id: \.name) { region in
                section(region)
            }
        }
        // 🔴 まとまりにしてから名前を付ける。器の VStack に直に付けると、中の行の名前（`visitedMap.row.<県>`）が
        // すべて `visitedMap.list` に上書きされていた（Mac 947 の要素の木: 行の Button が identifier 'visitedMap.list'）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("visitedMap.list")
    }

    private func section(_ region: PrefectureRegions.Region) -> some View {
        let names = region.prefectures
        let done = names.filter { model.record.count($0) >= 1 }.count
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            HStack {
                Text(L(region.name, PrefectureRegions.englishName(region)))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(done)/\(names.count)")
                    .font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text2)
                    .accessibilityLabel(L("\(names.count) 県のうち \(done) 県", "\(done) of \(names.count)"))
            }
            VStack(spacing: 0) {
                ForEach(names, id: \.self) { name in
                    row(name)
                    if name != names.last { JPCardDivider() }
                }
            }
            .jpCardFace()
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        }
    }

    private func row(_ name: String) -> some View {
        let count = model.record.count(name)
        let level = VisitedPrefectures.level(forCount: count)
        let candidate = model.isCandidate(name)
        // 2026-11-10 判断（レビュー）: 行は Button のまま（ScrollView のスクロールと押した見た目を保つ）。
        // 長押しは同時に受ける `LongPressGesture` で帯を出し、そのあと離したときの Button の押下は飲み込む
        // （`VisitedMapTouch.swallowsTap`）。前の `onTapGesture`＋`onLongPressGesture` はスクロールを邪魔しないか
        // 確かめていなかった（レビューの指摘）。スクロールと長押しで足さないことは UI テストで確かめる
        return Button {
            if VisitedMapTouch.swallowsTap(on: name, after: longPressed, now: Date()) {
                longPressed = nil
                return
            }
            longPressed = nil
            model.tap(name)
        } label: {
            rowLabel(name, count: count, level: level, candidate: candidate)
        }
        // 押している間が終わったら（離した・行の外へずらした・スクロールに取られた）長押しの印の寿命を切る
        .buttonStyle(VisitedRowButtonStyle { pressed in
            if !pressed { longPressed = VisitedMapTouch.released(longPressed, at: Date()) }
        })
        .simultaneousGesture(LongPressGesture(minimumDuration: VisitedMapTouch.longPressSeconds).onEnded { _ in
            longPressed = VisitedMapTouch.LongPress(prefecture: name, at: Date())
            model.peek(name)
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VisitedMapText.prefectureAccessibility(name, count: count, isCandidate: candidate))
        .accessibilityHint(VisitedMapText.tapHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tap(name) }
        .accessibilityAction(named: VisitedMapText.removeOne) { model.decrease(name) }
        .accessibilityAction(named: VisitedMapText.details) { model.openCard(name) }
        .accessibilityIdentifier("visitedMap.row.\(name)")
    }

    private func rowLabel(_ name: String, count: Int, level: Int, candidate: Bool) -> some View {
        HStack(spacing: JPSpace.s) {
            VisitedSwatch(level: level, isCandidate: candidate)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(name)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.foreground)
            Spacer(minLength: 0)
            if count > 0 {
                Text(VisitedMapText.visitCount(count))
                    .font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text2)
            } else if candidate {
                Text(VisitedMapText.legendCandidate)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.accent)
            }
        }
        .padding(.horizontal, JPSpace.m)
        .frame(maxWidth: .infinity, minHeight: JPHeight.row, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 段の見本（凡例と一覧の行頭）。地図と同じ塗り（`VisitedMapStyle.fill(forLevel:)`）・模様なし。
/// 板 04b: 16pt の札（角 4）。0 回は白 20%・0.6pt の縁を内側に、写真の候補は 0 の地に真鍮の破線 1.5pt を内側に
/// （地図と同じく形で切り、線幅を倍にして内側の半分を残す）。塗った段は縁なし
struct VisitedSwatch: View {

    let level: Int
    var isCandidate = false

    var body: some View {
        Canvas { ctx, size in
            var shape = Path()
            shape.addRoundedRect(in: CGRect(origin: .zero, size: size), cornerSize: CGSize(width: 4, height: 4))
            ctx.fill(shape, with: .color(VisitedMapStyle.color(VisitedMapStyle.fill(forLevel: level))))
            guard level == 0 else { return }
            var inside = ctx
            inside.clip(to: shape)
            if isCandidate {
                inside.stroke(shape, with: .color(WebTheme.accent),
                              style: StrokeStyle(lineWidth: VisitedMapStyle.candidateInsideWidth * 2,
                                                 dash: VisitedMapStyle.candidateDash))
            } else {
                inside.stroke(shape, with: .color(Color.white.opacity(VisitedMapStyle.zeroEdgeWhite)),
                              lineWidth: VisitedMapStyle.zeroEdgeWidth * 2)
            }
        }
    }
}

/// 一覧の行の押し方。押している間は行の地を白 6%（札の中の行と同じ手応え・`JPRowButtonStyle`）にし、
/// 押している間の始まりと終わりを渡す（長押しの印の寿命を切るため・2026-11-10 再確認）。
/// 終わりは、離したときだけでなく、行の外へずらした・スクロールに取られたときにも来る
struct VisitedRowButtonStyle: ButtonStyle {
    let onPressChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
            .onChange(of: configuration.isPressed) { _, pressed in onPressChange(pressed) }
    }
}
