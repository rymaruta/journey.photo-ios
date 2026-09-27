import Foundation

/// 読み込んだコメントの一覧に、この画面で書いた・消した分を重ねる。
///
/// 読み込みと投稿・削除は同時に走る（開いた直後の読み込みが遅いうちに
/// 書ける）。後から届いた一覧をそのまま採ると、書いたばかりのコメントが
/// 消え、消したコメントが戻っていた。**捨てもしない**——捨てると、既に
/// ある他の人のコメントが開き直すまで出なかった。
enum CommentMerge {

    static func merge(loaded: [PhotoComment], count: Int?,
                      posted: [PhotoComment], deleted: Set<String>) -> (items: [PhotoComment], count: Int?) {
        let loadedIds = Set(loaded.map(\.id))
        // 一覧に載っていない、書いたばかりの分（新しいものが先頭）
        let missing = posted.reversed().filter { !loadedIds.contains($0.id) && !deleted.contains($0.id) }
        // 一覧に残っている、消したはずの分
        let stale = loaded.filter { deleted.contains($0.id) }.count
        let items = missing + loaded.filter { !deleted.contains($0.id) }
        return (items, count.map { max(0, $0 + missing.count - stale) })
    }
}
