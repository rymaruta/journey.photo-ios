import SwiftUI

/// 下書きの削除と「元に戻す」（約6秒）。下書きの一覧（`DraftsView`）とマイページの「下書き」の枠
/// （`MyPageDraftsTile`）が**同じものを使う**（2026-10-30 判断 #408: 一覧の中に書いてあった流れを外に出した。
/// 写しを2つ持つと、片方だけ「画像を消すのは元に戻すの後」が抜ける）。
///
/// 流れ: 削除を押す → `DraftLibrary.hide`（一覧・件数から隠すだけ）→ 約6秒「元に戻す」を待つ →
/// `DraftLibrary.finalize`（記録と画像を本当に消す）。前の削除の「元に戻す」は積まずに締め切る。
@MainActor
final class DraftDeleteUndo: ObservableObject {

    /// 「元に戻す」を待っている削除（無ければ nil）
    @Published private(set) var pending: [String]?

    private let library: DraftLibrary
    private let seconds: Double
    private var owner = ""
    private var task: Task<Void, Never>?

    init(library: DraftLibrary? = nil, seconds: Double = DraftLibrary.undoSeconds) {
        self.library = library ?? DraftLibrary.shared
        self.seconds = seconds
    }

    /// 削除（隠す）→ 約6秒後に本当に消す。**画面が閉じても時間が来れば消す**（隠したまま残さない）
    func delete(_ ids: [String], owner: String) {
        guard !ids.isEmpty else { return }
        finish()
        library.hide(ids)
        pending = ids
        self.owner = owner
        let library = library
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            library.finalize(ids, for: owner)
            if self?.pending == ids {
                self?.pending = nil
                self?.task = nil
            }
        }
    }

    /// 「元に戻す」（隠していたものを元の位置に戻す）
    func undo() {
        guard let ids = pending else { return }
        task?.cancel()
        task = nil
        pending = nil
        library.undo(ids)
    }

    /// 待っている削除をいま済ませる（一覧を閉じた・次の削除を押した）
    func finish() {
        guard let ids = pending else { return }
        task?.cancel()
        task = nil
        pending = nil
        library.finalize(ids, for: owner)
    }
}

/// 削除のあとの「元に戻す」の札（約6秒）。成功の印は緑、ボタンは真鍮（黒い札の上）。
/// 置き場は呼び手の画面の下（`.overlay(alignment: .bottom)`）
struct DraftUndoBar: View {
    @ObservedObject var deleter: DraftDeleteUndo
    /// 「元に戻す」の目印（一覧は `drafts.undo`・マイページは `mypage.drafts.undo`）
    var identifier = "drafts.undo"

    var body: some View {
        if let ids = deleter.pending {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WebTheme.success)
                    .accessibilityHidden(true)
                Text(DraftsText.deleted(ids.count))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { deleter.undo() } label: {
                    Text(DraftsText.undo)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.accent)
                        .padding(.horizontal, 10)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(WebTheme.surface6, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
            .padding(.horizontal, JPSpace.s)
            .padding(.bottom, JPSpace.l)
            .accessibilityElement(children: .contain)
        }
    }
}

/// 下書きを消す前の確かめと、読めない写真のある下書きを開こうとしたときの問い。一覧とマイページの枠で同じもの
/// （2026-10-30 判断 #408: 一覧の中から外に出した）
struct DraftDialogs: ViewModifier {
    @Binding var confirmDelete: [String]?
    @Binding var missingTarget: DraftLibrary.Entry?
    let onOpen: (DraftLibrary.Entry) -> Void
    let onDelete: ([String]) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(DraftsText.deleteConfirmTitle(confirmDelete?.count ?? 0),
                                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button(DraftsText.delete, role: .destructive) {
                    if let ids = confirmDelete { onDelete(ids) }
                    confirmDelete = nil
                }
                Button(Labels.Common.cancel, role: .cancel) { confirmDelete = nil }
            } message: {
                Text(DraftsText.deleteConfirmMessage)
            }
            .confirmationDialog(DraftsText.missingTitle(missingTarget?.missingCount ?? 0),
                                isPresented: Binding(get: { missingTarget != nil }, set: { if !$0 { missingTarget = nil } }),
                                titleVisibility: .visible) {
                if let target = missingTarget {
                    if target.readableCount > 0 {
                        Button(DraftsText.continueWithRest(target.readableCount)) {
                            missingTarget = nil
                            onOpen(target)
                        }
                    }
                    Button(DraftsText.deleteThisDraft, role: .destructive) {
                        missingTarget = nil
                        confirmDelete = [target.id]
                    }
                }
                Button(Labels.Common.cancel, role: .cancel) { missingTarget = nil }
            } message: {
                if let target = missingTarget {
                    Text(DraftsText.missingMessage(total: target.photoCount, missing: target.missingCount))
                }
            }
    }
}

extension View {
    func draftDialogs(confirmDelete: Binding<[String]?>, missingTarget: Binding<DraftLibrary.Entry?>,
                      onOpen: @escaping (DraftLibrary.Entry) -> Void,
                      onDelete: @escaping ([String]) -> Void) -> some View {
        modifier(DraftDialogs(confirmDelete: confirmDelete, missingTarget: missingTarget, onOpen: onOpen, onDelete: onDelete))
    }
}

/// 下書きを開く前の分かれ道（読めない写真があれば問いを出す・一覧の `open` とマイページの枠で同じ）
enum DraftOpenRoute: Equatable {
    case open
    case askMissing

    static func route(_ entry: DraftLibrary.Entry) -> DraftOpenRoute {
        entry.missingCount > 0 ? .askMissing : .open
    }
}

/// マイページの「下書き」の枠の長押しのメニューに並べるもの（2026-10-30 判断 #408）。
///
/// - 先頭（最新）は一覧と同じ並び（`DraftLibrary.entries`: 自動の書きかけが先頭・あとは保存の新しい順）の1件目。
///   浮く絵と「続きから編集」「この下書きを削除」はこれに効く
/// - 2件以上なら「最近の下書き」に最大5件（最新も含む——一覧の上から5件と同じ並びにして迷わせない）
struct DraftsTileMenu: Equatable {
    static let recentLimit = 5

    let entries: [DraftLibrary.Entry]

    var latest: DraftLibrary.Entry? { entries.first }

    var recents: [DraftLibrary.Entry] {
        entries.count >= 2 ? Array(entries.prefix(Self.recentLimit)) : []
    }
}
