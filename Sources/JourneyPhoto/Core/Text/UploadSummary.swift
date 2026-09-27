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
            let head = done == 0
                ? L("やめました", "Stopped")
                : L("やめました（\(done) 枚は投稿しました）", "Stopped (\(done) posted)")
            return head + songNote(songFailures)
        }
        let head = done == 0
            ? L("投稿できませんでした", "Couldn't post")
            : L("\(done) 枚は投稿しました。残りは投稿できていません", "\(done) posted; the rest didn't go through")
        guard let reason = failures.first else { return head + songNote(songFailures) }
        return "\(head)（\(reason)）" + songNote(songFailures)
    }

    /// 撮った写真が並んだあとの一言。**今の状態から言い直す。**
    ///
    /// - 読めなかったライブラリの写真が選ばれたままなら、その枚数を言う。言わないと、
    ///   その写真が抜けたまま投稿できる（写真を外しても読み直さない）
    /// - 前の送信で曲を付けられなかったなら、それも言う。その写真はもう並びに居ない
    ///   ので、消すと二度と伝わらない
    /// - 「残りは投稿できていません」は引き継がない（残りは並びを見れば分かり、
    ///   外して諦めたあとも出続ける）
    static func afterCapture(unreadable: Int, songFailures: Int) -> String? {
        var parts: [String] = []
        if unreadable > 0 {
            parts.append(L("\(unreadable) 枚は読み込めませんでした", "\(unreadable) photo(s) couldn't be loaded"))
        }
        if songFailures > 0 {
            parts.append(L("前に投稿した写真に曲を付けられませんでした", "The song couldn't be attached to the photos posted earlier"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: L("。", ". "))
    }

    /// **曲のことは、どの結末でも言う。** 先頭の分岐でしか見ていなかった頃は、
    /// 途中でやめた回・他の写真が失敗した回に、曲が付かなかったことが
    /// 一度も伝わらなかった。
    private static func songNote(_ songFailures: Int) -> String {
        guard songFailures > 0 else { return "" }
        return L("　曲は付けられませんでした。", " The song couldn't be attached.")
    }
}
