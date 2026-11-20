import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 端末の AI（Apple Foundation Models）で「AI に頼む」に答える（札 #652）。**外へは何も送らない**（回数を取るだけ）。
///
/// - AI はアプリの中のものを**道具**（Foundation Models の `Tool`・読むだけ）で引いて答える。道具は5つだけ:
///   観光スポットの台帳、公開の写真、その人の行きたい場所、その人の旅行プラン、使い方の頁（`AskLibrary`）。
///   **作りの資料、コード、設定、DM、ほかの人の非公開の物を読む道具は作らない**（CLAUDE.md・絶対）
/// - 引いたものは `AskCollector` に残し、答えの下に札で見せる。何も引かなかった答えは「一般的な答え」
/// - 指示には答えないもの（`AskGuard.safetyInstructions`）を書き、利用者の文と台帳の文はデータとして囲む
/// - 答えの文は呼び手（`AskEngine`）が見張り（`AskGuard.screened`）を通してから出す
/// - 文脈は 4,096 トークン。直前の2往復だけを渡す
enum AskDevice {

    struct Result {
        let text: String
        /// 何も引かずに答えた（「一般的な答え」）
        let general: Bool
        let picks: [AskLibrary.Pick]
        let photoIds: [String]
        let sources: [AskAnswer.Source]
    }

    /// 待つ上限。過ぎたら言葉の表で答える
    static let timeout: Duration = .seconds(20)

    /// 指示。役目と答えの形と、答えないもの
    static func instructions(today: String) -> String {
        """
        あなたは日本の旅と写真のアプリの案内係です。今日は\(today)です。
        利用者の質問に、日本語で短く（3〜6行）答えます。
        観光スポットをすすめるときは、必ず道具 findSpots で台帳から引き、引いた所だけを名前で挙げます。台帳に無い場所を作りません。
        写真のことは findPhotos、利用者自身の行きたい場所は myWishlist、利用者自身の旅行プランは myTrips、
        アプリの使い方は appHelp で引いて答えます。引けないことは、一般的な知識で短く答えます。
        季節の案内は春夏秋冬の4つだけで、週ごとの見頃は分かりません。分からないことは分からないと言います。
        DM やコメントの返事の文は書きません。
        \(AskGuard.safetyInstructions)
        """
    }

    /// 渡す文（直前の2往復と質問。どれもデータとして囲む）
    static func prompt(_ question: String, history: [AskExchange]) -> String {
        var lines: [String] = []
        for e in history.suffix(AskService.historyTurns) {
            lines.append("前の質問: " + AskGuard.dataBlock(e.question, limit: 200))
            lines.append("前の答え: " + AskGuard.dataBlock(e.answer.text, limit: 300))
        }
        lines.append("質問: " + AskGuard.dataBlock(question, limit: AskQuery.maxLength))
        return lines.joined(separator: "\n")
    }

    static func todayText(_ date: Date = Date()) -> String {
        let day = AskHistoryStore.day(date).split(separator: "-").compactMap { Int($0) }
        guard day.count == 3 else { return "" }
        return "\(day[0])年\(day[1])月\(day[2])日"
    }

    /// 本物（端末の AI）。使えない、失敗、時間切れは nil
    static func live(_ question: String, history: [AskExchange], library: AskLibrary) async -> Result? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let collector = AskCollector()
            let box = AskLibraryBox(library)
            return await withTaskGroup(of: Result?.self) { group in
                group.addTask {
                    do {
                        let tools: [any Tool] = [
                            AskSpotsTool(box: box, collector: collector),
                            AskPhotosTool(box: box, collector: collector),
                            AskWishlistTool(box: box, collector: collector),
                            AskTripsTool(box: box, collector: collector),
                            AskHelpTool(collector: collector),
                        ]
                        let session = LanguageModelSession(model: SystemLanguageModel.default, tools: tools,
                                                           instructions: instructions(today: todayText()))
                        let response = try await session.respond(to: prompt(question, history: history),
                                                                 options: GenerationOptions(temperature: 0.3))
                        let snap = collector.snapshot()
                        return Result(text: response.content, general: snap.sources.isEmpty,
                                      picks: snap.picks, photoIds: snap.photoIds, sources: snap.sources)
                    } catch {
                        // 中身（質問と答え）はログに残さない。種類だけ
                        print("[ask] device failed \(type(of: error))")
                        return nil
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
        }
        #endif
        return nil
    }
}

/// 道具が引いたものを貯める（答えの下の札）。道具は別の流れから呼ばれるので鍵をかける
final class AskCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var picks: [AskLibrary.Pick] = []
    private var photoIds: [String] = []
    private var sources: [AskAnswer.Source] = []

    func add(picks new: [AskLibrary.Pick], source: AskAnswer.Source) {
        lock.lock(); defer { lock.unlock() }
        for p in new where !picks.contains(where: { $0.spot.spotId == p.spot.spotId }) { picks.append(p) }
        if !sources.contains(source) { sources.append(source) }
    }

    func add(photoIds new: [String], source: AskAnswer.Source) {
        lock.lock(); defer { lock.unlock() }
        for id in new where !photoIds.contains(id) { photoIds.append(id) }
        if !sources.contains(source) { sources.append(source) }
    }

    func add(source: AskAnswer.Source) {
        lock.lock(); defer { lock.unlock() }
        if !sources.contains(source) { sources.append(source) }
    }

    func snapshot() -> (picks: [AskLibrary.Pick], photoIds: [String], sources: [AskAnswer.Source]) {
        lock.lock(); defer { lock.unlock() }
        return (Array(picks.prefix(AskLibrary.maxSpots)), Array(photoIds.prefix(AskLibrary.maxPhotos)), sources)
    }
}

/// 棚を道具に渡す包み（読むだけ）
final class AskLibraryBox: @unchecked Sendable {
    let library: AskLibrary
    init(_ library: AskLibrary) { self.library = library }
}

#if canImport(FoundationModels)
// MARK: - 道具（読むだけ。その人の権限の範囲だけ）

/// 観光スポットの台帳を引く
@available(iOS 26.0, macOS 26.0, *)
struct AskSpotsTool: Tool {
    let name = "findSpots"
    let description = "アプリの観光スポットの台帳から、条件に合う所を探す。場所をすすめるときは必ず使う"
    let box: AskLibraryBox
    let collector: AskCollector

    @Generable
    struct Arguments {
        @Guide(description: "地名（都道府県か市町村）を質問の字のまま。無ければ「なし」")
        var place: String
        @Guide(description: "季節", .anyOf(SearchSentence.seasonChoices))
        var season: String
        @Guide(description: "時間帯", .anyOf(SearchSentence.dayPartChoices))
        var timeOfDay: String
        @Guide(description: "探したいもの（海、滝、紅葉など）を1語。無ければ「なし」")
        var keyword: String
        @Guide(description: "利用者の現在地の近くで探すか")
        var near: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        let lib = box.library
        var q = AskLibrary.Query()
        q.place = Self.word(arguments.place)
        q.season = SearchSentence.season(choice: arguments.season)
        q.dayPart = SearchSentence.dayPart(choice: arguments.timeOfDay)
        q.keyword = Self.word(arguments.keyword)
        q.near = arguments.near && lib.here != nil
        var picks = lib.pickSpots(q)
        if picks.isEmpty, let relaxed = AskLibrary.relaxed(q) { picks = lib.pickSpots(relaxed) }
        collector.add(picks: picks, source: .init(kind: .spots, label: L("観光スポットの台帳", "Tourist spot list")))
        return AskLibrary.spotLines(picks, query: q)
    }

    static func word(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "なし" ? nil : String(t.prefix(30))
    }
}

/// 公開の写真を引く（題と撮影地だけ。写真そのものは渡さない）
@available(iOS 26.0, macOS 26.0, *)
struct AskPhotosTool: Tool {
    let name = "findPhotos"
    let description = "みんなが全体に公開した写真を、語で探す（題と撮影地だけが分かる）"
    let box: AskLibraryBox
    let collector: AskCollector

    @Generable
    struct Arguments {
        @Guide(description: "探す語（地名か被写体）を1語")
        var keyword: String
    }

    func call(arguments: Arguments) async throws -> String {
        let photos = box.library.pickPhotos(near: [], keyword: AskSpotsTool.word(arguments.keyword))
        collector.add(photoIds: photos.map(\.id), source: .init(kind: .photos, label: L("公開の写真", "Public photos")))
        return AskLibrary.photoLines(photos)
    }
}

/// 利用者自身の行きたい場所
@available(iOS 26.0, macOS 26.0, *)
struct AskWishlistTool: Tool {
    let name = "myWishlist"
    let description = "利用者自身が保存した行きたい場所の一覧を見る"
    let box: AskLibraryBox
    let collector: AskCollector

    @Generable
    struct Arguments {
        @Guide(description: "何のために見るかを短く")
        var purpose: String
    }

    func call(arguments: Arguments) async throws -> String {
        collector.add(source: .init(kind: .wishlist, label: L("あなたの行きたい場所", "Your saved places")))
        return box.library.wishlistLines()
    }
}

/// 利用者自身の旅行プラン
@available(iOS 26.0, macOS 26.0, *)
struct AskTripsTool: Tool {
    let name = "myTrips"
    let description = "利用者自身の旅行プランの一覧を見る（題、日数、場所の名前）"
    let box: AskLibraryBox
    let collector: AskCollector

    @Generable
    struct Arguments {
        @Guide(description: "何のために見るかを短く")
        var purpose: String
    }

    func call(arguments: Arguments) async throws -> String {
        collector.add(source: .init(kind: .trips, label: L("あなたの旅行プラン", "Your trip plans")))
        return box.library.tripLines()
    }
}

/// アプリの使い方の頁（Web の /help と同じ中身）
@available(iOS 26.0, macOS 26.0, *)
struct AskHelpTool: Tool {
    let name = "appHelp"
    let description = "このアプリの使い方の頁を引く（ストーリー、投稿、行きたい場所、メッセージ、アルバムなど）"
    let collector: AskCollector

    @Generable
    struct Arguments {
        @Guide(description: "知りたい機能の名前か操作")
        var topic: String
    }

    func call(arguments: Arguments) async throws -> String {
        let pages = AskHelpPages.matching(arguments.topic)
        for p in pages {
            collector.add(source: .init(kind: .help, label: L("使い方の頁「\(p.title)」", "Help: \(p.title)")))
        }
        return AskHelpPages.lines(pages)
    }
}
#endif
