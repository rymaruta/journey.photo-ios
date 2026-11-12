import SwiftUI

/// 県の札（行った県マップ・札 #503・提案書 第2版）。押した県の帯の［詳しく］・候補の一覧・読み上げの操作「詳しく」で開く
/// （2026-11-10 札 #510・案 A: 地図を押すと 1 回足すので、札は詳しく見る・日付を直す所になった）。
///
/// - 回数と「−」「＋」。**「−」は 1 回減らし、0 回で記録を外す。**「＋」は上限（99）で止まる。
///   同じ日でも確かめずに足す（2026-11-10 owner「押した数だけ足す」）
/// - 最近の日付を 3 つ。日付はあとから直せる
/// - 写真から見つかった県（候補）には、記録にするのは本人だという一言と「記録する」「候補から外す」。
///   **候補は数にも色にも入らない**
/// - 近くの県を 3 つ（押し間違えた隣へそのまま移れる）
/// - 主ボタンは真鍮の塗り＋墨（写真の無い画面・板どおり）。押せるものは 44pt 以上
struct VisitedPrefectureCard: View {

    @ObservedObject var model: VisitedMapModel
    let prefecture: String
    let nearby: [String]
    let onClose: () -> Void

    private var count: Int { model.record.count(prefecture) }
    private var isCandidate: Bool { model.isCandidate(prefecture) }
    private var wasDismissed: Bool { model.found.contains(prefecture) && model.record.dismissed.contains(prefecture) && count == 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.xl) {
                header
                counter
                photosBlock
                if count == 0 { recordBlock }
                dates
                if !nearby.isEmpty { nearbyBlock }
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.m)
            .padding(.bottom, JPSpace.xl)
        }
        .background(WebTheme.sheet)
        // 確かめと「取り消す」は札の中にも出す（親の画面の帯は札の下に隠れる）
        .overlay(alignment: .bottom) { VisitedBottomBar(model: model) }
        .accessibilityIdentifier("visitedMap.card")
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                if let region = PrefectureRegions.region(of: prefecture) {
                    Text(L(region.name, PrefectureRegions.englishName(region)))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                }
                Text(prefecture)
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Text(VisitedMapText.close)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.accent)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("visitedMap.card.close")
        }
    }

    // MARK: - その県で撮った自分の写真（2026-11-12 判断・案「県の札に写真」）

    /// 画面が読んだ自分の写真から県で分けたもの（新しい口なし）。無ければ何も出さない
    @ViewBuilder
    private var photosBlock: some View {
        let photos = model.photosByPrefecture[prefecture] ?? []
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                // 題と枚数は区切りの記号を使わず、余白と字（枚数は等幅の数字）で分ける
                HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                    Text(L("\(prefecture)で撮った写真", "Your photos in \(prefecture)"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                    Text(L("\(photos.count) 枚", Plural.count(photos.count, "photo")))
                        .font(JPFont.number(JPTypeScale.footnote, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(WebTheme.text3)
                }
                HStack(spacing: 2) {
                    ForEach(photos.prefix(4)) { photo in
                        PhotoFrame(photo: photo, aspect: 1, corner: 0)
                    }
                    ForEach(0..<max(0, 4 - photos.count), id: \.self) { _ in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(prefecture)で撮った写真 \(photos.count) 枚", "\(photos.count) of your photos in \(prefecture)"))
                .accessibilityIdentifier("visitedMap.card.photos")
            }
        }
    }

    // MARK: - 回数

    private var counter: some View {
        HStack(spacing: JPSpace.m) {
            stepButton(systemName: "minus", label: VisitedMapText.removeVisit, enabled: count > 0,
                       id: "visitedMap.card.minus") { model.remove(prefecture) }
            VStack(spacing: 0) {
                Text(count > 0 ? String(count) : "–")
                    .font(JPFont.figureLarge)
                    .foregroundStyle(WebTheme.foreground)
                Text(count > 0 ? L("回", count == 1 ? "time" : "times") : VisitedMapText.legendNone)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
            }
            .frame(minWidth: 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count > 0 ? VisitedMapText.visitCount(count) : VisitedMapText.legendNone)
            stepButton(systemName: "plus", label: VisitedMapText.addVisit,
                       enabled: count < VisitedPrefectures.maxCount,
                       id: "visitedMap.card.plus") { model.add(prefecture) }
            Spacer(minLength: 0)
        }
    }

    private func stepButton(systemName: String, label: String, enabled: Bool, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
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

    // MARK: - 記録する（0 回のとき）

    private var recordBlock: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            if isCandidate {
                Text(VisitedMapText.candidateNote)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { model.add(prefecture) } label: {
                Text(VisitedMapText.record).jpPillButton(.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("visitedMap.card.record")
            if isCandidate {
                Button { model.dismissCandidate(prefecture) } label: {
                    Text(VisitedMapText.dismissCandidate).jpPillButton(.outline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("visitedMap.card.dismiss")
            } else if wasDismissed {
                Button { model.restoreCandidate(prefecture) } label: {
                    Text(VisitedMapText.restoreCandidate)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: JPHeight.secondaryButton)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 日付

    @ViewBuilder
    private var dates: some View {
        let days = model.record.days(prefecture)
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            Text(VisitedMapText.recentDates)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .accessibilityAddTraits(.isHeader)
            if days.isEmpty {
                Text(VisitedMapText.noDates)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text3)
            } else {
                // 新しい 3 つ（保存は古い順）
                let start = max(0, days.count - 3)
                ForEach(Array(days.indices.reversed().filter { $0 >= start }), id: \.self) { index in
                    dateRow(index: index, day: days[index])
                }
            }
        }
    }

    private func dateRow(index: Int, day: String) -> some View {
        let binding = Binding<Date>(
            get: { VisitedDay.date(from: day) ?? Date() },
            set: { model.changeDay(prefecture, at: index, to: VisitedDay.string(from: $0)) })
        return HStack {
            DatePicker(day, selection: binding,
                       in: Date(timeIntervalSince1970: 0)...Date(), displayedComponents: .date)
                .labelsHidden()
                .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
                .accessibilityLabel(L("\(day) の記録の日付", "Visit dated \(day)"))
            Spacer(minLength: 0)
        }
    }

    // MARK: - 近くの県

    private var nearbyBlock: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            Text(VisitedMapText.nearby)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: JPSpace.xs) {
                ForEach(nearby, id: \.self) { name in
                    Button { model.selected = name } label: {
                        VStack(spacing: 0) {
                            Text(name).font(JPFont.footnote).foregroundStyle(WebTheme.foreground).lineLimit(1)
                            Text(model.record.count(name) > 0 ? VisitedMapText.visitCount(model.record.count(name))
                                                              : VisitedMapText.legendNone)
                                .font(JPFont.caption).foregroundStyle(WebTheme.text2)
                        }
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .overlay(RoundedRectangle(cornerRadius: JPRadius.field)
                            .strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(VisitedMapText.prefectureAccessibility(
                        name, count: model.record.count(name), isCandidate: model.isCandidate(name)))
                    .accessibilityIdentifier("visitedMap.card.nearby.\(name)")
                }
            }
        }
    }
}
