import Foundation

/// 取り消された処理から通信を始めない。
///
/// **取り消された処理が URLSession を呼ぶと、URLSession が返すのは `URLError(.cancelled)`**
/// （Linux の Foundation と試験の模型ではそう。iOS で呼ぶ**前**から取り消されていた回に
/// 何を返すかは確かめていない）。呼ぶ前に同じ誤りを投げるので、呼び手の扱いは変わらない
/// ——`APIClient` は取り消しとして、公開一覧・索引は誤りの型を見ない catch で。
/// アップロードの PUT（`UploadService.put`）・今日の一問（`DailyQuizService.fetch`）・編集の元
/// （`PhotoRecolor.fetchSource`）は、**呼んだ処理が取り消されているとき**（`Task.isCancelled`）に
/// `CancellationError` で返す。PUT と一問は、`CancellationError` そのものが届いた回も同じ
/// （2026-10-30 判断・#378/#381。取り消しを「通信できません」と言わない）。
/// iOS が `CancellationError` を返していた場合も、変わるのは `APIClient` が「通信できません」
/// ではなく取り消しとして返すようになることだけ（取り消しを失敗の文にしない、の狙いどおり）。
/// 変わるのは、捨てられると分かっている要求を出さないこと。
///
/// **最後まで通すべき通信**（投稿の PUT・いいねのいまの数・ストーリーの送信）は、どれも
/// 取り消されない切り離した `Task` の上で走るので、ここでは止まらない。
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
