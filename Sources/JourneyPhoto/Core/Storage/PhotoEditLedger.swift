import Foundation

/// 自分で編集して保存した写真の、新しい行（写真 id → 編集後の行）。**画面をまたいで共有する。**
///
/// 🔴 **編集の結果は詳細画面の `@State` にしか残っていなかった。** 公開一覧は
/// 建て直しまで古い静的 JSON（`PublicGalleryService`）で、ホーム・探す・地図から
/// 同じ写真を開き直すと、題も説明も撮影地も編集前に戻って見えた（保存はできているので、
/// 「保存されていない」と思って直し直す）。
///
/// - **一覧に重ねる**のは `PublicGalleryService.merged`（ホーム・探す・地図・近くの写真に一度に効く）。
/// - **詳細の1枚**は `PhotoDetailView.shown` がここを引く（古い一覧から開いても新しい姿）。
/// - **捨てる**のは、一覧の行が編集に追いついたとき（`PhotoEditOverlay.caughtUp`）と、
///   ログアウト・退会・人の切り替えのとき（`clear`）。
///
/// 主スレッド（詳細の画面）と公開一覧の actor の両方から読むので、鍵で守る。
/// 端末には書かない（建て直しは通常数分で、起動し直せば一覧が追いついている）
final class PhotoEditLedger: @unchecked Sendable {

    private let lock = NSLock()
    private var overlay = PhotoEditOverlay()
    /// 捨てた回数（`clear`）。**引き直しを始める前に取り（`mark`）、書くときに比べる**
    private var generation = 0

    init() {}

    /// いまの回。引き直しを始める**前**に取って `record(_:since:)` に渡す
    var mark: Int {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    /// 保存した後に引き直した行を控える。
    ///
    /// 🔴 **`since` の後に捨てられていたら書かない。** 引き直しの答えがログアウト・退会
    /// （`clear`）の後に戻ると、前の人の行を書き戻し、次の人の一覧に重ねていた
    func record(_ photo: Photo, since mark: Int) {
        lock.lock(); defer { lock.unlock() }
        guard mark == generation else { return }
        overlay.record(photo)
    }

    /// その行に重ねる編集後の行。**行が追いついていれば nil**
    func edited(over row: Photo) -> Photo? {
        lock.lock(); defer { lock.unlock() }
        return overlay.edited(over: row)
    }

    /// 並びのうち、まだ追いついていない行の編集後の姿（写真 id → 行）
    func pending(in photos: [Photo]) -> [String: Photo] {
        lock.lock(); defer { lock.unlock() }
        return overlay.pending(in: photos)
    }

    /// 一覧に重ねる。**追いついた行の控えは捨てる**（`PublicGalleryService.merged`）
    func apply(to photos: [Photo]) -> [Photo] {
        lock.lock(); defer { lock.unlock() }
        return overlay.apply(to: photos)
    }

    /// ログアウト・退会・人の切り替えで捨てる（次の人に前の人の編集を重ねない）
    func clear() {
        lock.lock(); defer { lock.unlock() }
        overlay = PhotoEditOverlay()
        generation += 1
    }

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return overlay.isEmpty
    }
}

/// `PhotoEditLedger` の中身（画面も鍵も持たない計算だけ）。
struct PhotoEditOverlay: Equatable {

    private(set) var edits: [String: Photo] = [:]

    var isEmpty: Bool { edits.isEmpty }

    mutating func record(_ photo: Photo) {
        edits[photo.id] = photo
    }

    /// その行に重ねる姿。**追いついた行には重ねない**（nil）
    func edited(over row: Photo) -> Photo? {
        guard let edit = edits[row.id], !Self.caughtUp(listed: row, edited: edit) else { return nil }
        return Self.overlaid(listed: row, edited: edit)
    }

    func pending(in photos: [Photo]) -> [String: Photo] {
        var out: [String: Photo] = [:]
        for row in photos {
            if let edit = edited(over: row) { out[row.id] = edit }
        }
        return out
    }

    /// 一覧に重ねる。**一覧の行が追いついていたら、その控えを捨てる**
    /// （以降は一覧の行が本体——Web で後から直した分を、古い控えで上書きしない）
    mutating func apply(to photos: [Photo]) -> [Photo] {
        guard !edits.isEmpty else { return photos }
        return photos.map { row in
            guard let edit = edits[row.id] else { return row }
            if Self.caughtUp(listed: row, edited: edit) {
                edits[row.id] = nil
                return row
            }
            return Self.overlaid(listed: row, edited: edit)
        }
    }

    /// 一覧の行が編集に追いついたか。
    ///
    /// - **両方に更新日時（`updatedAt`）があれば、それで決める。** 編集の保存で
    ///   サーバーが進める（`photoUpdate.ts`）ので、一覧の行がそれ以降なら反映済み
    ///   ——Web で後から直した行（もっと新しい）にも負ける
    /// - 片方でも無ければ**中身の一致**で決める（いいねの数は比べない——別の口で替わる）
    static func caughtUp(listed: Photo, edited: Photo) -> Bool {
        if let listedAt = timestamp(listed.updatedAt), let editedAt = timestamp(edited.updatedAt) {
            return listedAt >= editedAt
        }
        return withoutCounts(listed) == withoutCounts(edited)
    }

    /// 編集後の行に、**一覧の行の表示用の項目を残す**:
    /// - いいねの数（一覧の数はいまの数に差し替え済み・`LiveLikes`）
    /// - 表示名（`displayName`）。静的 JSON は建て直しのたびに投稿者の今の名前で
    ///   焼き直す（`sync-photos-from-ddb.js` の `freshDisplayNames`）が、自分の写真の行
    ///   （`/user/photos`）は投稿したときの名前のまま——重ねると名前が古く戻った
    static func overlaid(listed: Photo, edited: Photo) -> Photo {
        var out = edited
        if listed.likes != nil {
            out.likes = listed.likes
            out.likesAsOf = listed.likesAsOf
        }
        if let name = listed.displayName, !name.isEmpty {
            out.displayName = name
        }
        return out
    }

    /// 中身の一致を見るとき、**編集では変わらない表示用の項目**は比べない
    /// （いいねの数・表示名は別の口・建て直しで替わる）
    private static func withoutCounts(_ photo: Photo) -> Photo {
        var out = photo
        out.likes = nil
        out.likesAsOf = nil
        out.displayName = nil
        return out
    }

    /// ISO8601（小数秒あり・なし）。読めなければ nil
    static func timestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}
