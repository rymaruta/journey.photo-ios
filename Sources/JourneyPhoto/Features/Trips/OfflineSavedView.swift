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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("この iPhone で使っている容量", "Space used on this iPhone"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                    Text(OfflineTripBytes.label(offline.totalBytes))
                        .font(JPFont.number(28, weight: .semibold, relativeTo: .title))
                        .foregroundStyle(WebTheme.text)
                    if let freeSpace {
                        Text(L("iPhone の空き \(OfflineTripBytes.label(freeSpace))", "\(OfflineTripBytes.label(freeSpace)) free on iPhone"))
                            .font(JPFont.mono(12))
                            .foregroundStyle(WebTheme.faint)
                    }
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)

                if offline.saved.isEmpty {
                    Text(L("電波なしで使える旅はまだありません。旅行プランの画面から保存できます。",
                           "No offline trips yet. Save one from a trip plan."))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                        .padding(.horizontal, 4)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        JPSectionTitle(L("電波なしで使える旅 · \(offline.saved.count) 件",
                                         "Offline trips · \(offline.saved.count)"))
                        JPCard {
                            ForEach(Array(offline.saved.enumerated()), id: \.element.planId) { i, manifest in
                                if i > 0 { JPCardDivider() }
                                row(manifest)
                            }
                        }
                    }

                    JPCard {
                        Button {
                            removingAll = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash").frame(width: 20).accessibilityHidden(true)
                                Text(L("保存した旅をすべて端末から削除", "Remove all offline trips from iPhone"))
                                Spacer(minLength: 0)
                            }
                            .font(.body)
                            .foregroundStyle(WebTheme.danger)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(JPRowButtonStyle())
                    }
                }

                Text(L("端末から削除しても、旅行プランは消えません。電波のあるところで、旅行プランの画面からいつでも保存し直せます。",
                       "Removing from your iPhone doesn't delete the trip plan. You can save it again from the trip plan anytime you have a signal."))
                    .font(.caption)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .webScreen()
        .navigationTitle(L("保存した旅", "Offline trips"))
        .navigationBarTitleDisplayMode(.inline)
        .task { freeSpace = Self.freeSpace() }
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

    /// iPhone の空き（設定アプリの「iPhone ストレージ」に近い数え方）。読めなければ nil（出さない）
    private static func freeSpace() -> Int64? {
        #if os(Linux)
        return nil
        #else
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        #endif
    }

    private func row(_ manifest: OfflineTripManifest) -> some View {
        HStack(spacing: 4) {
            NavigationLink {
                OfflineTripView(manifest: manifest, preview: true)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manifest.title.isEmpty ? L("無題のプラン", "Untitled trip") : manifest.title)
                        .font(JPFont.display(17, relativeTo: .body))
                        .foregroundStyle(WebTheme.text)
                        .multilineTextAlignment(.leading)
                    Text(OfflineTripText.savedRow(manifest))
                        .font(JPFont.mono(12))
                        .foregroundStyle(WebTheme.faint)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(JPRowButtonStyle())
            Button {
                removing = manifest
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17))
                    .foregroundStyle(WebTheme.muted2)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("「\(manifest.title)」を端末から削除", "Remove \(manifest.title) from iPhone"))
        }
        .padding(.trailing, 6)
    }
}

/// 設定の「Pro」の節の4行目（板 43・72e の注記）。**保存した旅があるか Pro のときだけ**出す
struct OfflineSavedSettingsRow: View {
    let isPro: Bool
    @EnvironmentObject private var offline: OfflineTripStore

    var body: some View {
        if isPro || !offline.saved.isEmpty {
            JPCardDivider()
            NavigationLink { OfflineSavedView() } label: {
                JPRowLabel(title: L("保存した旅", "Offline trips"),
                           detail: OfflineTripText.settingsDetail(count: offline.saved.count, bytes: offline.totalBytes),
                           icon: AnyView(OfflinePhoneIcon(saved: true, side: 20)))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("settings.offlineTrips")
        }
    }
}
