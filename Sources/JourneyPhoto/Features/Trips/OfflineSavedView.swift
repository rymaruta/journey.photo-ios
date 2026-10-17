import SwiftUI

/// 保存した旅（板 72e・2026-10-09）。入口は設定の「Pro」の節の「保存した旅」。
///
/// **Pro が切れても見られる・消せる**（新しく保存・保存し直すだけ Pro・owner 2026-10-09）。
/// **帰ってきた旅を自動では消さない**——消すのはここか、旅行プランの札から
struct OfflineSavedView: View {

    @EnvironmentObject private var offline: OfflineTripStore
    @State private var removing: OfflineTripManifest?
    @State private var removingAll = false
    @State private var freeSpace: Int64?
    /// 0件の一手「旅行プランを開く」（保存は旅行プランの画面から・2026-10-17）
    @State private var showPlans = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 大見出し（v2 の板 OfflineSaved: 明朝の題）
                Text(L("保存した旅", "Offline trips"))
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)

                usageCard
                    .padding(.top, JPSpace.m)

                if offline.saved.isEmpty {
                    EmptyState(message: L("電波なしで使える旅はまだありません。旅行プランの画面から保存できます。",
                                          "No offline trips yet. Save one from a trip plan."),
                               actionTitle: Self.openPlansTitle, actionIdentifier: "offlineSaved.emptyPlans") {
                        showPlans = true
                    }
                        .padding(.top, JPSpace.xs)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        JPEyebrowLine(L("電波なしで使える旅 · \(offline.saved.count) 件",
                                        "Offline trips · \(offline.saved.count)"))
                            .padding(.bottom, JPSpace.xxs)
                        ForEach(offline.saved) { manifest in
                            row(manifest)
                        }
                    }
                    .padding(.top, 22)
                }

                // 保存済みが無くても、途中のもの（止めた保存・プランを消した旅）が残っていれば出す。
                // v2 の板: 札で囲まず、`WebTheme.danger` の字の行を1つ
                if offline.hasLocalData {
                    Button {
                        removingAll = true
                    } label: {
                        Text(L("保存した旅をすべて端末から削除", "Remove all offline trips from iPhone"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.danger)
                            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }

                Text(L("端末から削除しても、旅行プランは消えません。電波のあるところで、旅行プランの画面からいつでも保存し直せます。",
                       "Removing from your iPhone doesn't delete the trip plan. You can save it again from the trip plan anytime you have a signal."))
                    .font(JPFont.caption)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.top, 6)
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.screenEnd)
        }
        .webScreen()
        .navigationTitle(L("保存した旅", "Offline trips"))
        .navigationBarTitleDisplayMode(.inline)
        // 題は画面の中の明朝の大見出し（同じ語を上のバーに2度出さない）。戻るの名前に `navigationTitle` は残す
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
        .task { freeSpace = Self.freeSpace() }
        .navigationDestination(isPresented: $showPlans) { TripPlansView() }
        .confirmationDialog(L("「\(removing?.title ?? "")」を端末から削除しますか？", "Remove \"\(removing?.title ?? "")\" from this iPhone?"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button(L("削除する", "Remove"), role: .destructive) {
                if let planId = removing?.planId { offline.delete(planId) }
                removing = nil
            }
            Button(Labels.Common.cancel, role: .cancel) { removing = nil }
        } message: {
            Text(OfflineTripText.deleteBody(bytes: removing?.bytes ?? 0))
        }
        .confirmationDialog(L("保存した旅をすべて端末から削除しますか？", "Remove all offline trips from this iPhone?"),
                            isPresented: $removingAll, titleVisibility: .visible) {
            Button(L("すべて削除する", "Remove all"), role: .destructive) { offline.deleteAll() }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(OfflineTripText.deleteBody(bytes: offline.totalBytes))
        }
    }

    /// 0件の一手。行き先の画面の名前と同じ語（設定・メニューの「旅行プラン」）
    nonisolated static var openPlansTitle: String { L("旅行プランを開く", "Open trip plans") }

    /// iPhone の空き（設定アプリの「iPhone ストレージ」に近い数え方）。読めなければ nil（出さない）
    ///
    /// **理由の申告が要る API**（ディスクの空き）。`PrivacyInfo.xcprivacy` に 85F4.1（本人に見せるだけ・外へ送らない）
    /// で申告してある。書く前の確かめや送信に使うなら理由を足すこと（2026-10-16）
    private static func freeSpace() -> Int64? {
        #if os(Linux)
        return nil
        #else
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        #endif
    }

    /// 使っている容量の札（v2 の板 OfflineSaved: 12 の名前 → 細い大きな数字と 13 の単位 → 真鍮の線 → 空き）
    private var usageCard: some View {
        let parts = TripStyle.splitBytes(OfflineTripBytes.label(offline.totalBytes))
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("この iPhone で使っている容量", "Space used on this iPhone"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
            HStack(alignment: .firstTextBaseline, spacing: JPSpace.xxs) {
                Text(parts.number)
                    .font(JPFont.figureLarge)
                    .foregroundStyle(WebTheme.text)
                if !parts.unit.isEmpty {
                    Text(parts.unit)
                        .font(JPFont.mono(13, relativeTo: .footnote))
                        .foregroundStyle(WebTheme.text3)
                }
            }
            .accessibilityElement(children: .combine)
            if let fraction = TripStyle.usageFraction(used: offline.totalBytes, free: freeSpace) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(TripStyle.progressTrackOpacity))
                        // 小さすぎて見えない割合でも、点としては見せる
                        Capsule().fill(WebTheme.accent)
                            .frame(width: max(geo.size.width * fraction, offline.totalBytes > 0 ? TripStyle.progressHeight : 0))
                    }
                }
                .frame(height: TripStyle.progressHeight)
                .accessibilityHidden(true)
            }
            if let freeSpace {
                Text(L("iPhone の空き \(OfflineTripBytes.label(freeSpace))", "\(OfflineTripBytes.label(freeSpace)) free on iPhone"))
                    .font(JPFont.meta)
                    .foregroundStyle(WebTheme.text3)
            }
        }
        .offlineCardFace()
    }

    /// 行（v2 の板 OfflineSaved: 84・左に 56 の作例 → 明朝の題 → 等幅の1行 → 右に赤のごみ箱・下に区切り線）
    private func row(_ manifest: OfflineTripManifest) -> some View {
        HStack(spacing: JPSpace.xxs) {
            NavigationLink {
                OfflineTripView(manifest: manifest, preview: true)
            } label: {
                HStack(spacing: JPSpace.s) {
                    OfflineStoredImage(url: offline.fileURL(planId: manifest.planId,
                                                            file: manifest.days.lazy.flatMap(\.stops).first { !$0.samples.isEmpty }?.samples.first?.file))
                        .frame(width: TripStyle.savedThumb, height: TripStyle.savedThumb)
                        .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        // 板は 17 だが、明朝の下限 18（`JPTypeScale.title3`）を守る
                        Text(manifest.title.isEmpty ? L("無題のプラン", "Untitled trip") : manifest.title)
                            .font(JPFont.rowTitle)
                            .foregroundStyle(WebTheme.text)
                            .multilineTextAlignment(.leading)
                        Text(OfflineTripText.savedRow(manifest))
                            .font(JPFont.meta)
                            .foregroundStyle(WebTheme.text3)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: TripStyle.savedRowMinHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(JPRowButtonStyle())
            Button {
                removing = manifest
            } label: {
                // 板: ごみ箱は `danger`（端末から消す・CLAUDE.md の危険の色）
                Image(systemName: "trash")
                    .font(.system(size: 17))
                    .foregroundStyle(WebTheme.danger)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("「\(manifest.title)」を端末から削除", "Remove \(manifest.title) from iPhone"))
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }
}

/// 設定の「Pro」の節の4行目（板 43・72e の注記）。**端末に保存した旅（途中のものを含む）があるか Pro のときだけ**出す
struct OfflineSavedSettingsRow: View {
    let isPro: Bool
    @EnvironmentObject private var offline: OfflineTripStore

    var body: some View {
        if isPro || offline.hasLocalData {
            JPCardDivider()
            NavigationLink { OfflineSavedView() } label: {
                // 板 v2（Settings）: 行の絵を外し、件数と容量は右の値（等幅）に
                JPRowLabel(title: L("保存した旅", "Offline trips"),
                           value: OfflineTripText.settingsDetail(count: offline.saved.count, bytes: offline.totalBytes))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("settings.offlineTrips")
        }
    }
}
