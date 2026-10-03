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
            // 他のアプリからは見えない場所。守りは「起動後に一度ロックを解くまで読めない」
            // （`fileProtection`）。
            #if os(iOS)
            try data.write(to: url, options: fileProtection)
            #else
            try data.write(to: url, options: .atomic)
            #endif
            return url
        } catch {
            return nil
        }
    }

    /// 一時ファイルを書くときの守り。
    ///
    /// 🔴 **2026-10-03 判断: `.completeFileProtection` ではなく `.completeUntilFirstUserAuthentication`。**
    /// `.complete` はロック中に読めない。投稿を押してすぐ端末をロックする・裏に回すと、送信の途中で
    /// 書き出し（編集の元を読む）が落ちていた。書き出しは今は投稿の最初（前面にいるうち）に全部
    /// 済ませる（`UploadViewModel.exportAllEdited`）ので主な穴は塞いだが、やり直し・共有の絵の作り直しなど
    /// 裏で読みうる道が残るため、二重の守りとして読める側に倒す。
    /// 失うもの: 起動後に一度でも解いた端末をロック中に取られ、中身を抜かれたときに読まれうる
    /// （写真ライブラリの原本と同じ守りの水準。置き場はアプリの一時フォルダで、他のアプリからは見えない）
    static let fileProtection: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

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
