import SwiftUI

/// 県の一覧（行った県マップの補助・提案書 第2版 案 C）。地方ごとに「関東 5/7」の見出しと県の行。
/// **行は 52pt（押せる 44pt 以上）**。地図が押しにくい小さな県（埼玉・神奈川・滋賀・大阪・奈良・鳥取・香川・佐賀）の
/// 逃げ道で、VoiceOver の人は地図よりこちらが読みやすい。
/// 行を押すと地図と同じ（スイッチがオンなら 1 回足し、オフなら札を開く）。段は小さな見本（`VisitedSwatch`）と
/// 回数の数字（「9+」まで）で伝え、色だけに頼らない
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
        return Button { model.tap(name) } label: {
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
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VisitedMapText.prefectureAccessibility(name, count: count, isCandidate: candidate))
        .accessibilityHint(VisitedMapText.tapHint(addsCount: model.addsOnTap))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L("札を開く", "Open details")) { model.openCard(name) }
        .accessibilityIdentifier("visitedMap.row.\(name)")
    }
}

/// 段の見本（凡例と一覧の行頭）。地図と同じ塗り・模様（`VisitedMapCanvasView.patternPath`）。
/// 未は斜線、写真の候補は斜線＋真鍮の点線の縁
struct VisitedSwatch: View {

    let level: Int
    var isCandidate = false

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            var shape = Path()
            shape.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
            ctx.fill(shape, with: .color(VisitedMapStyle.color(VisitedMapStyle.fill(forLevel: level))))
            if let line = VisitedMapCanvasView.patternPath(level, bounds: rect) {
                var layer = ctx
                layer.clip(to: shape)
                let color: Color = level == 0
                    ? Color.white.opacity(0.18)
                    : VisitedMapStyle.color(level >= 2 ? VisitedMapStyle.inkOnBright : VisitedMapStyle.inkOnDark).opacity(0.5)
                layer.stroke(line.path, with: .color(color), style: line.style)
            }
            if level == 0 && isCandidate {
                ctx.stroke(shape, with: .color(WebTheme.accent), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            } else {
                ctx.stroke(shape, with: .color(Color.white.opacity(level == 0 ? 0.2 : 0.0)), lineWidth: 0.6)
            }
        }
    }
}
