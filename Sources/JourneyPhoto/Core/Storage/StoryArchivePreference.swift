import Foundation

/// ストーリーを作る画面の「24時間後も自分用に残す」（`StoryAudienceSheet`）を端末に覚える。
///
/// **2026-11-11 判断（owner「最初からオンでいい」）:**
/// - **最初の値はオン。** 前は毎回オフから始まり、残したい人は毎回「誰に見せる？」を開いて入れる必要があった
///   （ハイライトに入れられるのは残したものだけ・`api-user/src/highlights.ts`）
/// - **最後に選んだ値を人ごとに覚える。** 一度オフにした人は次もオフで始まる（毎回オンに戻すと、
///   残したくない人が毎回切ることになる）。覚え方は「撮影地の位置を付ける」と同じ（`PerUserFlag`）
/// - 覚えるのは本人が切り替えたときだけ。下書きを開いて戻した値は覚えない（下書きの値はその下書きのもの）
/// - これは「切り替えの初めの値」だけを決める。1本ごとに残すかを送る側で絞る決まりがあれば、そちらが勝つ
///
/// 画面が開くたびに読み、切り替えたときに書くだけなので `ObservableObject` にしない（`UploadLocationPreference` と同じ）
struct StoryArchivePreference {

    /// 覚えが無いときの値（2026-11-11 判断: オン）
    static let defaultValue = true

    static let baseKey = "journey-photo-story-keep-in-archive"

    private let flag: PerUserFlag

    init(defaults: UserDefaults = .standard) {
        flag = PerUserFlag(baseKey: Self.baseKey, defaultValue: Self.defaultValue, defaults: defaults)
    }

    /// 人ごとの鍵。持ち主が分からなければ nil
    static func key(for userId: String?) -> String? {
        PerUserFlag.key(base: baseKey, userId: userId)
    }

    /// その人が選んだ値。覚えが無い・持ち主が分からなければオン
    func keepsInArchive(userId: String?) -> Bool {
        flag.value(userId: userId)
    }

    /// 選んだ値を覚える。持ち主が分からなければ書かない
    func set(_ keeps: Bool, userId: String?) {
        flag.set(keeps, userId: userId)
    }

    /// 退会した人の控えを消す（`AccountLocalData`）
    func removeData(for userId: String) {
        flag.removeData(for: userId)
    }
}
