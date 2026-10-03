import Foundation

/// 写真の編集の**元**（選んだときの原本）を置く一時ファイル。
///
/// 投稿画面は整えた 1920px の JPEG（`ImagePreparer.Prepared`）しか持たず、原本は捨てていた。
/// 編集は**非破壊**（毎回元から描く）なので、元を残す。**メモリには持たない**——
/// 原本は HEIC で 1 枚 2〜10MB、10 枚選ぶと数十 MB を画面が抱えることになる。
/// 一時フォルダの中の自分のフォルダに置き、写真を外した・投稿した・画面を閉じたら消す。
///
/// - 書けなければ nil（編集は整えた本体を元にする。投稿は止めない）
/// - アプリが落ちて消し損ねた分は OS が一時フォルダごと片付ける。
///   2026-10-02 判断: 起動時に掃除はしない（投稿画面が2つ開く経路があると、使っている元まで消す）
/// - **MainActor に縛らない箱**（画面のモデルが消えるとき＝`deinit` にも片付けるため）。
///   触るのは MainActor の上と、書くときの画面の処理の外（`write` は static）
final class PhotoEditSources: @unchecked Sendable {

    /// 置き場（一時フォルダの中）
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("photo-edit-sources", isDirectory: true)
    }

    /// 原本を一時ファイルに書く。**画面の処理の外で呼ぶ**（数 MB を書く）。書けなければ nil
    static func write(_ data: Data) -> URL? {
        let folder = directory
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(UUID().uuidString)
            // 他のアプリからは見えない場所だが、端末のロック中は読めなくしておく（撮影地入りの原本）
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            return url
        } catch {
            return nil
        }
    }

    private var tracked: Set<URL> = []

    init() {}

    /// 持っている元（試験で見る）
    var urls: Set<URL> { tracked }

    /// 今の写真が使っている元だけを残し、ほかを消す（写真を外した・投稿した）
    func keep(only inUse: Set<URL>) {
        let gone = tracked.subtracting(inUse)
        tracked = inUse
        for url in gone { try? FileManager.default.removeItem(at: url) }
    }

    /// 全部消す（画面を閉じた）
    func removeAll() {
        keep(only: [])
    }
}
