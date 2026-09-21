import Foundation

/// まとめて投稿したときの結果の伝え方。
///
/// **`@MainActor` の型に置かない**（`TagInput` と同じ理由——テストから
/// 呼べなくなる。この轍は3回目なので、最初からこちらに置く）。
enum UploadSummary {

    /// 結果の一言。**何枚上がって、何枚残ったか**を必ず出す。
    ///
    /// - Parameter songFailures: 写真は上がったが**曲を付けられなかった**枚数。
    ///   写真の投稿としては成功なので `failures` には入らない。ここを数えないと
    ///   「全部成功」と見なされて画面が閉じ、**曲が付いていないことが
    ///   本人に一度も伝わらない**（`UploadView` は `didPostAll` で閉じる）。
    static func message(done: Int, failures: [String], cancelled: Bool,
                        songFailures: Int = 0) -> String? {
        if failures.isEmpty && !cancelled {
            guard songFailures > 0 else { return nil }
            return L("\(done) 枚を投稿しましたが、曲を付けられませんでした",
                     "Posted \(done), but the song couldn't be attached")
        }
        if cancelled && failures.isEmpty {
            return done == 0
                ? L("やめました", "Stopped")
                : L("やめました（\(done) 枚は投稿しました）", "Stopped (\(done) posted)")
        }
        let head = done == 0
            ? L("投稿できませんでした", "Couldn't post")
            : L("\(done) 枚は投稿しました。残りは投稿できていません", "\(done) posted; the rest didn't go through")
        guard let reason = failures.first else { return head }
        return "\(head)（\(reason)）"
    }
}
