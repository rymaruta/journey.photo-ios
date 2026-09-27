import Foundation

/// 取り消された処理から通信を始めない。
///
/// **取り消された処理が URLSession を呼ぶと、URLSession が返すのは `URLError(.cancelled)`。**
/// それなら呼ぶ前に同じ誤りを投げても、呼び手の扱い（`APIClient` は取り消しとして、
/// 公開一覧・索引は圏外と同じ控えの経路で）は変わらない。変わるのは、捨てられると
/// 分かっている要求を出さないことだけ。
///
/// 🔴 **Linux の試験がこれで落ちなくなる。** swift-corelibs-foundation の URLSession は、
/// 取り消された処理から呼ぶと、要求の途中でも・呼ぶ前に取り消されていても、中の競合で
/// まれに落ちる（`TaskRegistry` の Fatal error。500回の取り消しを40回流して、途中の
/// 取り消しで24回・呼ぶ前の取り消しで31回、呼ばない形で0回）。本物の iOS で
/// `URLError(.cancelled)` が返ることは、試験の模型に合わせた前提で、実機では確かめていない
enum RequestCancellation {
    /// 通信の `do` の中で、URLSession を呼ぶ直前に呼ぶ（その `catch` が同じく受けるように）
    static func throwIfCancelled() throws {
        if Task.isCancelled { throw URLError(.cancelled) }
    }
}
