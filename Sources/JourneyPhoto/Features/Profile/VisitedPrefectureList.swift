import SwiftUI

/// 県の一覧（行った県マップの補助・提案書 第2版 案 C）。地方ごとに「関東 5/7」の見出しと県の行。
/// **行は 52pt（押せる 44pt 以上）**。地図が押しにくい小さな県（埼玉・神奈川・滋賀・大阪・奈良・鳥取・香川・佐賀）の
/// 逃げ道で、VoiceOver の人は地図よりこちらが読みやすい。
/// 行を押すと地図と同じ（案 A・2026-11-10: 押す＝1 回足して帯・長押し 0.5 秒＝足さずに帯。画面ごとに操作を割らない）。
/// 段は小さな見本（`VisitedSwatch`）と回数の数字（「9+」まで）で伝え、色だけに頼らない
struct VisitedPrefectureList: View {

    @ObservedObject var model: VisitedMapModel

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xl) {
            ForEach(PrefectureRegions.all, id: \.name) { region in
                section(region)
            }
        }
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
        return HStack(spacing: JPSpace.s) {
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
        // 押す＝1 回足す・長押し＝足さずに帯（Button だと長押しのあとも押したことになり 1 回足してしまうので、
        // 2 つの手振りに分ける。長押しに届いた指では押したことにならない）
        .onTapGesture { model.tap(name) }
        .onLongPressGesture(minimumDuration: VisitedMapCanvasView.longPressSeconds) { model.peek(name) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VisitedMapText.prefectureAccessibility(name, count: count, isCandidate: candidate))
        .accessibilityHint(VisitedMapText.tapHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tap(name) }
        .accessibilityAction(named: VisitedMapText.removeOne) { model.decrease(name) }
        .accessibilityAction(named: VisitedMapText.details) { model.openCard(name) }
        .accessibilityIdentifier("visitedMap.row.\(name)")
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
