import Foundation

/// ストーリー閲覧の決まりごと。**Web の `StoryViewer.tsx` と同じ約束。**
///
/// 画面（`StoryViewerView`）はここの答えを描くだけにして、
/// 決まりは Linux の `swift test` で縛る。
///
/// 守っているのは「**動いていないものを動いているふりで描かない**」:
///
/// - 写真は投稿者が選んだ秒数（`durationSec`・3〜15）で実際に送り、
///   その経過だけをバーに塗る
/// - 動画は経過の出どころ（`CMTime`）を模型に足していないので**塗らない**。
///   区切りで「何枚目か」だけ分かるようにする
enum StoryPlayback {

    // MARK: - 表示秒数

    /// 写真1枚の表示秒数。**Web の `storyDurationMs` と同じ丸め**
    /// （無ければ 5・3〜15 に収める）。サーバーも同じ範囲に丸めて保存する
    /// （`stories.ts`）が、古い行や手で書かれた値が来ても画面で壊れないように
    /// こちらでももう一度収める。
    static func duration(seconds: Int?) -> TimeInterval {
        guard let seconds else { return TimeInterval(StoryService.defaultDurationSec) }
        let range = StoryService.durationRange
        return TimeInterval(min(range.upperBound, max(range.lowerBound, seconds)))
    }

    // MARK: - 進行バー

    /// 区切りごとの塗り（0〜1）。**`nil` は「今ここだが経過は描けない」**
    /// ——動画の区切りがこれ。前は満・後は空。
    static func segmentFills(count: Int, current: Int, elapsed: TimeInterval,
                             duration: TimeInterval, isVideo: Bool) -> [Double?] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            if index < current { return 1.0 }
            if index > current { return 0.0 }
            if isVideo { return nil }
            guard duration > 0 else { return 0.0 }
            return min(1.0, max(0.0, elapsed / duration))
        }
    }

    // MARK: - 時間を進める

    enum Tick: Equatable {
        /// まだ表示中
        case running
        /// 表示時間を使い切った。次へ
        case advance
    }

    /// 写真1枚の経過。**凍っている間は1ミリも進まない。**
    struct Progress: Equatable {
        var elapsed: TimeInterval = 0
        let duration: TimeInterval

        mutating func tick(_ dt: TimeInterval, frozen: Bool) -> Tick {
            guard !frozen else { return .running }
            elapsed = min(duration, elapsed + dt)
            return elapsed >= duration ? .advance : .running
        }
    }

    /// 自動送りを止める条件。**どれか1つでも立てば止まる。**
    ///
    /// `isSending` を外さない——Web が実際に踏んだ穴で、送信中に次へ送られて
    /// 「送りました」が別のストーリーの画面に出た。`mediaReady` は
    /// 「絵が出る前から秒数が減る」を防ぐ（回線が遅いと表示時間が短くなる）。
    static func isFrozen(pressing: Bool, paused: Bool, menuOpen: Bool, sheetOpen: Bool,
                         replyFocused: Bool, isSending: Bool, mediaReady: Bool) -> Bool {
        pressing || paused || menuOpen || sheetOpen || replyFocused || isSending || !mediaReady
    }

    // MARK: - 前後

    /// 次の位置。**最後なら `nil`＝閉じる**（最初に戻して回し続けない）。
    static func next(after index: Int, count: Int) -> Int? {
        let candidate = index + 1
        return candidate < count ? candidate : nil
    }

    enum LeftTap: Equatable {
        /// 同じ1枚を最初から
        case restart
        /// 1つ前へ
        case previous(Int)
    }

    /// 始まってすぐの左タップだけ前へ戻る。**Web と同じ 0.8 秒の線。**
    /// それを過ぎていたら「今のを最初から」——見返したい方が多い。
    static let restartThreshold: TimeInterval = 0.8

    static func leftTap(index: Int, elapsed: TimeInterval) -> LeftTap {
        if elapsed > restartThreshold || index == 0 { return .restart }
        return .previous(index - 1)
    }

    // MARK: - スワイプ

    /// スワイプで何をするか。
    ///
    /// **左右タップと同じ行き先に寄せる**（`leftTap` / `next`）——同じ
    /// 画面に「押すと進む」と「払うと別の動き」が並ぶと、どちらが本当かを
    /// 人が覚えられない。
    enum Swipe: Equatable {
        /// 次の1本へ（無ければ閉じる）
        case next
        /// 前の1本へ／今のを最初から（`leftTap` と同じ判断）
        case back
        /// 閉じる
        case close
        /// 何もしない（短すぎる・斜め）
        case ignore
    }

    /// これ未満は払ったと見なさない（指の揺れ）。
    /// Apple の標準的な線（44pt＝押せるものの最小）に合わせる
    static let swipeThreshold: CGFloat = 44

    /// **縦横で迷ったら何もしない。** 斜めの払いを「次へ」と読むと、
    /// 閉じようとして進んでしまう——戻る手が無い操作ほど慎重に倒す。
    /// 縦横の差がこの倍率に満たなければ捨てる
    static let swipeDominance: CGFloat = 1.5

    /// - Parameters:
    ///   - dx: 横の移動（右が正）
    ///   - dy: 縦の移動（下が正）
    static func swipe(dx: CGFloat, dy: CGFloat) -> Swipe {
        let ax = abs(dx), ay = abs(dy)
        // **上への払いは何もしない。** モックには無いし、他のアプリでは
        // 「詳細を開く」に割り当てられていることが多い——同じ動きで
        // 違うことが起きる方が悪い
        if ay > ax * swipeDominance {
            return dy >= swipeThreshold ? .close : .ignore
        }
        if ax > ay * swipeDominance, ax >= swipeThreshold {
            // **払った向きと進む向きを合わせる。** 左へ払う＝次（紙をめくる向き）
            return dx < 0 ? .next : .back
        }
        return .ignore
    }

    // MARK: - 兄弟

    /// 押した1本と同じ投稿者のストーリーを、古い順に並べる。
    ///
    /// **この端末が持つ一覧の中だけ**（サーバーの最新とは限らない）。
    /// `userId` が無い行は兄弟を探しようがないので、その1本だけ。
    static func siblings(of story: Story, in stories: [Story]) -> (stories: [Story], index: Int) {
        guard let userId = story.userId, !userId.isEmpty else { return ([story], 0) }
        let same = stories
            .filter { $0.userId == userId }
            .sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        guard let index = same.firstIndex(where: { $0.id == story.id }) else { return ([story], 0) }
        return (same, index)
    }

    /// 横並びの輪。**1人＝1つ。**
    ///
    /// 1本＝1つにしていた頃は、2本出した人が輪2つで並び、owner の目には
    /// 「わたしが2人いる」と映った（2026-09-25）。押すと同じ束が開くので、
    /// 輪を分けても見られるものは増えない。
    ///
    /// - 並びは一覧で最初に出てきた順（サーバーの並びを崩さない）
    /// - 輪に出す1本は**まだ見ていない中で一番古いもの**、全部見ていれば
    ///   一番古いもの。押すとそこから始まる（見たものを見直させない）
    /// - `userId` の無い行は束ねようがないので、1本ずつ
    static func rings(_ stories: [Story], isSeen: (String) -> Bool) -> [Story] {
        var order: [String] = []
        var groups: [String: [Story]] = [:]
        var loose: [String: Story] = [:]
        for story in stories {
            if let userId = story.userId, !userId.isEmpty {
                let key = "u:" + userId
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(story)
            } else {
                let key = "s:" + story.id
                if loose[key] == nil { order.append(key) }
                loose[key] = story
            }
        }
        return order.compactMap { key in
            if let single = loose[key] { return single }
            guard let group = groups[key] else { return nil }
            let oldestFirst = group.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
            return oldestFirst.first { !isSeen($0.id) } ?? oldestFirst.first
        }
    }

    /// 端末側で落とす。
    ///
    /// サーバーの一覧はブロックを両向きに落として返すが、**通報した1本は
    /// 落とさない**（読むのは人で、すぐには終わらない）。通報した人の画面に
    /// 出続けるなら押した意味がないので、写真の一覧と同じく端末で消す。
    /// ブロックも、サーバーの一覧を読み直すまでの間はここで消す
    static func visible(_ stories: [Story], blockedUserIds: Set<String>,
                        reportedPhotoIds: Set<String>) -> [Story] {
        stories.filter { story in
            if reportedPhotoIds.contains(story.id) { return false }
            if let userId = story.userId, blockedUserIds.contains(userId) { return false }
            return true
        }
    }

    // MARK: - 「…」のメニュー

    enum MenuItem: Equatable, CaseIterable {
        case pause
        case mute
        case hideCaption
        case block
        case report
    }

    /// 出す項目。**押しても何も起きない項目は出さない。**
    ///
    /// - ミュートは動画だけ（写真のストーリーは音を鳴らしていない。
    ///   `Story.song` を復号しておらず BGM も無い）
    /// - 「テキストを非表示」はサーバーの `caption` があるときだけ。
    ///   写真に焼き込んだ文字は消せない
    /// - ブロック・通報は他人の投稿だけ（自分は通報できない。サーバーも 400）。
    ///   ブロックは相手が分かるときだけ
    static func menuItems(isMine: Bool, isVideo: Bool, hasCaption: Bool, hasOwner: Bool) -> [MenuItem] {
        var items: [MenuItem] = [.pause]
        if isVideo { items.append(.mute) }
        if hasCaption { items.append(.hideCaption) }
        if !isMine {
            if hasOwner { items.append(.block) }
            items.append(.report)
        }
        return items
    }

    // MARK: - 時刻

    /// 「2時間前」。**サーバーの時刻が読めなければ何も出さない**
    /// （「0分前」と書くより、書かない方が正しい）。未来も出さない。
    static func ago(from iso: String?, now: Date = Date()) -> String? {
        guard let iso, let date = parse(iso) else { return nil }
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 0 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return L("たった今", "just now") }
        if minutes < 60 { return L("\(minutes)分前", "\(minutes)m ago") }
        let hours = minutes / 60
        if hours < 24 { return L("\(hours)時間前", "\(hours)h ago") }
        return L("\(hours / 24)日前", "\(hours / 24)d ago")
    }

    /// サーバーは `toISOString()`（小数秒つき）だが、小数秒の無い ISO8601 も
    /// 読めるようにしておく——片方だけだと**時刻が丸ごと消える**
    private static func parse(_ iso: String) -> Date? {
        fractional.date(from: iso) ?? plain.date(from: iso)
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
