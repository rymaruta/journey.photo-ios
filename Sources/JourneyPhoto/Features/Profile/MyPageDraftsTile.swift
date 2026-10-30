import SwiftUI
import UIKit

/// マイページの写真の格子の先頭の「下書き」の枠（2026-10-29・#400 の入口に、2026-10-30・#408 で長押しを足した）。
///
/// - **押す**: 下書きの一覧を積む（`onShowList`。積む口は格子の外の `navigationDestination`——
///   遅延の格子の中に置くと効かないことがある）
/// - **長押し（深く押す）**: 浮く絵は最新の下書きの縮図と題・種類・枚数・日時（一覧の長押しと同じ `DraftPreviewCard`）。
///   メニューは「続きから編集」「下書きの一覧を開く」「この下書きを削除」。2件以上なら「最近の下書き」に
///   最大5件（`DraftsTileMenu`）。開くのは一覧と同じ `TabRouter.openDraft`、読めない写真があれば同じ問い
///   （`DraftDialogs`）、消すのは同じ「元に戻す」つきの削除（`DraftDeleteUndo`・呼び手が持つ）
/// - **見た目**: 地に最新の下書きの縮図を淡く敷く（インスタの下書きの枠と同じ）。2026-10-30 判断 #408:
///   縮図の上に黒 78% を重ねる——板の「78% 未満のスクリムは写真の上」の線を越えるので、上は黒い地として扱え、
///   件数バッジ（真鍮＋墨＋黒 2px の縁）を今のまま置ける。字とアイコンは白（板: 写真の上は白）
struct MyPageDraftsTile: View {
    /// 縮図の上の黒の重ね（板の「写真の上」の線 78%）
    nonisolated static let scrimOpacity: Double = 0.78

    let userId: String
    /// バッジの件数（`DraftLibrary.shownCount`・呼び手が持つ。0 なら呼び手が枠ごと出さない）
    let count: Int
    let onShowList: () -> Void
    let onOpen: (DraftLibrary.Entry) -> Void
    let onDelete: ([String]) -> Void

    @ObservedObject private var library = DraftLibrary.shared
    @State private var entries: [DraftLibrary.Entry] = []
    @State private var confirmDelete: [String]?
    @State private var missingTarget: DraftLibrary.Entry?

    init(userId: String, count: Int, onShowList: @escaping () -> Void,
         onOpen: @escaping (DraftLibrary.Entry) -> Void, onDelete: @escaping ([String]) -> Void) {
        self.userId = userId
        self.count = count
        self.onShowList = onShowList
        self.onOpen = onOpen
        self.onDelete = onDelete
    }

    private var menu: DraftsTileMenu { DraftsTileMenu(entries: entries) }

    var body: some View {
        let latest = menu.latest
        Button(action: onShowList) { face(latest) }
            .buttonStyle(.plain)
            .contextMenu {
                menuItems
            } preview: {
                if let latest {
                    DraftPreviewCard(entry: latest, now: library.now())
                } else {
                    face(nil).frame(width: 160)
                }
            }
            .accessibilityLabel(accessibilityLabel(latest))
            .accessibilityHint(DraftsText.tileHint)
            .accessibilityAction(named: DraftsText.continueEditing) { if let latest { open(latest) } }
            .accessibilityAction(named: DraftsText.openList) { onShowList() }
            .accessibilityAction(named: DraftsText.deleteThisDraft) { if let latest { confirmDelete = [latest.id] } }
            .accessibilityIdentifier("mypage.drafts")
            .task(id: TileReload(userId: userId, revision: library.revision)) { reload() }
            .draftDialogs(confirmDelete: $confirmDelete, missingTarget: $missingTarget,
                          onOpen: onOpen, onDelete: onDelete)
    }

    /// 枠の見た目（縦 4:5・地は札の地に白 8% の縁。最新の下書きの縮図を淡く敷き、白の字とアイコン、右上に件数）
    private func face(_ latest: DraftLibrary.Entry?) -> some View {
        Color.clear
            .aspectRatio(ProfileV2.gridAspect, contentMode: .fit)
            .background(WebTheme.card)
            .overlay {
                if let cover = latest?.cover {
                    DraftCover(url: cover, showsFailure: false)
                        .overlay(Color.black.opacity(Self.scrimOpacity))
                }
            }
            .clipped()
            .overlay(Rectangle().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 22, weight: .light))
                    Text(DraftsText.title)
                        .font(JPFont.footnote)
                }
                .foregroundStyle(WebTheme.text)
            }
            .overlay(alignment: .topTrailing) {
                CountBadge(count: count)
                    .padding(JPSpace.xs)
            }
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var menuItems: some View {
        if let latest = menu.latest {
            Button { open(latest) } label: {
                Label(DraftsText.continueEditing, systemImage: "pencil")
            }
        }
        Button { onShowList() } label: {
            Label(DraftsText.openList, systemImage: "square.grid.3x3")
        }
        if let latest = menu.latest {
            // メニューは系統の部品なので系統の赤のまま（CLAUDE.md）
            Button(role: .destructive) { confirmDelete = [latest.id] } label: {
                Label(DraftsText.deleteThisDraft, systemImage: "trash")
            }
        }
        if !menu.recents.isEmpty {
            Section(DraftsText.recentSection) {
                ForEach(menu.recents) { entry in
                    Menu {
                        Button { open(entry) } label: {
                            Label(DraftsText.continueEditing, systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmDelete = [entry.id] } label: {
                            Label(DraftsText.deleteThisDraft, systemImage: "trash")
                        }
                    } label: {
                        Label {
                            Text(DraftsText.title(entry))
                            Text(DraftsText.menuSubtitle(entry, now: library.now()))
                        } icon: {
                            Image(systemName: entry.kind == .story ? "clock" : "photo")
                        }
                    }
                }
            }
        }
    }

    private func accessibilityLabel(_ latest: DraftLibrary.Entry?) -> String {
        let head = DraftsText.entryAccessibility(count)
        guard let latest else { return head }
        return "\(head) · \(DraftsText.accessibility(latest, now: library.now()))"
    }

    /// 開く（読めない写真があれば一覧と同じ問いを出す）
    private func open(_ entry: DraftLibrary.Entry) {
        switch DraftOpenRoute.route(entry) {
        case .askMissing: missingTarget = entry
        case .open: onOpen(entry)
        }
    }

    private func reload() {
        entries = library.entries(for: userId, sendingStoryStamp: StoryUploadCenter.shared.pendingDraftStamp)
    }

    /// 読み直す合図（人が替わった・保存／削除／元に戻す）
    private struct TileReload: Equatable {
        let userId: String
        let revision: Int
    }
}

/// 下書きが変わった（保存・削除・元に戻す `DraftLibrary.revision`）ことを呼び手に伝えるだけの見えない部品。
/// マイページ全体で `DraftLibrary` を見張ると大きな画面を毎回描き直すので、見張るのはこれだけ（#408）
struct DraftRevisionWatcher: View {
    @ObservedObject private var library = DraftLibrary.shared
    let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: library.revision) { _, _ in onChange() }
            .accessibilityHidden(true)
    }
}
