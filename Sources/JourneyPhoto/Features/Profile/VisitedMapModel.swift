import SwiftUI
import Combine

/// 行った県マップの画面の状態（札 #503）。記録の判定・保存は Core（`VisitedPrefectures`・
/// `VisitedPrefectureStore`）が持ち、ここは**画面の操作を記録の変更に結ぶ**だけ。
///
/// 2026-11-08 判断（提案書 第2版）:
/// - 回数を増やすのは**本人のタップだけ**。写真の候補（`found`）は数にも色にも入らない
/// - スイッチ「タップで回数を足す」は**既定オフ**で、画面を開くたびにオフに戻る（地図を動かす操作での
///   誤記録を防ぐ）。オンのときだけ地図のタップが +1
/// - 同じ県を**同じ日に2回目**に足すときは、止めずに確かめる一言（`pendingSameDay`）
/// - 戻し方は3つ: 「取り消す」（5秒）・「ひとつ戻す」（20手）・札の「−」
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
    }

    @Published private(set) var record = VisitedPrefectures()
    @Published private(set) var history = VisitedHistory()
    /// 写真から導けた県（候補の元・JIS の順）
    @Published private(set) var found: [String] = []
    @Published private(set) var photosState: PhotosState = .idle
    /// 「タップで回数を足す」
    @Published var addsOnTap = false
    @Published private(set) var toast: Toast?
    /// 祝い。画面が閉じるまで出し続け、`dismissCelebration` で消す
    @Published private(set) var celebration: VisitedPrefectures.Celebration?
    /// 「今日は記録済みです。もう 1 回足しますか」の確かめを待っている県
    @Published private(set) var pendingSameDay: String?
    /// 札（県）を開いている県
    @Published var selected: String?
    /// 数が変わったあとの読み上げ（`UIAccessibility.post` は画面が行う）
    @Published private(set) var announcement: String?
    /// 触覚の合図（値が変わったら鳴らす）。足す・引く・戻すは軽く、周がそろったときだけ成功
    @Published private(set) var lightTick = 0
    @Published private(set) var successTick = 0

    private(set) var userId: String?
    private let store: VisitedPrefectureStore
    private let now: () -> Date
    private let calendar: Calendar
    private var toastCounter = 0

    /// 「取り消す」を出しておく秒数
    nonisolated static let toastSeconds: Double = 5

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
            pendingSameDay = nil
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
        found = PrefectureResolver(spots: spots).found(in: photos)
        photosState = .loaded
    }

    func failPhotos() { photosState = .failed }

    // MARK: - 地図のタップ

    /// 県を押した。スイッチがオンなら 1 回足し、オフなら札を開く
    func tap(_ prefecture: String) {
        guard RegionList.prefectures.contains(prefecture) else { return }
        if addsOnTap { add(prefecture) } else { selected = prefecture }
    }

    /// 長押し・「札を開く」: スイッチによらず札を開く
    func openCard(_ prefecture: String) {
        guard RegionList.prefectures.contains(prefecture) else { return }
        selected = prefecture
    }

    // MARK: - 記録の変更

    /// 1 回足す。同じ日に記録があれば、確かめてから（`confirmSameDay`）
    func add(_ prefecture: String, confirmingSameDay: Bool = true) {
        guard record.count(prefecture) < VisitedPrefectures.maxCount else { return }
        if confirmingSameDay, record.hasVisit(prefecture, on: today) {
            pendingSameDay = prefecture
            return
        }
        let change = record.add(prefecture, day: today)
        // 外していた候補は、記録にしたら戻す（0 回に戻したときにまた候補に出る）
        record.restoreCandidate(prefecture)
        apply(change) { name, count in VisitedMapText.recorded(name, count: count) }
    }

    func confirmSameDay() {
        guard let prefecture = pendingSameDay else { return }
        pendingSameDay = nil
        add(prefecture, confirmingSameDay: false)
    }

    func cancelSameDay() { pendingSameDay = nil }

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
    private func finish(message: String?, name: String?, celebrates: Bool = true) {
        lightTick += 1
        if let celebrated = record.takeCelebration(), celebrates {
            celebration = celebrated
            successTick += 1
        }
        persist()
        if let message {
            toastCounter += 1
            let current = Toast(id: toastCounter, message: message)
            toast = current
            scheduleToastEnd(current.id)
        } else {
            toast = nil
        }
        if let name {
            announcement = VisitedMapText.changeAnnouncement(name, count: record.count(name), visited: record.visitedCount)
        } else {
            announcement = VisitedMapText.ratio(record.visitedCount)
        }
    }

    private func scheduleToastEnd(_ id: Int) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.toastSeconds * 1_000_000_000))
            guard let self, self.toast?.id == id else { return }
            self.toast = nil
        }
    }

    private func persist() { store.save(record, for: userId) }
}
