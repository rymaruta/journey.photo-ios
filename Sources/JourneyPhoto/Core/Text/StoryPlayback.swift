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

    /// 写真1枚の時計。**「いつから動いているか」だけを持ち、経過はその場で計算する。**
    ///
    /// 以前は 50ms ごとに `elapsed` を書き換え、刻みの間を同じ長さの線のアニメーションで
    /// つないでいた。`Task.sleep` は遅れて起きることがあり、遅れるとアニメーションが先に
    /// 終わって**バーが一瞬止まってから動く**（owner「もっと進捗バー滑らかにしたい」
    /// 2026-09-29）。さらに書き換えのたびに閲覧画面の全体を1秒に20回描き直していた。
    /// いまは状態が変わるのは**動く／止まるが切り替わったときだけ**で、バーは画面の
    /// 描画（`TimelineView(.animation)`）ごとに `elapsed(at:)` を読んで伸びる
    /// （Web の `StoryViewer` が CSS アニメーション・requestAnimationFrame で解いたのと同じ考え方）
    struct Clock: Equatable {
        /// 止まっていた間までに貯まった経過
        private(set) var base: TimeInterval = 0
        /// 動き出した時刻。止まっていれば nil
        private(set) var runningSince: Date?

        var isRunning: Bool { runningSince != nil }

        /// `now` の時点の経過。`now` が動き出しより前なら動き出しの時点の値（負にしない）
        func elapsed(at now: Date) -> TimeInterval {
            base + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
        }

        /// 動かす／止める。**同じ向きの2回目は何もしない**（止めた時刻・動き出した時刻を
        /// 書き直さない）。変わったら true（呼ぶ側はそのときだけ `@State` を書く）
        @discardableResult
        mutating func set(running: Bool, at now: Date) -> Bool {
            switch (running, runningSince) {
            case (true, nil):
                runningSince = now
                return true
            case (false, let since?):
                base += max(0, now.timeIntervalSince(since))
                runningSince = nil
                return true
            default:
                return false
            }
        }

        /// 動いている間の `seconds` を**無かったことにする**（`StoryPlayback.stalledSeconds`）。
        /// 止まっていれば何もしない。
        ///
        /// 🔴 **捨てるのは動いていた長さまで**（動き出しを `now` より先へずらさない）。
        /// 背面から戻る合図で先に動き出し、そのあと背面の前から眠っていた見回りが
        /// 1時間の間で起きると、1時間ぶんを捨てて**戻った後もバーが1時間止まった**
        /// （a46fed7 のレビュー）
        mutating func discard(_ seconds: TimeInterval, at now: Date) {
            guard seconds > 0, let since = runningSince else { return }
            runningSince = min(since.addingTimeInterval(seconds), now)
        }

        /// 最初から（同じ1本を頭から・別の1本へ移った）
        mutating func restart(running: Bool, at now: Date) {
            base = 0
            runningSince = running ? now : nil
        }
    }

    /// 自動送りを止める条件。**どれか1つでも立てば止まる。**
    ///
    /// `isSending` を外さない——Web が実際に踏んだ穴で、送信中に次へ送られて
    /// 「送りました」が別のストーリーの画面に出た。`mediaReady` は
    /// 「絵が出る前から秒数が減る」を防ぐ（回線が遅いと表示時間が短くなる）。
    ///
    /// `inBackground` は**アプリが前面に居ない間**（ホームへ戻った・電話・
    /// 通知センター）。見ていない時間で秒数を減らさない
    /// 動画が終わった（読めずに諦めた回も）と知らされたときにどうするか。
    enum MediaEnd: Equatable {
        /// 別の1本の知らせ（古い1本・同じ1本の2回目）。捨てる
        case ignore
        /// 止めている間（ブロックの確認・通報・返信を打っている…）。解けるまで待つ
        case hold
        case advance
    }

    /// 🔴 **止めている間は進めない・見ている1本の知らせだけ採る。** 読めない動画の
    /// 失敗は止めていても届くので、ブロックの確認を出している間に次の1本へ移り、
    /// 確認の「ブロック」が**次の投稿者**に効いていた（通報・返信の書きかけも同じ）。
    /// 失敗の通知と状態の見張りの両方が来ると、1本飛ばしてもいた
    static func mediaEnded(storyId: String, currentId: String?, frozen: Bool) -> MediaEnd {
        guard storyId == currentId else { return .ignore }
        return frozen ? .hold : .advance
    }

    static func isFrozen(pressing: Bool, paused: Bool, menuOpen: Bool, sheetOpen: Bool,
                         replyFocused: Bool, isSending: Bool, mediaReady: Bool,
                         inBackground: Bool = false) -> Bool {
        pressing || paused || menuOpen || sheetOpen || replyFocused || isSending || !mediaReady
            || inBackground
    }

    /// 時計の見回りの間で、**数えてよい長さの上限**。
    ///
    /// 経過は時刻から計算するので、**アプリが止まっていた時間もそのまま入る**
    /// ——ホームへ戻って帰ってくると、その瞬間に表示時間を使い切って次の1本へ
    /// 飛んでいた（2026-09-26 のバグ探し）。止まる条件（`inBackground`）で防ぐが、
    /// 前面に戻る合図より先に見回りが走ることもあるので、ここでも抑える
    /// （超えた分は `stalledSeconds` → `Clock.discard` で捨てる）。
    /// 捨てた直後は、バーが捨てた分だけ一瞬戻って見えることがある
    static let maxTickSeconds: TimeInterval = 0.25

    /// 見回りの間があいた分のうち、**数えない分**。`maxTickSeconds` を超えた分は
    /// アプリが止まっていた（背面・メインの詰まり）とみなして捨てる
    static func stalledSeconds(gap: TimeInterval) -> TimeInterval {
        max(0, gap - maxTickSeconds)
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
        /// 前の人へ（束の先頭で、前の人がいるとき。`StoryReel`）
        case previousGroup
    }

    /// 始まってすぐの左タップだけ前へ戻る。**Web と同じ 0.8 秒の線。**
    /// それを過ぎていたら「今のを最初から」——見返したい方が多い。
    static let restartThreshold: TimeInterval = 0.8

    /// - Parameter hasPreviousGroup: 前の人がいる（人から人への並びの中で、最初の人でない）。
    ///   束の先頭で始まってすぐなら前の人へ戻る（Instagram と同じ）
    static func leftTap(index: Int, elapsed: TimeInterval, hasPreviousGroup: Bool = false) -> LeftTap {
        if elapsed > restartThreshold { return .restart }
        if index == 0 { return hasPreviousGroup ? .previousGroup : .restart }
        return .previous(index - 1)
    }

    /// 左タップの判断（`leftTap`）に渡す経過。**動画と読み込み中の写真は、見せ始めてからの
    /// 実時間**（Web の `goPrev` と同じ）。時計（`Clock`）は写真が出てからしか回らないので、
    /// 動画ではいつも0になり、左を押すと頭から流れずに前の1本・前の人へ飛んでいた。
    /// 出ている写真は今までどおり時計（止めていた間は数えない）
    static func leftTapElapsed(clock: TimeInterval, sinceShown: TimeInterval,
                               isVideo: Bool, mediaReady: Bool) -> TimeInterval {
        isVideo || !mediaReady ? sinceShown : clock
    }

    /// 頭から見直したときの終わりの控え（`pendingEnd`）と受け取った印（`endedIds`）。
    ///
    /// **控えは捨て、いまの1本の印も外す。** 知らせが出ている間に動画が終わると控えに入る。
    /// そのまま見直すと、知らせが消えたときに控えが効き、見直している途中の動画が次へ
    /// 飛ばされた。印を外すのは、見直した回の終わりをもう一度受けるため。
    /// **読めなかった動画**はもう終わりを知らせてこないので、見直しの合図を受けた側が
    /// 知らせ直す（`restartAction`）——控えを捨てても止まったままにならない
    static func afterRestart(pendingEnd: String?, endedIds: Set<String>,
                             currentId: String?) -> (pendingEnd: String?, endedIds: Set<String>) {
        var ended = endedIds
        if let currentId { ended.remove(currentId) }
        return (nil, ended)
    }

    enum RestartAction: Equatable {
        /// 0 へ戻して鳴らし直す
        case seekToStart
        /// 読めなかった動画。**終わりをもう一度知らせる**（見直しで控えが捨てられたので、
        /// 知らせないと黒い画面のまま進まない）
        case reportEnd
    }

    /// 動画が見直しの合図（`restartToken`）を受けたときにすること
    static func restartAction(mediaFailed: Bool) -> RestartAction {
        mediaFailed ? .reportEnd : .seekToStart
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

    /// ホームの輪の並び（板 27「いつもの並び」）。**自分は先頭に別に取り出し、
    /// 残りは未読 → 既読の順**。未読どうし・既読どうしはサーバーの並びのまま
    /// （同じ順を保つ——開くたびに輪が入れ替わると覚えられない）
    static func orderedRings(_ rings: [Story], me: String?,
                             isUnseen: (Story) -> Bool) -> (mine: Story?, others: [Story]) {
        let mine = me.flatMap { id in rings.first { $0.userId == id } }
        let others = rings.filter { me == nil || $0.userId != me }
        let unseen = others.filter(isUnseen)
        let seen = others.filter { !isUnseen($0) }
        return (mine, unseen + seen)
    }

    /// 輪を本数で区切るときの1区切り（0...1 の始まりと終わり）。
    /// **1本なら切れ目の無い輪**。切れ目は円周のうち `gap` の割合
    static func ringSegments(count: Int, gap: Double = 4.0 / 182.2) -> [(start: Double, end: Double)] {
        guard count > 1 else { return [(0, 1)] }
        // **型を言い切って1式ずつ書く。** 名前付きの組を返す式を1行で書くと、
        // Xcode の型検査が時間切れで止まる（TestFlight run #113）
        let step: Double = 1.0 / Double(count)
        let half: Double = gap / 2
        var segments: [(start: Double, end: Double)] = []
        segments.reserveCapacity(count)
        for i in 0..<count {
            let start: Double = Double(i) * step + half
            let end: Double = Double(i + 1) * step - half
            segments.append((start: start, end: end))
        }
        return segments
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
        /// 自分の投稿を写真として残す（足元の「…」から・2026-09-29）
        case keep
        /// 自分の投稿を消す（確かめてから）
        case delete
    }

    /// 出す項目。**押しても何も起きない項目は出さない。**
    ///
    /// - ミュートは音が出るときだけ＝動画か、曲が付いているとき
    ///   （Web の `hasAudio = isVideo || !!item.song`）
    /// - 「テキストを非表示」はサーバーの `caption` があるときだけ。
    ///   写真に焼き込んだ文字は消せない
    /// - ブロック・通報は他人の投稿だけ（自分は通報できない。サーバーも 400）。
    ///   ブロックは相手が分かるときだけ
    /// - 写真として残す・削除は自分の投稿だけ（足元を1行にしたので「…」にしまう）。
    ///   残すのは `canKeep`（動画・自分用の投稿はサーバーが断る）のときだけ。
    ///   **ハイライトの中では出さない**（以前もハイライトには無かった操作）
    static func menuItems(isMine: Bool, isVideo: Bool, hasSong: Bool = false,
                          hasCaption: Bool, hasOwner: Bool, canKeep: Bool = false,
                          inHighlight: Bool = false) -> [MenuItem] {
        var items: [MenuItem] = [.pause]
        if isVideo || hasSong { items.append(.mute) }
        if hasCaption { items.append(.hideCaption) }
        if isMine {
            if !inHighlight {
                if canKeep { items.append(.keep) }
                items.append(.delete)
            }
        } else {
            if hasOwner { items.append(.block) }
            items.append(.report)
        }
        return items
    }

    /// 上（見出しの横）に「…」を出すか。人の投稿は必ず（通報とブロックの入口・審査 1.2）。
    /// 自分の投稿は**ハイライトの中で音があるときだけ**（音を消す口がそこにしか無い）。
    /// ハイライト以外の自分の投稿は足元に「…」があるので出さない（上下に2つ並ぶ）
    static func showsTopMenu(isMine: Bool, inHighlight: Bool, hasAudio: Bool) -> Bool {
        !isMine || (inHighlight && hasAudio)
    }

    /// 読み直したあとの一覧。
    ///
    /// - 取れた → それを絞り込む（通報した1本はサーバーが落とさないので端末で消す）
    /// - **取れなかった → 前の一覧を残す**（閉じるたびに読み直すので、圏外で1本
    ///   見て閉じると輪が全部消えていた）。ただし**絞り込みはかけ直す**——
    ///   圏外で通報・ブロックした1本が残らないように
    /// - 取れなかったうえに見ている人が変わった → 空（前の人の輪を見せない）
    /// - Parameter now: **期限（24時間）を過ぎた1本は落とす**——取れなかった回に前の一覧を
    ///   残すと、日をまたいで戻ったとき昨日の輪が並んだままになっていた
    static func afterLoad(fetched: [Story]?, previous: [Story], sameViewer: Bool,
                          blockedUserIds: Set<String>, reportedPhotoIds: Set<String>,
                          now: Date = Date()) -> [Story] {
        guard let base = fetched ?? (sameViewer ? previous : nil) else { return [] }
        // **期限で絞るのは前の一覧を使う回だけ。** 取れた一覧はサーバーが既に
        // `expiresAt > now` で絞っている——端末の時計が進んでいると正しい輪まで消えた
        let live = fetched != nil ? base : base.filter { story in
            guard let iso = story.expiresAt, let expires = parse(iso) else { return true }
            return expires > now
        }
        return visible(live, blockedUserIds: blockedUserIds, reportedPhotoIds: reportedPhotoIds)
    }

    // MARK: - 曲

    /// 曲を鳴らし始める位置（秒）。選ばれていなければ頭から
    static func songStart(for story: Story) -> Double {
        Double(story.song?.startSec ?? 0)
    }

    /// 鳴らす曲。題の無い曲・URL の無い曲は鳴らさない（曲名の行を出さない条件と同じ）。
    ///
    /// 🔴 **音源のホストを確かめる。** ストーリーは開いた瞬間に曲を取りに行くので、
    /// 任意の URL が入った行があると、トレイから開いた全員の IP と時刻がその先へ
    /// 渡る（Web の `safeSongPreviewUrl`・`lib/utils/mediaHosts.ts` と同じ規則）
    static func songURL(for story: Story) -> URL? {
        guard story.songLine != nil, let url = story.song?.previewURL,
              isAllowedPreview(url) else { return nil }
        return url
    }

    /// 試聴の配信元（iTunes Search API が返すホスト）。**完全一致かサブドメインだけ**
    /// ——末尾一致だと `evil-mzstatic.com` が通る
    static let previewHosts = ["itunes.apple.com", "mzstatic.com"]

    static func isAllowedPreview(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return previewHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// 動画の音を消すか。**曲が付いている動画は動画側を常に消す**
    /// （2つ重ねて鳴らさない。Web の `muted={muted || !!item.song}`）
    static func videoMuted(muted: Bool, hasSong: Bool) -> Bool {
        muted || hasSong
    }

    // MARK: - 返信の候補

    /// 返信欄の上に並べる一言（板「25d 返信を書く」）。**押すとそのまま送る**
    /// ——ふつうの返信（`text`）として送るので、サーバーの変更は要らない
    static let quickReplies = ["きれい", "行ってみたい", "どこですか？"]
    static let quickRepliesEnglish = ["Beautiful", "I want to go", "Where is this?"]

    // MARK: - 一時停止の札

    /// 止めている間の画面の出し方。
    ///
    /// - `longHeld`: **0.35秒押し続けた**（指が触れただけでは立てない——
    ///   `onPressingChanged` は触れた瞬間に true になるので、それで隠すと
    ///   ふつうのタップのたびに見出しと足元が点滅した）
    /// - `paused`: メニューの「一時停止」で止めた
    ///
    /// 見出しと足元を隠すのは**長押しの間だけ**（板 25b）。メニューで止めた
    /// ときに隠すと、「…」（再開）と ✕ に手が届かなくなる
    struct Chrome: Equatable {
        let hidesChrome: Bool
        let showsPill: Bool
        /// 札の言い方。長押しなら「指を離すと」
        let pillSaysRelease: Bool
    }

    static func chrome(longHeld: Bool, paused: Bool, overlayOpen: Bool) -> Chrome {
        guard !overlayOpen else {
            return Chrome(hidesChrome: false, showsPill: false, pillSaysRelease: false)
        }
        return Chrome(hidesChrome: longHeld,
                      showsPill: longHeld || paused,
                      // 両方立っているときは、離しても続かないので「押すと」
                      pillSaysRelease: longHeld && !paused)
    }

    /// 止めている間に出す札の文言。**長押しなら「指を離すと」、メニューから
    /// 止めたなら「押すと」**——メニューで止めた人に「指を離すと」と言っても
    /// 離す指が無い
    static func pausedNote(pressing: Bool) -> String {
        pressing
            ? L("一時停止中 — 指を離すと続きから", "Paused — release to continue")
            : L("一時停止中 — 押すと続きから", "Paused — tap to continue")
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

    /// 「あと 22 時間で消えます」（自分のストーリーの見出し・板 25e）。
    /// **1時間を切ったら分で言う**。読めない・過ぎているときは出さない
    static func remaining(until iso: String?, now: Date = Date()) -> String? {
        guard let iso, let date = parse(iso) else { return nil }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return L("あと \(max(1, minutes)) 分で消えます", "Disappears in \(max(1, minutes))m")
        }
        return L("あと \(minutes / 60) 時間で消えます", "Disappears in \(minutes / 60)h")
    }

    /// 投稿した日時（反応の画面の副題「9月24日 18:20に投稿」）。**端末の時刻帯で**
    static func postedAt(_ iso: String?, timeZone: TimeZone = .current) -> String? {
        guard let iso, let date = parse(iso) else { return nil }
        return L("\(format(date, "M月d日 HH:mm", locale: "ja_JP", timeZone))に投稿",
                 "Posted \(format(date, "MMM d, HH:mm", locale: "en_US_POSIX", timeZone))")
    }

    /// ハイライトの左下の日付（「2026.09.12」・等幅で出す）
    static func dotDate(_ iso: String?, timeZone: TimeZone = .current) -> String? {
        guard let iso, let date = parse(iso) else { return nil }
        return format(date, "yyyy.MM.dd", locale: "en_US_POSIX", timeZone)
    }

    /// **書式器は使い回す。** ハイライトの足元は閲覧画面が描き直されるたびに
    /// 呼ばれるので、呼ぶたびに作ると重い
    private static var formatters: [String: DateFormatter] = [:]
    private static let formattersLock = NSLock()

    private static func format(_ date: Date, _ pattern: String, locale: String, _ timeZone: TimeZone) -> String {
        let key = "\(pattern)|\(locale)|\(timeZone.identifier)"
        formattersLock.lock()
        defer { formattersLock.unlock() }
        let f: DateFormatter
        if let cached = formatters[key] {
            f = cached
        } else {
            f = DateFormatter()
            f.locale = Locale(identifier: locale)
            f.timeZone = timeZone
            f.dateFormat = pattern
            formatters[key] = f
        }
        return f.string(from: date)
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

    // MARK: - 反応

    /// 反応を送ったあとの知らせ。**❤️ は今までどおり「いいね」**、ほかは「反応」
    static func reactionSentMessage(_ emoji: String) -> String {
        emoji == StoryService.reactions.first
            ? L("いいねを送りました", "Like sent")
            : L("\(emoji) を送りました", "Sent \(emoji)")
    }

    /// 反応の読み上げの名前（絵文字の読みは端末で違うので、ここで決める）
    static func reactionName(_ emoji: String) -> String {
        switch emoji {
        case "❤️": return L("いいね", "Like")
        case "😍": return L("大好き", "Love it")
        case "😂": return L("笑った", "Haha")
        case "😮": return L("びっくり", "Wow")
        case "😢": return L("悲しい", "Sad")
        case "👏": return L("拍手", "Applause")
        default: return emoji
        }
    }

    /// 反応の並びを閉じるか。**返信欄・メニュー・シート・確認のどれかが開いたら閉じる**
    /// （並びは ♡ の上に出るので、♡ が隠れる・別の画面が上に来たら残す理由が無い）
    static func closesReactionPicker(replyFocused: Bool, menuOpen: Bool, sheetOpen: Bool) -> Bool {
        replyFocused || menuOpen || sheetOpen
    }
}
