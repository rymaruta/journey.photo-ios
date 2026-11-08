import SwiftUI

extension PrefectureMapGeometry {
    /// 同梱の `japan-prefectures.json` から1度だけ作る（入口の札と画面で共有）
    static let bundled: PrefectureMapGeometry? =
        PrefectureMapGeometry.build(shapes: ShareCardMap.loadShapes(resource: "japan-prefectures"))
}

/// マイページ「旅の記録」の下の札「行った県 31/47」（札 #503・提案書 第2版）。押すと専用の画面（`VisitedMapScreen`）。
/// 右の薄い絵は**色の段の縮図**（見るだけ。県を押せる地図は画面の中）。
///
/// - 数は端末の記録（`VisitedPrefectureStore`）から。読み上げは「行った県、31 / 47、ボタン」
/// - 形は既存の札と同じ（角 14・行 64・板の `.card`）。数は SF の等幅数字
/// - 記録が 0 でも出す（空の状態と「47県ぜんぶ行った」はこの先の画面にある）
/// - **この数は硬貨・バッジ・家具・Pro にも他人にも関係しない**（本人の記録）。バッジ「都道府県」の数とは別
struct VisitedMapEntryCard: View {

    @EnvironmentObject private var auth: AuthStore
    @State private var record = VisitedPrefectures()

    /// 札の縮図の幅と高さ
    nonisolated static let thumbnailSize = CGSize(width: 44, height: 50)

    var body: some View {
        NavigationLink {
            VisitedMapScreen()
        } label: {
            HStack(spacing: JPSpace.s) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    Text(VisitedMapText.title)
                        .font(JPFont.rowTitle)
                        .foregroundStyle(WebTheme.foreground)
                    Text(VisitedMapText.ratio(record.visitedCount))
                        .font(JPFont.mono(JPTypeScale.footnote, relativeTo: .footnote))
                        .foregroundStyle(WebTheme.text2)
                }
                Spacer(minLength: 0)
                VisitedMapThumbnail(counts: record.counts)
                    .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, JPSpace.m)
            .frame(maxWidth: .infinity, minHeight: JPHeight.tallRow, alignment: .leading)
            .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ProfileV2.gutter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VisitedMapText.entryAccessibility(record.visitedCount))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("profile.visitedMap")
        .task(id: auth.userId) { record = VisitedPrefectureStore().load(for: auth.userId) }
        .onAppear { record = VisitedPrefectureStore().load(for: auth.userId) }
    }
}

/// 色の段の縮図（見るだけ）。段ごとの塗りだけで、模様と字は付けない
struct VisitedMapThumbnail: View {

    let counts: [Int]

    var body: some View {
        Canvas { ctx, size in
            guard let geometry = PrefectureMapGeometry.bundled else { return }
            let scale = min(size.width / geometry.size.width, size.height / geometry.size.height)
            let offsetX = (size.width - geometry.size.width * scale) / 2
            let offsetY = (size.height - geometry.size.height * scale) / 2
            for (index, name) in RegionList.prefectures.enumerated() {
                guard index < counts.count, let piece = geometry.piece(name), !piece.inInset else { continue }
                var path = Path()
                for polygon in piece.polygons {
                    guard let first = polygon.first else { continue }
                    path.move(to: CGPoint(x: offsetX + first.x * scale, y: offsetY + first.y * scale))
                    for p in polygon.dropFirst() {
                        path.addLine(to: CGPoint(x: offsetX + p.x * scale, y: offsetY + p.y * scale))
                    }
                    path.closeSubpath()
                }
                let level = VisitedPrefectures.level(forCount: counts[index])
                ctx.fill(path, with: .color(level == 0 ? Color.white.opacity(0.1)
                                                        : ProMarkColors.color(VisitedMapStyle.fill(forLevel: level))))
            }
        }
    }
}
