import SwiftUI

/// カードの「…」（通報・この人をブロック・帳から外す）。**審査 1.2**（2026-10-16 の読み直し）: 届いたカードは
/// 他人が載せたものなので、ほかの写真と同じく通報・ブロックできる口を置く。束の画面（表・裏とも見える上の段）と
/// 帳の綴じの1枚が使う。確認・シートは呼ぶ側が持つ
struct PassCardMenu: View {

    let content: PassCardContent
    /// 写真を通報する（写真の持ち主への通報）
    let report: () -> Void
    /// ひとことを通報する（署名が無いので、写真の通報とは分ける・`ReportSheet.passNote`）
    let reportNote: () -> Void
    /// ひとことを伏せる／出す（この端末だけ）
    let toggleNote: () -> Void
    /// 区間の字（発・着）を伏せる／出す（伏せたら自動の形に戻る・2026-10-16）
    let toggleLabels: () -> Void
    let block: () -> Void
    let remove: () -> Void
    /// 写真の上に置く（帳の綴じ）ならガラスの丸に白。黒地の上（束の上の段）なら素の白
    var onPhoto = false

    var body: some View {
        Menu {
            Button(action: report) {
                Label(L("写真を通報する", "Report photo"), systemImage: "flag")
            }
            if content.card.hasWrittenText {
                // ひとこと・発・着（相手の端末から届いた、署名の無い字）を1つの通報で
                Button(action: reportNote) {
                    Label(L("書かれた字を通報する", "Report the text"), systemImage: "text.bubble")
                }
            }
            // 連絡先の形で出さない字は、出す口も置かない（`PassEncounter.shownNote`）
            if !content.card.labelsHaveContact,
               !(content.card.originLabel ?? "").isEmpty || !(content.card.destinationLabel ?? "").isEmpty {
                Button(action: toggleLabels) {
                    content.card.labelsHidden == true
                        ? Label(L("区間の字を出す", "Show route text"), systemImage: "eye")
                        : Label(L("区間の字を伏せる", "Hide route text"), systemImage: "eye.slash")
                }
            }
            if !content.card.note.isEmpty, !content.card.noteHasContact {
                Button(action: toggleNote) {
                    content.card.noteHidden == true
                        ? Label(L("ひとことを出す", "Show note"), systemImage: "eye")
                        : Label(L("ひとことを伏せる", "Hide note"), systemImage: "eye.slash")
                }
            }
            if content.card.ownerId != nil {
                Button(role: .destructive, action: block) {
                    Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                }
            }
            Button(action: remove) {
                Label(L("帳から外す", "Remove from the book"), systemImage: "minus.circle")
            }
        } label: {
            Group {
                if onPhoto {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .background(.ultraThinMaterial, in: Circle())
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(WebTheme.foreground)
                }
            }
            .webTappable()
        }
        .accessibilityLabel(L("このカードの操作", "Card actions"))
        .accessibilityIdentifier("pass.card.menu")
    }
}

/// カードのブロック（束の画面と帳が同じ手順を使う）
@MainActor
enum PassCardModeration {
    /// ブロックする（確認の後）。**サーバーに送り、公開一覧から落とす**——帳からもその人のカードが消える
    static func block(_ content: PassCardContent, hidden: ModerationStore, environment: AppEnvironment,
                      toasts: ToastCenter) async -> Bool {
        guard let owner = content.card.ownerId else { return false }
        do {
            try await hidden.blockAndHide(owner, environment: environment)
            toasts.show(L("ブロックしました", "Blocked"))
            return true
        } catch {
            toasts.show((error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block"),
                        kind: .failure)
            return false
        }
    }
}
