import SwiftUI
import Combine

/// 行った県マップの画面の状態（札 #503）。記録の判定・保存は Core（`VisitedPrefectures`・
/// `VisitedPrefectureStore`）が持ち、ここは**画面の操作を記録の変更に結ぶ**だけ。
///
/// 2026-11-08 判断（提案書 第2版）:
/// - 回数を増やすのは**本人のタップだけ**。写真の候補（`found`）は数にも色にも入らない
/// - 戻し方: 「ひとつ戻す」（20手）・帯と札の「−」・札の ＋− のあとの「取り消す」（5秒）
///
/// 2026-11-10 判断（札 #510・owner「Aで作って」。案の Artifact: https://claude.ai/artifact/8SCDZoffPx8xW9wZVukher）:
/// - スイッチ「タップで回数を足す」と同じ日の確かめをなくした。**県を押すたびに必ず 1 回足す**
///   （同じ県を同じ日に 2 回押したら 2 回。owner 2026-11-10「2回押したら2回カウントされる」）。
///   記録の形（日付の並び）と読み方は変えていない
/// - 押すと小さな帯（`quickBar`「東京都 3 回 ［−］［＋］［詳しく］」）を 5 秒出す。触っている間は消さない
///   （VoiceOver の間は「取り消す」と同じ 30 秒）。別の県を押したら帯はその県に替わる
/// - 長押し（`peek`）は足さずに帯だけ出す。帯の［−］は［＋］と同じ大きさで、確かめずに 1 回減らす（［＋］で戻せる・
///   owner 2026-11-10「消すときも簡単にしたい」）
/// - 帯がある間は「取り消す」の帯を出さない（同じ下に重なる。帯の［−］が取り消しを兼ねる）。
///   地図・一覧・帯から足し引きした回は「取り消す」を作らない（札の ＋− は今までどおり作る）
/// - 写真の候補の県も、地図で押したら同じく 1 回足す（モックどおり）。「候補から外す」は［詳しく］の札と、
///   地図の下の候補の一覧（押すと札が開く）に残す
/// - 祝い（`celebration`）は周が増えたときに1回だけ。画面を開いた時点ですでにそろっていれば出さない
/// - 保存のたびに端末へ書く。サーバーには送らない
@MainActor
final class VisitedMapModel: ObservableObject {

    /// 写真から県を調べる状態（記録そのものとは別。失敗しても記録は残る）
    enum PhotosState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    struct Toast: Equatable {
        let id: Int
        let message: String
        /// 「取り消す」を添えるか（上限の知らせには添えない）
        var offersUndo = true
    }

    @Published private(set) var record = VisitedPrefectures()
    @Published private(set) var history = VisitedHistory()
    /// 写真から導けた県（候補の元・JIS の順）
    @Published private(set) var found: [String] = []
    @Published private(set) var photosState: PhotosState = .idle
    /// 県ごとの自分の写真（新しい順・県の札の写真の帯・2026-11-12 判断）。画面が読んだ自分の写真から県で分けるだけ
    /// （新しい口なし・候補と同じ当て方 `PrefectureResolver`）
    @Published private(set) var photosByPrefecture: [String: [Photo]] = [:]
    /// 押した県の小さな帯。`timerID` は 5 秒の数え直しの印、`deadline` は消える時刻（触っている間は nil・残りの線が読む）
    struct QuickBar: Equatable {
        let prefecture: String
        var timerID: Int
        var deadline: Date?
        var seconds: Double = VisitedMapModel.quickBarDefaultSeconds
    }

    /// 押した県の小さな帯（案 A）
    @Published private(set) var quickBar: QuickBar?
    /// 帯を指で触っている間（`VisitedQuickBar` が渡す）。触っている間は消さず、離したら 5 秒を数え直す
    @Published private(set) var quickBarHeld = false
    /// 足した合図の通し番号と県（地図の「＋1」）
    @Published private(set) var addPulse = 0
    private(set) var addPulsePrefecture: String?
    @Published private(set) var toast: Toast?
    /// 祝い。画面が閉じるまで出し続け、`dismissCelebration` で消す
    @Published private(set) var celebration: VisitedPrefectures.Celebration?
    /// 札（県）を開いている県
    @Published var selected: String?
    /// 数が変わったあとの読み上げ（`UIAccessibility.post` は画面が行う）
    @Published private(set) var announcement: String?
    /// 触覚の合図（値が変わったら鳴らす）。足す・引く・戻すは軽く、周がそろったときだけ成功
    @Published private(set) var lightTick = 0
    @Published private(set) var successTick = 0
    /// 上限（99回）に達して足せなかったときの警告の触覚
    @Published private(set) var warningTick = 0
    /// VoiceOver が動いているとき「取り消す」を長く残す（押す前に消えない・`VisitedMapScreen` が渡す）
    var voiceOverOn = false

    private(set) var userId: String?
    private let store: VisitedPrefectureStore
    private let now: () -> Date
    private let calendar: Calendar
    private var toastCounter = 0
    private var quickBarCounter = 0

    /// 「取り消す」を出しておく秒数
    nonisolated static let toastSeconds: Double = 5
    /// VoiceOver のときの秒数（読み上げを聞いてから押せる長さ）
    nonisolated static let voiceOverToastSeconds: Double = 30
    /// 押した県の帯を出しておく秒数（モック A・「取り消す」と同じ 5 秒）
    nonisolated static let quickBarDefaultSeconds: Double = 5
    /// 帯を消すまでの秒数（試験だけ短くする）
    var quickBarSeconds: Double = VisitedMapModel.quickBarDefaultSeconds

    init(store: VisitedPrefectureStore = VisitedPrefectureStore(), now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    // MARK: - 読む

    var today: String { VisitedDay.string(from: now(), calendar: calendar) }

    var candidates: [String] { record.candidates(found: found) }

    func isCandidate(_ prefecture: String) -> Bool { candidates.contains(prefecture) }

    var breakdown: (fromPhotos: Int, byHand: Int) {
        let b = record.breakdown(found: found)
        return (b.fromPhotos, b.recordedOnly)
    }

    /// 地図に何も無い（記録も候補も無い）
    var isEmpty: Bool { record.visitedCount == 0 && candidates.isEmpty }

    // MARK: - 開く

    /// 人が替わったら読み直す。**開いた時点ですでにそろっていれば祝わない**（`settleOnOpen`）
    func open(userId: String?) {
        if self.userId != userId {
            history.removeAll()
            toast = nil
            celebration = nil
            quickBar = nil
            quickBarHeld = false
            selected = nil
            found = []
            photosState = .idle
        }
        self.userId = userId
        record = store.load(for: userId)
        let before = record
        record.settleOnOpen()
        if record != before { persist() }
    }

    /// 画面写真のための見本（Debug のみ・`PreviewSession.visitedMapSeed`）。端末には書かない
    func seedForPreview(_ seed: VisitedPrefectures) {
        record = seed
        record.settleOnOpen()
        history.removeAll()
    }

    func beginLoadingPhotos() {
        if photosState != .loaded { photosState = .loading }
    }

    func applyPhotos(_ photos: [Photo], spots: [OfficialSpot]) {
        let resolver = PrefectureResolver(spots: spots)
        found = resolver.found(in: photos)
        photosByPrefecture = Self.group(photos, by: resolver)
        photosState = .loaded
    }

    /// 写真を県で分ける（県の分からない写真は入れない・並びは渡された順のまま）
    static func group(_ photos: [Photo], by resolver: PrefectureResolver) -> [String: [Photo]] {
        var out: [String: [Photo]] = [:]
        for photo in photos {
            guard let name = resolver.prefecture(of: photo) else { continue }
            out[name, default: []].append(photo)
        }
        return out
    }

    /// 候補のチップを押した: **その場で 1 回記録する**（2026-11-12 判断・案「行った県」: 札を開いて「記録する」の
    /// 2 回 → 1 回）。札の「記録する」と同じ足し方（外していた候補の印も戻す）で、帯の「取り消す」で戻せる
    func recordCandidate(_ prefecture: String) {
        guard isCandidate(prefecture) else { return }
        add(prefecture)
    }

    func failPhotos() { photosState = .failed }

    // MARK: - 地図・一覧を押す（案 A）

    /// 県を押した: **押すたびに 1 回足し**、帯を出す（同じ日でも確かめない・押した数だけ足す）
    func tap(_ prefecture: String) {
        guard RegionList.prefectures.contains(prefecture) else { return }
        showQuickBar(prefecture)
        add(prefecture, quick: true)
    }

    /// 長押し: 足さずに帯だけ出す（見る・帯の［−］で減らす）
    func peek(_ prefecture: String) {
        guard RegionList.prefectures.contains(prefecture) else { return }
        showQuickBar(prefecture)
        announcement = VisitedMapText.prefectureAccessibility(prefecture, count: record.count(prefecture),
                                                              isCandidate: isCandidate(prefecture))
    }

    /// 帯の［＋］
    func quickAdd() {
        guard let name = quickBar?.prefecture else { return }
        add(name, quick: true)
        armQuickBar()
    }

    /// 帯の［−］: 確かめずに 1 回減らす（0 回で塗りが消える。［＋］で戻せる）
    func quickRemove() {
        guard let name = quickBar?.prefecture else { return }
        decrease(name)
        armQuickBar()
    }

    /// 1 回減らして帯を出す（帯の［−］・読み上げの操作「1 回減らす」）。0 回なら何もしない
    func decrease(_ prefecture: String) {
        guard RegionList.prefectures.contains(prefecture) else { return }
        if quickBar?.prefecture != prefecture { showQuickBar(prefecture) }
        guard let change = record.removeLast(prefecture) else {
            // 0 回（［−］は押せない見た目。読み上げの操作から来たときだけここに来る）: 今の数を読む
            announcement = VisitedMapText.prefectureAccessibility(prefecture, count: 0, isCandidate: isCandidate(prefecture))
            return
        }
        history.push(change)
        finish(message: nil, name: prefecture, keepsToast: false,
               spoken: VisitedMapText.quickRemoved(prefecture, count: record.count(prefecture)))
    }

    /// 帯の［詳しく］・候補の一覧・読み上げの操作「詳しく」: 札（日付・候補・近くの県）を開く。帯は閉じる
    func openCard(_ prefecture: String) {
        guard RegionList.prefectures.contains(prefecture) else { return }
        dismissQuickBar()
        selected = prefecture
    }

    /// 地図の指を離したときの結果（`VisitedMapTouch.onRelease`）を記録に結ぶ。押す＝1 回足す・長押し＝足さずに帯・
    /// 動かした・ピンチした・長押しで帯を出し終えた指＝何もしない
    func release(_ outcome: VisitedMapTouch.Outcome, on prefecture: String) {
        switch outcome {
        case .add: tap(prefecture)
        case .peek: peek(prefecture)
        case .none: break
        }
    }

    /// 帯を触っている間は消さない。離したら 5 秒を数え直す
    func setQuickBarHeld(_ held: Bool) {
        guard quickBarHeld != held else { return }
        quickBarHeld = held
        if held { quickBar?.deadline = nil } else { armQuickBar() }
    }

    func dismissQuickBar() {
        quickBar = nil
        quickBarHeld = false
    }

    /// 時間切れ（`timerID` が今の帯のものなら消す）。触っている間は消さない
    func expireQuickBar(_ timerID: Int) {
        guard quickBar?.timerID == timerID, !quickBarHeld else { return }
        quickBar = nil
    }

    // MARK: - 記録の変更

    /// 1 回足す（札の ＋・「記録する」）。同じ日でも確かめずに足す（2026-11-10 owner）
    func add(_ prefecture: String) { add(prefecture, quick: false) }

    /// - quick: 地図・一覧・帯から足した回。「取り消す」の帯を作らない（帯の［−］が兼ねる）・
    ///   読み上げは「東京都、3 回、1 回足しました」
    private func add(_ prefecture: String, quick: Bool) {
        guard record.count(prefecture) < VisitedPrefectures.maxCount else {
            // 黙って何も起きないままにしない: 一言と警告の触覚（帯の回は［＋］を押せない形にして見せる）
            warningTick += 1
            announcement = VisitedMapText.limitReached(prefecture)
            if !quick {
                toastCounter += 1
                let notice = Toast(id: toastCounter, message: VisitedMapText.limitReached(prefecture), offersUndo: false)
                toast = notice
                scheduleToastEnd(notice.id)
            }
            return
        }
        let change = record.add(prefecture, day: today)
        // 外していた候補は、札で「記録する」「＋」と決めて足したときだけ戻す（0 回に戻したときにまた候補に出る）。
        // 2026-11-10 判断（札 #510・レビュー）: 地図・一覧・帯から足した回（quick）は戻さない。押すたびに足す形では
        // うっかり押して［−］で戻すことがあり、そのたびに外した印が黙って消えると、外した候補がまた出てくる。
        // quick の回は外した印に触らないので、戻す記録（`VisitedChange`）に印の前の状態は持たせない
        if !quick { record.restoreCandidate(prefecture) }
        guard let change else { return }
        history.push(change)
        addPulsePrefecture = prefecture
        addPulse += 1
        if quick {
            finish(message: nil, name: prefecture, keepsToast: false,
                   spoken: VisitedMapText.quickAdded(prefecture, count: record.count(prefecture)))
        } else {
            finish(message: VisitedMapText.recorded(prefecture, count: record.count(prefecture)), name: prefecture)
        }
    }

    /// 札の「−」: 1 回減らす（0 回で記録を外す）
    func remove(_ prefecture: String) {
        apply(record.removeLast(prefecture)) { name, count in VisitedMapText.reduced(name, count: count) }
    }

    /// 「47県ぜんぶ行った」（確認のあとで）
    func markAllVisited() {
        guard let change = record.markAllVisited(day: today) else { return }
        history.push(change)
        finish(message: VisitedMapText.recordedAllToast, name: nil, celebrates: false)
    }

    /// 「記録をすべて外す」（確認のあとで）
    func clearAll() {
        guard let change = record.clearAll() else { return }
        history.push(change)
        finish(message: VisitedMapText.clearedAllToast, name: nil)
    }

    /// 日付を直す（札の日付の行）
    func changeDay(_ prefecture: String, at index: Int, to day: String) {
        guard VisitedDay.isValid(day), let change = record.changeDay(prefecture, at: index, to: day) else { return }
        history.push(change)
        persist()
        objectWillChange.send()
    }

    /// 「取り消す」（直後のトースト）・「ひとつ戻す」（右上）はどちらも一手戻す
    func undo() {
        guard let change = history.undo(on: &record) else { return }
        toast = nil
        // 帯の県と関係のない一手を戻したら、帯は閉じる（帯の数と画面の動きを食い違わせない）
        if let bar = quickBar, change.after[bar.prefecture] == nil { dismissQuickBar() }
        lightTick += 1
        persist()
        if change.after.count == 1, let name = change.after.keys.first {
            announcement = VisitedMapText.changeAnnouncement(name, count: record.count(name), visited: record.visitedCount)
        } else {
            announcement = VisitedMapText.ratio(record.visitedCount)
        }
    }

    var canUndo: Bool { history.canUndo }

    func dismissCandidate(_ prefecture: String) {
        record.dismissCandidate(prefecture)
        persist()
        objectWillChange.send()
    }

    func restoreCandidate(_ prefecture: String) {
        record.restoreCandidate(prefecture)
        persist()
        objectWillChange.send()
    }

    func dismissCelebration() { celebration = nil }

    func clearToast() { toast = nil }

    func clearAnnouncement() { announcement = nil }

    // MARK: - 内部

    /// 1 県の変更を記録の履歴・保存・トースト・読み上げ・祝いに結ぶ
    private func apply(_ change: VisitedChange?, message: (String, Int) -> String) {
        guard let change, let name = change.after.keys.first else { return }
        history.push(change)
        finish(message: message(name, record.count(name)), name: name)
    }

    /// - celebrates: false なら、そろった周は「見せた」ことにだけして祝わない（「47県ぜんぶ行った」の一括は
    ///   本人がまとめて申告したもので、祝う場面ではない）
    /// - keepsToast: false なら、出ている「取り消す」の帯に手を付けない（帯から足し引きした回）
    /// - spoken: 読み上げを替える（帯から足し引きした回「東京都、3 回、1 回足しました」）
    private func finish(message: String?, name: String?, celebrates: Bool = true, keepsToast: Bool = true,
                        spoken override: String? = nil) {
        let celebrated = record.takeCelebration()
        let celebrating = celebrated != nil && celebrates
        if celebrating, let celebrated {
            celebration = celebrated
            // 触覚は成功の1回だけ（軽い触覚と重ねない）
            successTick += 1
            // 祝いの札が出ると帯は隠れる（`VisitedBottomBar`）。帯を押さえたまま隠れると「触っている」が残り、
            // 帯がいつまでも消えなくなるので、ここで離したことにして数え直す（レビュー 2026-11-10）
            if quickBarHeld { setQuickBarHeld(false) }
        } else {
            lightTick += 1
        }
        persist()
        if let message {
            toastCounter += 1
            let current = Toast(id: toastCounter, message: message)
            toast = current
            scheduleToastEnd(current.id)
        } else if keepsToast {
            toast = nil
        }
        var spoken = override ?? name.map {
            VisitedMapText.changeAnnouncement($0, count: record.count($0), visited: record.visitedCount)
        } ?? VisitedMapText.ratio(record.visitedCount)
        // 祝いは目で見る札なので、VoiceOver の人にも文で伝える
        if celebrating, let celebrated {
            spoken = "\(VisitedMapText.celebrationTitle(celebrated))。\(spoken)"
        }
        announcement = spoken
    }

    private func scheduleToastEnd(_ id: Int) {
        Task { [weak self] in
            let seconds = self?.voiceOverOn == true ? Self.voiceOverToastSeconds : Self.toastSeconds
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.toast?.id == id else { return }
            self.toast = nil
        }
    }

    private func showQuickBar(_ prefecture: String) {
        // 「取り消す」の帯と同じ下に重ねない（帯の［−］が取り消しを兼ねる）
        toast = nil
        quickBarCounter += 1
        quickBar = QuickBar(prefecture: prefecture, timerID: quickBarCounter)
        if !quickBarHeld { scheduleQuickBarEnd(quickBarCounter) }
    }

    /// 5 秒を数え直す（帯の［−］［＋］・指を離したとき）
    private func armQuickBar() {
        guard var bar = quickBar else { return }
        quickBarCounter += 1
        bar.timerID = quickBarCounter
        bar.deadline = nil
        quickBar = bar
        if !quickBarHeld { scheduleQuickBarEnd(bar.timerID) }
    }

    private func scheduleQuickBarEnd(_ id: Int) {
        let seconds = voiceOverOn ? Self.voiceOverToastSeconds : quickBarSeconds
        if quickBar?.timerID == id {
            quickBar?.deadline = Date().addingTimeInterval(seconds)
            quickBar?.seconds = seconds
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.expireQuickBar(id)
        }
    }

    private func persist() { store.save(record, for: userId) }
}
