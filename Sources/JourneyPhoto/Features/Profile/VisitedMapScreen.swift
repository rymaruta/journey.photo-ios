import SwiftUI
import UIKit

/// 行った県マップの画面（札 #503・owner 2026-11-08「案はA」）。
/// 提案書（Artifact・第2版。モックで、実画面ではない）: https://claude.ai/artifact/W9TRaGdrv1LJCYGw3i4z8y
///
/// 置き場はマイページ「旅の記録」の下の札（`VisitedMapEntryCard`）とバッジ「都道府県」の詳細。地図タブには混ぜない。
/// 作りは `VisitedMapModel` の注記のとおり——**回数は本人のタップ（日付つき）だけ・写真は候補・報酬にも公開にも結ばない・
/// 端末の中だけ**。この画面は自分の写真（`myPhotos`）と撮影スポットの台帳を読むが、書くのは端末の記録だけ。
///
/// 状態: 読み込み中（写真から県を調べています）・空（記録も候補も無い）・失敗（記録は残し、写真の調べだけやり直す）・
/// 圏外（地図の形も記録も端末の中なので、そのまま使える。写真の候補の更新だけ待つ）。
///
/// 2026-11-08 判断:
/// - 主ボタンは写真の無い画面なので真鍮の塗り＋墨（板）。数字は SF の等幅数字、題は明朝
/// - 拡大しているあいだは画面のスクロールを止め、地図の移動に譲る（`scrollDisabled`）
/// - 祝いは静かに（札を1枚・触覚の成功を1回・連続や順位や紙吹雪は作らない）
struct VisitedMapScreen: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = VisitedMapModel()
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    @State private var viewport = VisitedMapViewport()
    @State private var mode: Mode = .map
    @State private var geometry: PrefectureMapGeometry?
    @State private var lastTap: (unit: CGPoint, name: String)?
    @State private var confirmAll = false
    @State private var confirmClear = false

    enum Mode: Hashable { case map, list }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.xl) {
                header
                modePicker
                switchRow
                if mode == .map { mapBlock } else { VisitedPrefectureList(model: model) }
                photoStatus
                candidatesBlock
                if model.isEmpty && (model.photosState == .loaded || model.photosState == .failed) { emptyBlock }
                footer
            }
            .padding(.horizontal, ProfileV2.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.screenEnd + JPSpace.xl)
        }
        .scrollDisabled(viewport.isZoomed && mode == .map)
        .webScreen()
        .navigationTitle(VisitedMapText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.undo() } label: {
                    Text(VisitedMapText.undoStep)
                        .font(JPFont.body)
                        .foregroundStyle(model.canUndo ? WebTheme.accent : WebTheme.text3)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                }
                .disabled(!model.canUndo)
                .accessibilityIdentifier("visitedMap.undoStep")
            }
        }
        // 札（シート）が開いている間は、帯は札の中に出る（`VisitedPrefectureCard`・親の帯は札の下に隠れる）
        .overlay(alignment: .bottom) { if model.selected == nil { VisitedBottomBar(model: model) } }
        .overlay(alignment: .bottom) { celebrationCard }
        .sheet(isPresented: cardBinding) {
            VisitedPrefectureCard(model: model, prefecture: model.selected ?? "", nearby: nearbyNames,
                                  onClose: { model.selected = nil })
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(VisitedMapText.allVisitedConfirmTitle, isPresented: $confirmAll, titleVisibility: .visible) {
            Button(VisitedMapText.confirm) { model.markAllVisited() }
            Button(VisitedMapText.cancel, role: .cancel) {}
        } message: {
            Text(VisitedMapText.allVisitedConfirmBody)
        }
        .confirmationDialog(VisitedMapText.clearAllConfirmTitle, isPresented: $confirmClear, titleVisibility: .visible) {
            Button(VisitedMapText.clearConfirm, role: .destructive) { model.clearAll() }
            Button(VisitedMapText.cancel, role: .cancel) {}
        } message: {
            Text(VisitedMapText.clearAllConfirmBody)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.lightTick)
        .sensoryFeedback(.success, trigger: model.successTick)
        .sensoryFeedback(.warning, trigger: model.warningTick)
        .onAppear { model.voiceOverOn = voiceOverOn }
        .onChange(of: voiceOverOn) { _, on in model.voiceOverOn = on }
        .onChange(of: model.announcement) { _, text in
            guard let text else { return }
            UIAccessibility.post(notification: .announcement, argument: text)
            model.clearAnnouncement()
        }
        .task(id: auth.userId) {
            model.open(userId: auth.userId)
            if let seed = PreviewSession.visitedMapSeed { model.seedForPreview(seed) }
            if geometry == nil { geometry = PrefectureMapGeometry.bundled }
            await loadPhotos()
        }
    }

    // MARK: - 読み込み

    private func loadPhotos() async {
        guard auth.userId != nil else { return }
        // 見本の利用者（UI テスト）は鍵を持たず、自分の写真の口は叩けない。地図の絵だけ出す
        if PreviewSession.userId != nil, PreviewSession.visitedMapSeed != nil {
            model.applyPhotos([], spots: [])
            return
        }
        model.beginLoadingPhotos()
        do {
            async let photos = environment.photos.myPhotos()
            async let spots = try? await environment.spots.fetchIndex()
            let loaded = try await photos
            // 台帳だけ読めなかった回は、撮影地の文字だけで県を探す（候補なので足りなくても害は無い）
            let index = await spots
            model.applyPhotos(loaded, spots: index ?? [])
        } catch {
            model.failPhotos()
        }
    }

    // MARK: - 見出し

    private var header: some View {
        let visited = model.record.visitedCount
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            Text(VisitedMapText.title)
                .font(JPFont.screenTitle)
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                Text("\(visited)")
                    .font(JPFont.figureLarge)
                    .foregroundStyle(WebTheme.foreground)
                Text("/ \(VisitedPrefectures.total)")
                    .font(JPFont.number(JPTypeScale.body, weight: .regular, relativeTo: .body))
                    .foregroundStyle(WebTheme.text2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(VisitedMapText.entryAccessibility(visited))
            .accessibilityIdentifier("visitedMap.count")
            if let rounds = VisitedMapText.roundsLine(completed: model.record.completedRounds,
                                                      inProgress: model.record.inProgress) {
                Text(rounds)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.accent)
            }
            if model.photosState == .loaded {
                let b = model.breakdown
                Text(VisitedMapText.breakdown(fromPhotos: b.fromPhotos, byHand: b.byHand))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
                Text(VisitedMapText.breakdownNote)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 切り替えとスイッチ

    /// 地図／一覧（つながったセグメント・板 Components の「表示の切替」）
    private var modePicker: some View {
        HStack(spacing: 2) {
            segment(.map, title: VisitedMapText.showMap, id: "visitedMap.mode.map")
            segment(.list, title: VisitedMapText.showList, id: "visitedMap.mode.list")
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: JPRadius.field))
    }

    private func segment(_ value: Mode, title: String, id: String) -> some View {
        Button { mode = value } label: {
            Text(title)
                .font(mode == value ? JPFont.bodyEmphasis : JPFont.body)
                .foregroundStyle(mode == value ? WebTheme.foreground : WebTheme.text2)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .background(mode == value ? WebTheme.surface8 : Color.clear,
                            in: RoundedRectangle(cornerRadius: JPRadius.s))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    private var switchRow: some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            Toggle(isOn: $model.addsOnTap) {
                Text(VisitedMapText.switchTitle)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.foreground)
            }
            .tint(WebTheme.accent)
            .frame(minHeight: WebTheme.minTapTarget)
            .accessibilityIdentifier("visitedMap.switch")
            Text(VisitedMapText.switchNote(on: model.addsOnTap))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 地図

    @ViewBuilder
    private var mapBlock: some View {
        if let geometry {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                VisitedMapCanvasView(geometry: geometry, model: model, viewport: $viewport,
                                     onTap: { unit, name in lastTap = (unit, name) })
                    .aspectRatio(geometry.size.width / geometry.size.height, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                legend
            }
        } else {
            // 地図の形を読めなかった（同梱のファイルなので通常は起きない）。一覧で続けられる
            Text(VisitedMapText.failedPhotos)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
        }
    }

    /// 凡例（段の見本＋字。色だけに頼らない）。板 04b: 少ない → 多いの順（0・1・2・3 回以上）に並べ、
    /// 段ではない印（写真の候補）は区切り線（1×16・白 14%）の後ろに置く。読み上げは1つの要素で順に読む
    private var legend: some View {
        // 6 つ（区切り線を含む）は 1 行に収まらない幅があるので、折り返して並べる
        FlowLayout(spacing: JPSpace.m, lineSpacing: JPSpace.xs) {
            legendItem(level: 0, candidate: false, text: VisitedMapText.legendZero)
            legendItem(level: 1, candidate: false, text: VisitedMapText.legendTimes(1))
            legendItem(level: 2, candidate: false, text: VisitedMapText.legendTimes(2))
            legendItem(level: 3, candidate: false, text: VisitedMapText.legendThreePlus)
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 16)
            legendItem(level: 0, candidate: true, text: VisitedMapText.legendCandidate)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("凡例: 0 回、1 回、2 回、3 回以上、写真の候補",
                              "Legend: 0, 1, 2, 3 or more, suggested"))
    }

    private func legendItem(level: Int, candidate: Bool, text: String) -> some View {
        HStack(spacing: JPSpace.xxs) {
            VisitedSwatch(level: level, isCandidate: candidate).frame(width: 16, height: 16)
            Text(text).font(JPFont.caption).foregroundStyle(WebTheme.text2).fixedSize()
        }
    }

    // MARK: - 写真の調べ・候補・空

    @ViewBuilder
    private var photoStatus: some View {
        switch model.photosState {
        case .loading:
            HStack(spacing: JPSpace.xs) {
                ProgressView()
                Text(VisitedMapText.loadingPhotos)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
            }
            .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .failed:
            ErrorBanner(message: VisitedMapText.failedPhotos) { Task { await loadPhotos() } }
        case .idle, .loaded:
            EmptyView()
        }
    }

    @ViewBuilder
    private var candidatesBlock: some View {
        let names = model.candidates
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                Text(L("写真の候補 \(names.count) 県", "Suggested from photos: \(names.count)"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityAddTraits(.isHeader)
                Text(VisitedMapText.candidateNote)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: JPSpace.xs) {
                    ForEach(names, id: \.self) { name in
                        Button { model.openCard(name) } label: {
                            Text(name)
                                .font(JPFont.footnote)
                                .foregroundStyle(WebTheme.foreground)
                                .padding(.horizontal, JPSpace.s)
                                .frame(minHeight: WebTheme.minTapTarget)
                                .overlay(Capsule().strokeBorder(WebTheme.accent.opacity(0.7),
                                                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(VisitedMapText.prefectureAccessibility(name, count: 0, isCandidate: true))
                        .accessibilityIdentifier("visitedMap.candidate.\(name)")
                    }
                }
            }
        }
    }

    /// 空（記録も候補も無い）。何が無いか → どうすれば埋まるか → 一手（写真を投稿・写真の無い画面の主ボタン）。
    /// 「47県ぜんぶ行った」は下の足元にある
    private var emptyBlock: some View {
        EmptyState(title: VisitedMapText.emptyTitle, message: VisitedMapText.emptyBody,
                   actionTitle: VisitedMapText.postPhoto, actionIdentifier: "visitedMap.empty.post") {
            TabRouter.shared.openPost(.photo)
        }
        .jpCardFace()
    }

    // MARK: - 足元

    private var footer: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            Text(VisitedMapText.privateNote)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("visitedMap.private")
            if model.record.visitedCount < VisitedPrefectures.total {
                textButton(VisitedMapText.allVisited47, id: "visitedMap.all47") { confirmAll = true }
            }
            if model.record.visitedCount > 0 {
                textButton(VisitedMapText.clearAll, id: "visitedMap.clearAll") { confirmClear = true }
            }
        }
    }

    private func textButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.accent)
                .frame(minHeight: WebTheme.minTapTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - 札・取り消し・同じ日

    private var cardBinding: Binding<Bool> {
        Binding(get: { model.selected != nil }, set: { if !$0 { model.selected = nil } })
    }

    /// 札の「近くの県」。地図を押した点が分かればその近く、一覧などから開いたときは県の中心の近く
    private var nearbyNames: [String] {
        guard let geometry, let name = model.selected else { return [] }
        if let lastTap, lastTap.name == name {
            return geometry.nearby(to: lastTap.unit, excluding: name)
        }
        guard let piece = geometry.piece(name) else { return [] }
        return geometry.nearby(to: piece.anchor, excluding: name)
    }

    // MARK: - 祝い

    /// 静かな祝い。札を1枚（真鍮の細い縁）。連続・順位・紙吹雪は作らない
    @ViewBuilder
    private var celebrationCard: some View {
        // 札を開いている間は出さない（札の下に隠れる）。閉じたあとに出る
        if let celebration = model.celebration, model.selected == nil {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                Text(VisitedMapText.celebrationEyebrow(celebration))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Text(VisitedMapText.celebrationTitle(celebration))
                    .font(JPFont.cardTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text(VisitedMapText.celebrationBody(celebration))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.addsOnTap {
                    Button {
                        model.addsOnTap = true
                        model.dismissCelebration()
                    } label: {
                        Text(VisitedMapText.celebrationRecordCounts).jpPillButton(.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("visitedMap.celebration.counts")
                }
                Button { model.dismissCelebration() } label: {
                    Text(VisitedMapText.close).jpPillButton(.outline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("visitedMap.celebration.close")
            }
            .padding(JPSpace.l)
            .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.xl))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.xl).strokeBorder(WebTheme.accent.opacity(0.45), lineWidth: JPStroke.hairline))
            .padding(.horizontal, JPSpace.m)
            .padding(.bottom, JPSpace.m)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("visitedMap.celebration")
        }
    }
}
