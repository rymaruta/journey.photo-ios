import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded([Photo])
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    /// 選ばれているカテゴリ。nil は「すべて」
    @Published var category: String?
    /// 並び替え。**Web の `FilterBar` と同じ3つ**（新しい順／古い順／人気順）
    /// **初めのフィード（おすすめ）の並びで始める。** `.new` から始めると、最初の
    /// 読み込みが新しい順で並び、あとから `use` で並べ直されて一覧が入れ替わっていた
    @Published var sort: GallerySort = HomeFeed.recommended.sort
    /// ホームのフィード（おすすめ / フォロー中 / 新着）。
    /// **範囲と並びの組に名前を付けたもの**（`HomeFeed`）
    @Published private(set) var feed: HomeFeed = .recommended
    /// 選んでいるタグ。**複数選べて、全部を持つ写真だけが残る**
    /// （Web の `selectedTags` と同じ）
    @Published private(set) var selectedTags: [String] = []
    /// 打った文字。題・説明・撮影地・タグを見る
    @Published var query: String = "" { didSet { state = .loaded(filtered()) } }
    /// 出す範囲（自分 / フォロー中 / すべて）。**選んでいるフィードが決める**（`HomeFeed.scope`）
    @Published private(set) var scope: GalleryScope = .all
    /// フォローしている人。`following` のときだけ要る
    /// フォロー先。**カードのフォローボタンにも渡す**（モック1）
    private(set) var followingIds: Set<String> = []
    /// フォロー一覧を**取れなかった**（圏外など）。
    ///
    /// 取れなかった回を空の集合で表すと、「フォロー中」に
    /// 「フォロー中の人の写真はまだありません」と出る——フォローしている人に
    /// 「まだ誰もいない」と言うことになる。画面はこれを見て
    /// 「読み込めませんでした」を出す
    @Published private(set) var followingFailed = false
    /// `followingIds` が**誰の**フォロー先か。同じ人で取れなかった回に
    /// 手元の集合を潰さないために見る（人が替わった回だけ空にする）
    private var followingOwner: String?
    private var viewerId: String?
    /// **見ていた人から替わった先の人たち**（いまの人は入らない）。
    ///
    /// 遅れて着いた前の人のフォロー一覧（`refreshFollowing`）を捨てる目印。
    /// `self.viewerId` と違うだけでは捨てない——人が替わった直後（`use` の前）に
    /// 取れた**今の人**の集合まで捨てることになる
    private var departedViewerIds: Set<String> = []

    /// 見ている人を入れ替える。前の人を「離れた人」に入れ、戻ってきた人は外す
    private func setViewer(_ newViewer: String?) {
        guard newViewer != viewerId else { return }
        if let old = viewerId { departedViewerIds.insert(old) }
        if let newViewer { departedViewerIds.remove(newViewer) }
        viewerId = newViewer
    }

    /// **画面がこれから取りに行く人**を知らせる（`.task` の頭・await の前）。
    ///
    /// A→B→A と戻ったとき、戻った A は `use` が走るまで「離れた人」に入ったまま
    /// なので、その間に引き下げで取れた A の正しい一覧を `refreshFollowing` が
    /// 捨てていた。見ている人（`viewerId`）はここでは替えない
    func expect(viewerId newViewer: String?) {
        if let old = viewerId, old != newViewer { departedViewerIds.insert(old) }
        if let newViewer { departedViewerIds.remove(newViewer) }
    }

    /// 絞り込みに出すカテゴリ。**写真が1枚もない種類は出さない**
    /// （押しても空になるボタンを置かない）
    @Published private(set) var categories: [String] = []

    /// 公開一覧の出どころ。**`let` にしない。**
    ///
    /// `@StateObject` の初期化時には `EnvironmentObject` を読めないので、
    /// 画面が出てから本物（`AppEnvironment.gallery`）に差し替える。
    /// 自前の `PublicGalleryService()` を持ったままだと、
    /// `setHidden` は環境側の1つにしか届かず、**ブロックした相手の写真が
    /// ギャラリーから一生消えない**（再起動しても消えない）。
    private var gallery: PublicGalleryService

    /// 公開写真のページ（`GET /feed`）。**nil ならページで読まない**（今までどおり
    /// `photos.json` だけ）。`gallery` と同じ理由で、画面が出てから環境の1つを入れる
    private var feedPages: PublicFeedService?

    init(gallery: PublicGalleryService = PublicGalleryService(), feed: PublicFeedService? = nil) {
        self.gallery = gallery
        self.feedPages = feed
    }

    /// 画面が出たら、環境が持っている1つに繋ぎ直す。
    func use(gallery: PublicGalleryService, feed: PublicFeedService? = nil) {
        self.gallery = gallery
        if let feed { self.feedPages = feed }
    }

    /// - Parameter force: 控えを無視して取り直す（引き下げ更新）。**ページは1ページ目から読み直す**
    ///
    /// **`photos.json`（全件）と `/feed` の1ページ目を同時に読む**（2026-10-03）。
    /// 「新着」は1ページ目が着いた時点で出す（全件を待たない）。全件は、全件が要る
    /// 札（おすすめ・フォロー中・カテゴリ・タグ・検索・今日のテーマ）のために今までどおり読む。
    /// `/feed` が使えない（道が無い 404・500・圏外・壊れた答え）回は全件の並びに戻る
    func load(force: Bool = false) async {
        // 再読み込みのときに画面を空にしない（読み込み中の白画面を挟まない）
        if case .loaded = state {} else { state = .loading }
        let generation = viewerGeneration
        // 全件を読んでいる間に始まった1ページ目は、限定公開を読みに行かない（`showFirstPage`）
        snapshotLoadsInFlight += 1
        defer { snapshotLoadsInFlight -= 1 }
        loadSerial += 1
        let mine = loadSerial
        // 引き下げ（force）の回は、走っている間だけ覚える（`writes` の3つ目）
        if force { runningForced.insert(mine) }
        defer { runningForced.remove(mine) }
        loadedEpoch = await gallery.restrictedEpoch
        // **`/feed` は「新着」のときだけ読む**（2026-10-03 のレビュー）。おすすめなどでは読まない・待たない。
        // 「新着」でも、引き下げ・まだ試していない回・1ページ目が古い回（`firstPageIsStale`）だけ
        // 1ページ目から読む。それ以外の読み直し（force なし）は、読んだページを持ったまま
        // 仕上げだけ掛け直す（下まで送った一覧を縮めない）
        let readsFirstPage = feed == .latest && feedPages != nil
            && (force || pageSource == .untried || firstPageIsStale)
        // 「新着」以外で引き下げた回は、手元の1ページ目を古いことにする（次に「新着」を選んだら読み直す）
        if force, !readsFirstPage, pageSource == .pages { firstPageReadAt = nil }
        if readsFirstPage {
            // 1ページ目と全件を同時に読み、**どちらも着いた時点で書く**（片方を待たない）
            async let firstPage: Void = showFirstPage(force: force, generation: generation, alongsideSnapshot: true)
            await finishSnapshot(serial: mine, force: force, generation: generation)
            await firstPage
        } else {
            await finishSnapshot(serial: mine, force: force, generation: generation)
        }
    }

    /// 全件（`photos.json`）を読んで書く。**最後の書き込みはここだけで、`writes` を通す**
    private func finishSnapshot(serial mine: Int, force: Bool, generation: Int) async {
        // **catch の中で await しない**（Xcode 26.3 の SILGen）。結果を外へ持ち出してから分ける
        let result: Result<[Photo], Error>
        do {
            result = .success(try await gallery.fetchPhotos(force: force))
        } catch {
            result = .failure(error)
        }
        // 限定公開の控え・いいねの数を取り直した後で、読んだページの仕上げを掛け直す
        // （`writes` の後に await を挟まない——書くと決めたら必ずすぐ書く）
        if pageSource == .pages, pendingPage == nil { await representPages(loadsRestricted: true) }
        guard writes(mine, force: force, generation: generation) else { return }
        switch result {
        case .success(let photos):
            all = sorted(photos)
            state = .loaded(filtered())
        case .failure(let error):
            // 全件が読めなくても、ページで出している「新着」は出し続ける
            if usesPagedFeed {
                state = .loaded(filtered())
            } else {
                state = .failed((error as? APIError)?.errorDescription ?? Labels.Common.loadFailed)
            }
        }
    }

    /// 読み込みを始めた回数（`load` の番号）
    private var loadSerial = 0
    /// 一覧を書き終えた回の番号（`writes`）。**書かなかった回は数えない**
    private var lastWrittenSerial = 0
    /// 走っている引き下げ（force）の回の番号
    private var runningForced: Set<Int> = []

    /// その回の答えを書くか。**書くと決めたら `lastWrittenSerial` を進める**（呼んだら必ず書くこと）。
    ///
    /// - 読んでいる間に人が替わった回は書かない（前の人の限定公開を持ち込む）
    /// - 取り消されて出している一覧を残す回（`keepsShownFeed`）は書かない
    /// - 🔴 **書き終えた回より新しい回だけ書く**（バグ探し 2026-10-03）。ホームの読み込みは画面の
    ///   `.task`・引き下げ・限定公開の口の入れ替え（`restrictedChanges`）・ブロックから重なって
    ///   走り、先に始めた回が後から着くと、後の回の新しい一覧（入れ替わった口の限定公開・
    ///   引き下げで取り直した数）を古い一覧で戻していた。
    ///   「最後に始めた回だけ」にしないのは、後の回が取り消されて何も書かなかったとき、
    ///   先の回の答えまで捨てて古い一覧が残るため——**何も書かなかった回は数えない**
    /// - 🔴 **引き下げの答えを待っている間に始まった force なしの回は書かない。** force なしの回は
    ///   60秒の控えから即座に返るので、番号は新しくても中身は引き下げより古い。書くと、あとから
    ///   着いた引き下げの新しい答えが「古い番号」として捨てられていた。引き下げが着けばそれを書く
    ///
    /// 2026-10-03 判断: 後の回が**失敗**して帯を書いたあとに先の回が取れても、先の回は書かない
    /// （帯の「もう一度試す」と引き下げが出口）。引き下げが失敗した回は、待っている間の
    /// force なしの答えも捨てたまま帯になる（引き下げは利用者が自分で引いたものなので、その結果を出す）
    ///
    /// **`/feed` の1ページ目の表示はここを通さない**（`showFirstPage`）。あちらは全件の回の番号とは
    /// 別の道で、`keepsShownFeed`・人の切り替えの番号・ページの番号（`pageSerial`）で守る
    private func writes(_ serial: Int, force: Bool, generation: Int) -> Bool {
        guard !keepsShownFeed, generation == viewerGeneration, serial > lastWrittenSerial else { return false }
        if !force, runningForced.contains(where: { $0 < serial }) { return false }
        lastWrittenSerial = serial
        return true
    }

    // MARK: - 公開写真のページ（`GET /feed`・2026-10-03）

    /// 「新着」の出どころ
    private enum PageSource {
        /// まだ試していない（「新着」で次に読み込むとき1ページ目を読む）
        case untried
        /// `/feed` で読めている
        case pages
        /// `/feed` が使えなかった。**全件（`photos.json`）の並びに戻っている**。
        /// 次の引き下げでまた試す
        case snapshot
    }

    private var pageSource: PageSource = .untried
    /// 読んだページの写真（届いた順・id で重複を除いたもの。仕上げ前）
    private var pageRaw: [Photo] = []
    private var pageIds: Set<String> = []
    /// 次のページの札。**nil なら最後まで読んだ**（続きの有無はこれだけで決める）
    private var nextCursor: String?
    /// 仕上げ（限定公開・ブロック）を掛けた、出す並び
    private var pagedPhotos: [Photo] = []
    /// ページを読み直した回数。**読み直しの前に始めた続きの答えを書かない**ために使う
    private var pageSerial = 0
    /// 仕上げを始めた回数。遅れて終わった古い仕上げで新しい並びを戻さない
    private var presentSerial = 0
    /// 読んでいる最中の1ページ目。**同じ回の読み直しはこれを待つ**（起動時の `.task` と
    /// 限定公開の口の入れ替えが重なっても `/feed` を2度読まない）
    private var firstPageTask: (serial: Int, task: Task<Bool, Never>)?

    /// 画面に出ている間に届かなかった続き（`PageWrite.whenVisible`）。戻ってきたら足す
    private struct PendingPage {
        let serial: Int
        let items: [Photo]
        let next: String?
    }
    private var pendingPage: PendingPage?
    /// 画面に出ていない間に1ページ目から読み直した（続きの札の 400）。戻ってきたら書く
    private var pageWriteDeferred = false
    /// ホームが画面に出ているか（詳細を上に積んでいる間は false）。**既定は出ている**
    private(set) var isOnScreen = true

    /// ページを読んでいる最中。**続きを重ねて頼まない**
    @Published private(set) var isLoadingPage = false
    /// 続きを読めなかった（一覧の下に「もう一度試す」を出す）
    @Published private(set) var pageFailed = false
    /// 読んだページの数。一覧の下の目印をこれで作り直す——短いページで目印が画面に
    /// 残ったままでも、作り直すと `onAppear` がもう一度走って次を読む
    @Published private(set) var loadedPageCount = 0

    /// 走っている全件の読み込み（`load`）の数
    private var snapshotLoadsInFlight = 0

    /// 札を選んだときなどに起こした、1ページ目の読み込み（試験が待つため）
    private(set) var pagesTask: Task<Void, Never>?

    /// 空のページ（`items` が空で `nextCursor` だけ）が続いたとき、1回の頼みで続けて読む上限。
    /// 超えたら一度返し、一覧の下の目印が次を頼む
    static let maxEmptyPageHops = 5

    /// 届いた続きを、いま一覧に書くか。
    ///
    /// 🔴 **詳細を開いている間（ホームが画面に出ていない間）は書かない。** 足すと末尾の欠けた段
    /// （`EditorialLayout.Row.id` は隣の写真まで含む）が作り直され、そこから開いた詳細が閉じる。
    /// ページで出していない札（おすすめなど）では一覧に響かないので、すぐ足してよい
    enum PageWrite: Equatable {
        case now
        case whenVisible
    }

    static func pageWrite(isOnScreen: Bool, showsPages: Bool) -> PageWrite {
        (isOnScreen || !showsPages) ? .now : .whenVisible
    }

    /// いま「新着」をページで出しているか。
    ///
    /// **2026-10-03 判断:** ページで出すのは「新着」（新しい順・範囲はすべて）で、
    /// カテゴリ・タグ・検索の絞りが無いときだけ。`/feed` は新しい順しか返さないので、
    /// おすすめ（選んだ写真を先頭に・いいね順）・フォロー中（フォロー先で絞る）・
    /// 絞り込みは、読んだページだけで並べると全体の答えと食い違う。全件の `photos.json` のまま
    var usesPagedFeed: Bool {
        pageSource == .pages
            && feed == .latest && sort == .new && scope == .all
            && category == nil && selectedTags.isEmpty
            && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 一覧の下に「続きを読む」目印を出すか
    var hasMorePages: Bool { usesPagedFeed && nextCursor != nil }

    /// 1ページ目を読み、**ページで出しているなら書く**。`writes` は通さない（`writes` の注記）。
    /// `/feed` が使えなかった回は何も書かない——全件の回（`finishSnapshot`）が書く
    /// （ここで書くと、全件がまだの間に空の一覧を出してしまう）
    private func showFirstPage(force: Bool, generation: Int, alongsideSnapshot: Bool) async {
        // 全件と同時に読む回・全件の読み込みが走っている間は、限定公開を読みに行かない
        // （全件の回が読み、読み終えたら掛け直す。二重に読まない）
        let loadsRestricted = !alongsideSnapshot && snapshotLoadsInFlight == 0
        guard let serial = await reloadPages(force: force, loadsRestricted: loadsRestricted) else {
            // 全件と同時でない回（札を選んだ・札の 400 で読み直した）で全件に戻ったら、全件の並びを出し直す
            // （ページの並びが出たまま残らないように）。全件と同時の回は全件の回が書く
            if !alongsideSnapshot, pageSource == .snapshot, generation == viewerGeneration,
               !keepsShownFeed, isOnScreen, case .loaded = state {
                state = .loaded(filtered())
            }
            return
        }
        guard serial == pageSerial, !keepsShownFeed, generation == viewerGeneration, usesPagedFeed else { return }
        guard isOnScreen else {
            pageWriteDeferred = true
            return
        }
        state = .loaded(filtered())
    }

    /// 「新着」を選んだとき、まだ試していない・1ページ目が古ければ1ページ目を読む
    func loadPagesIfNeeded() async {
        guard feed == .latest, feedPages != nil, pageSource == .untried || firstPageIsStale else { return }
        await showFirstPage(force: false, generation: viewerGeneration, alongsideSnapshot: false)
    }

    /// 1ページ目を読み終えた時刻。nil は「古いことにした」（新着以外で引き下げた）
    private var firstPageReadAt: Date?
    /// 今の時刻（試験が進める）
    var clock: () -> Date = Date.init
    /// 1ページ目をこれより前に読んでいたら、「新着」を選んだとき・読み込みのときに読み直す
    static let firstPageFreshness: TimeInterval = 60

    /// 手元の1ページ目が古いか。
    ///
    /// **2026-10-03 判断:** 「新着」は「新着」を見ている間しか読まないので、おすすめで引き下げた・
    /// 詳細から戻った・ブロックの後の読み直しのあとも、前に読んだ1ページ目が出続けていた。
    /// 読んでから60秒（全件の控え `PublicGalleryService.cacheLifetime` と同じ）を過ぎたら古いとする。
    /// **読み直すのは2ページ目以降をまだ読んでいないときだけ**——下まで送った一覧を1ページに
    /// 縮めると、見ていた場所が消える（そちらは引き下げで新しくする）
    var firstPageIsStale: Bool {
        guard pageSource == .pages, loadedPageCount <= 1, pendingPage == nil else { return false }
        guard let readAt = firstPageReadAt else { return true }
        return clock().timeIntervalSince(readAt) >= Self.firstPageFreshness
    }

    /// 1ページ目から読み直す。読めたらその回の番号（`pageSerial`）を返す
    private func reloadPages(force: Bool, loadsRestricted: Bool) async -> Int? {
        guard let feedPages else { return nil }
        // 同じ回の1ページ目を読んでいる最中なら、それを待つ（引き下げは新しく読む）
        if !force, let running = firstPageTask, running.serial == pageSerial {
            return await running.task.value ? running.serial : nil
        }
        pageSerial += 1
        let serial = pageSerial
        pendingPage = nil
        isLoadingPage = true
        let task = Task { await self.readFirstPage(feedPages, serial: serial, loadsRestricted: loadsRestricted) }
        firstPageTask = (serial, task)
        let ok = await task.value
        if firstPageTask?.serial == serial { firstPageTask = nil }
        return ok ? serial : nil
    }

    private func readFirstPage(_ feedPages: PublicFeedService, serial: Int, loadsRestricted: Bool) async -> Bool {
        defer { if serial == pageSerial { isLoadingPage = false } }
        let outcome = await readPages(feedPages, from: nil, known: [])
        guard serial == pageSerial else { return false }
        switch outcome {
        case .success(let (items, cursor)):
            pageRaw = items
            pageIds = Set(items.map(\.id))
            nextCursor = cursor
            pageSource = .pages
            pageFailed = false
            loadedPageCount = 1
            firstPageReadAt = clock()
            await representPages(loadsRestricted: loadsRestricted)
            return serial == pageSerial
        case .failure(let error):
            // 取り消された回は何も変えない（出ていた並びを残す）
            if error is CancellationError { return false }
            // **全件の並びに戻る。** 道が無い 404（`isMissingRoute`）・500・圏外・壊れた答えの
            // どれでも、ホームを空にしない——戻り先の `photos.json` は端末の控えも持つ
            print("[feed] 公開写真のページを読めませんでした。photos.json に戻ります: \(error)")
            clearPages()
            pageSource = .snapshot
            return false
        }
    }

    /// 次のページを読む（一覧の下の目印が呼ぶ）。**読んでいる最中・最後まで読んだ回・
    /// 届いた続きをまだ足していない回は何もしない**
    func loadNextPage() async {
        guard let feedPages, pageSource == .pages, pendingPage == nil,
              let cursor = nextCursor, !isLoadingPage else { return }
        isLoadingPage = true
        let serial = pageSerial
        let generation = viewerGeneration
        defer { if serial == pageSerial { isLoadingPage = false } }
        let outcome = await readPages(feedPages, from: cursor, known: pageIds)
        // 待つ間に引き下げ・人の切り替えで読み直していたら、古い続きを書かない
        guard serial == pageSerial, generation == viewerGeneration else { return }
        switch outcome {
        case .success(let (items, next)):
            let page = PendingPage(serial: serial, items: items, next: next)
            switch Self.pageWrite(isOnScreen: isOnScreen, showsPages: usesPagedFeed) {
            case .now: await apply(page)
            case .whenVisible: pendingPage = page
            }
        case .failure(let error):
            if error is CancellationError { return }
            // 🔴 **札を断られた（400）なら1ページ目から読み直す。** 同じ札で「もう一度試す」を
            // 押しても永遠に 400 で、続きが読めないまま残っていた
            if case .server(400, _)? = error as? APIError {
                print("[feed] 続きの札を断られました。1ページ目から読み直します: \(error)")
                await showFirstPage(force: true, generation: generation, alongsideSnapshot: false)
                return
            }
            // 読んだぶんは残し、札も残す（「もう一度試す」で同じ続きを頼む）
            print("[feed] 続きのページを読めませんでした: \(error)")
            pageFailed = true
        }
    }

    /// 届いた続きを足して書く
    private func apply(_ page: PendingPage) async {
        guard page.serial == pageSerial else { return }
        pageRaw += page.items
        pageIds.formUnion(page.items.map(\.id))
        nextCursor = page.next
        pageFailed = false
        loadedPageCount += 1
        await representPages(loadsRestricted: true)
        guard page.serial == pageSerial else { return }
        if case .loaded = state { state = .loaded(filtered()) }
    }

    /// ホームが画面から外れた（詳細を開いた）。これ以降の続きは戻るまで足さない
    func leaveScreen() {
        isOnScreen = false
    }

    /// ホームに戻ってきた印。**同期で立てる**（画面の `onAppear` から直に呼ぶ）。
    ///
    /// 🔴 `Task` の中で立てると1拍遅れ、戻ってすぐ詳細を開き直した回に `leaveScreen` の後で
    /// 立って印が逆転し、詳細を開いている間に続きを足していた（2026-10-03 のレビュー）
    func markOnScreen() {
        isOnScreen = true
    }

    /// 外れていた間に届いた続き・読み直しを書く。**印は立てない**（`markOnScreen`）——
    /// 待っている間にまた外れていたら何もしない
    func applyPendingPages() async {
        guard isOnScreen else { return }
        if let page = pendingPage {
            pendingPage = nil
            await apply(page)
        } else if pageWriteDeferred {
            pageWriteDeferred = false
            if usesPagedFeed, case .loaded = state { state = .loaded(filtered()) }
        }
    }

    /// `cursor` から読み、**新しい写真が1枚でも入るか、最後に着くまで**続けて読む
    /// （上限 `maxEmptyPageHops`）。空のページ・読んだ写真だけのページは続きを読む
    private func readPages(_ feedPages: PublicFeedService, from cursor: String?,
                           known: Set<String>) async -> Result<([Photo], String?), Error> {
        var seen = known
        var fresh: [Photo] = []
        var cursor = cursor
        do {
            for _ in 0..<Self.maxEmptyPageHops {
                let page = try await feedPages.page(cursor: cursor)
                for photo in page.items where seen.insert(photo.id).inserted {
                    fresh.append(photo)
                }
                cursor = page.nextCursor
                if !fresh.isEmpty || cursor == nil { break }
            }
            return .success((fresh, cursor))
        } catch {
            return .failure(error)
        }
    }

    /// 読んだページに仕上げ（いいねの数・限定公開・編集・ブロック）を掛け直す。
    /// - Parameter loadsRestricted: false なら限定公開は手元の控えだけで重ねる（全件の回と
    ///   同時に走る1ページ目。全件の回が読み終えたら掛け直す）
    private func representPages(loadsRestricted: Bool) async {
        presentSerial += 1
        let serial = presentSerial
        // ページの境目をまたぐ複数枚の投稿は、続きが届くまで出さない（前半だけの束にしない・
        // `PhotoGroups.holdingBackTrailingGroup`）。読んだ印（`pageIds`）には入れたままで、
        // 続きが届くと末尾でなくなり、そろった束で出る
        let raw = PhotoGroups.holdingBackTrailingGroup(pageRaw, hasMore: nextCursor != nil)
        let presented = await gallery.presentFeed(raw, reachedEnd: nextCursor == nil,
                                                  loadsRestricted: loadsRestricted)
        guard serial == presentSerial, pageSource == .pages else { return }
        pagedPhotos = presented
    }

    private func clearPages() {
        pageSerial += 1
        presentSerial += 1
        pageRaw = []
        pageIds = []
        nextCursor = nil
        pagedPhotos = []
        pageFailed = false
        isLoadingPage = false
        loadedPageCount = 0
        pendingPage = nil
        pageWriteDeferred = false
        firstPageTask = nil
        firstPageReadAt = nil
    }

    /// 人が替わった回数。**替わる前に読み始めた回の答えを書かない**ために使う
    private var viewerGeneration = 0

    /// 最後に読み始めたときの、限定公開の読み出し口の回（`restrictedEpoch`）
    private var loadedEpoch: Int?

    /// 人が替わったら呼ぶ。**前の人の一覧を捨てて読み込み中に戻し、読み直す**。
    ///
    /// ホームは一度読んだ一覧を持ち続けるので、捨てないとログアウトや別の人の
    /// ログインのあとも、前の人あての「フォロワーのみ／親しい友達」が並んでいた。
    ///
    /// **未ログイン→ログインでは捨てない**（起動時の確認中→A もここ）。出ていたのは
    /// 公開ぶんだけなので、消して丸に戻すと起動のたびに一覧がちらつく。読み直しだけする
    func switchViewer(from previous: String?, to next: String?) async {
        guard previous != next else { return }
        if previous != nil {
            viewerGeneration += 1
            all = []
            // 読んだページも捨てる（仕上げに前の人の限定公開が重なっている）。次の読み込みで1ページ目から
            clearPages()
            pageSource = .untried
            myPhotos = []
            myPhotosOwner = nil
            myPhotosWanted = next
            state = .loading
            // **前の人の「フォロー中」で絞らない。** 画面はこの読み直しを待ってから
            // 新しい人のフォロー中を渡すので、それまでは空で絞る。
            // nil（まだ取れていない）で渡す——空の集合を「次の人のもの」として
            // 記録すると、次の取得が失敗したとき「まだありません」と言ってしまう（`use`）
            use(viewerId: next, following: nil)
            // **読み出し口がまだ前の人のままなら、ここでは読まない。** 読むと前の人の
            // 限定公開（と控え）を次の人の画面に書く。入れ替わったら画面の
            // `restrictedChanges` が読み直す（入れ替えと人の変化の順は決まっていない）
            guard await gallery.restrictedEpoch != loadedEpoch else { return }
        }
        await load()
    }

    /// **一覧を出している最中に取り消された回は何も書かない。** 戻ると `.task` が走り直し、
    /// 読み終わる前に次の写真を開くと取り消される。失敗の帯はフィードごと差し替え、
    /// 遅れて書いた一覧は並びが変わると段（`EditorialLayout.Row.id` は隣の写真まで含む）を
    /// 作り直す——どちらでも開いたばかりの詳細が閉じる。
    /// **まだ何も出していない回は今までどおり書く**（書かないと、読み込み中の丸のまま
    /// 引き下げも再試行も効かない画面が残る。開いている詳細も無い）
    private var keepsShownFeed: Bool {
        guard Task.isCancelled, case .loaded = state else { return false }
        return true
    }

    /// いま出している一覧。絞り込みを変えたら読み直さずに掛け替える。
    private var all: [Photo] = []

    /// 今日のテーマの背景に使う公開写真（絞り込みの影響を受けない全件）。
    /// **2026-10-03 判断:** 日付で全件から選ぶので `photos.json` の全件のまま（ページにしない）
    var allPhotosForTheme: [Photo] { all }

    /// 自分の写真。**今日のテーマに参加したかの判定に使う。**
    ///
    /// 公開一覧（静的 JSON）ではなく**API から読む**——投稿したばかりの
    /// 写真は再ビルドまで公開一覧に載らないので、公開一覧だけを見ると
    /// 「参加したのに参加済みにならない」が数分続く。
    @Published private(set) var myPhotos: [Photo] = []

    func loadMyPhotos(_ photos: PhotoService, viewerId: String?) async {
        await loadMyPhotos(viewerId: viewerId) { try await photos.myPhotos() }
    }

    /// 取り方を差し替えられる形（試験で答えを待たせる）
    func loadMyPhotos(viewerId: String?, fetch: () async throws -> [Photo]) async {
        myPhotosWanted = viewerId
        guard viewerId != nil else {
            myPhotos = []
            myPhotosOwner = nil
            justPosted = nil
            return
        }
        // 先に足した控えは、この読み直しが**成功・失敗・取り消しのどれで終わっても**手放す
        // （残すと、あとで消した写真が次の読み直しで戻る・`PostedPhotos.keepSeconds`）
        defer { justPosted = nil }
        let fetched = try? await fetch()
        // 取り消された回（ログアウト・人の切り替え）は、遅れて着いた答えを誰にも付けない
        guard !Task.isCancelled else { return }
        // 🔴 **取り消されない回（投稿を閉じた・引き下げ）もある。** 待つ間に別の人
        // （ログアウトを含む）の読みが始まっていたら、前の人の答えを書かない
        guard myPhotosWanted == viewerId else { return }
        if let fetched {
            // 投稿したばかりでまだ索引に無い写真も残す（`showPosted`・id で重複を除く）
            myPhotos = PostedPhotos.merge(loaded: fetched, posted: justPosted?.photos(at: Date()) ?? [],
                                          owner: viewerId)
            myPhotosOwner = viewerId
        } else if myPhotosOwner != viewerId {
            // 取れなかった回は、**同じ人のぶんなら残す**（詳細を開いて取り消された回に
            // 「参加済み」が消えない）。人が替わった回は前の人のぶんを残さない
            myPhotos = []
            myPhotosOwner = nil
        }
    }

    /// 投稿したばかりで、まだ読み直しの結果に合わせていない写真（`PostedPhotos`・2026-10-03）
    private var justPosted: PostedPhotos.Pending?

    /// 投稿画面を閉じた（`TabRouter.lastPosted`）。保存の応答の行を**読み直しの前に**自分の写真へ足す
    /// （今日のテーマの札が、索引の遅れで「参加する」のまま残らないように）。人が替わっていたら何もしない
    /// 控えは次の読み直しが終わったら手放し、`keepSeconds` を過ぎたら使わない（`PostedPhotos.Pending`）
    func showPosted(_ posted: [Photo], viewerId: String?, at now: Date = Date()) {
        guard let viewerId, !posted.isEmpty, myPhotosWanted == nil || myPhotosWanted == viewerId else { return }
        justPosted = PostedPhotos.Pending(photos: posted, receivedAt: now)
        guard myPhotosOwner == viewerId else { return }
        myPhotos = PostedPhotos.merge(loaded: myPhotos, posted: posted, owner: viewerId)
    }

    /// `myPhotos` が誰のものか（`followingOwner` と同じ考え方）
    private var myPhotosOwner: String?
    /// 最後に自分の写真を読みに行った人（人の切り替えでも替える）。
    /// これと違う人の答えは遅れて着いたものなので捨てる
    private var myPhotosWanted: String?

    func select(category: String?) {
        self.category = category
        state = .loaded(filtered())
    }

    func select(scope: GalleryScope) {
        self.scope = scope
        state = .loaded(filtered())
    }

    /// フォローしている人だけ入れ替える。
    ///
    /// **`use(viewerId:following:)` を使い回さない**——あちらは範囲を
    /// 既定へ倒すので、「フォロー中」を選んだ直後に「自分」へ戻ってしまう。
    ///
    /// - Parameters:
    ///   - following: nil は「取れなかった」。**手元の集合は潰さない**
    ///     （前に取れていたぶんで出し続ける。一度も取れていなければ失敗のまま）
    ///   - viewerId: **誰の鍵で取ったか。** `self.viewerId` から取らない——
    ///     `use` が走る前（`.task` が取り消された回）だと nil のままで、
    ///     取れた集合の持ち主が分からなくなり、次の失敗で空に潰される
    ///     **遅れて着いた前の人の集合は、呼ぶ側（画面）が `auth.userId` と見比べて捨てる。**
    ///     ここで `self.viewerId` と比べると、人が替わった直後（`use` がまだの間）に
    ///     今の人の正しい集合まで捨てる。モデルが捨てるのは**もう離れた人**
    ///     （`departedViewerIds`）のぶんだけ——前の人の一覧が次の人の「フォロー中」に入らない
    func refreshFollowing(_ following: Set<String>?, viewerId: String, ticket: Int? = nil) {
        guard let following else { return }
        guard !departedViewerIds.contains(viewerId) else { return }
        guard takesFollowing(ticket, for: viewerId) else { return }
        self.followingIds = following
        followingOwner = viewerId
        followingFailed = false
        if case .loaded = state { state = .loaded(filtered()) }
    }

    /// ログイン状態が決まったら呼ぶ。
    ///
    /// **範囲はいま選んでいるフィードが決める**（指示書のホームは
    /// おすすめ／フォロー中／新着）。以前はここで「自分」へ倒していたが、
    /// それだと**押したフィードが即座に打ち消される**。
    ///
    /// **フォロー中は未ログインだと中身が無い。** 絞れないので
    /// 「おすすめ」へ戻す（空の画面に置き去りにしない）。
    ///
    /// - Parameter following: nil は「取れなかった」。
    ///   - **同じ人の集合が手元にあれば潰さない**（詳細から戻って `.task` が
    ///     走り直した回・取り消された回。潰すと「フォロー中」の一覧が空になり、
    ///     開いた詳細の元のタイルが消えて閉じる）
    ///   - 人が替わった回・一度も取れていない回は、空にして `followingFailed` を立てる
    func use(viewerId: String?, following: Set<String>?, ticket: Int? = nil) {
        // 並びは sort と feed の両方で決まる（`sorted`）。**どちらかが変わったら**並べ直す
        let previousFeed = feed
        setViewer(viewerId)
        // 後から始めた取得の答えがもう入っていたら、この古い答えでは一覧に触らない
        // （「取れなかった」の枝に入れると、A→B→A と戻った回に一覧を空にして失敗を出していた）。
        // 取れなかった答えは番号を進めない——`refreshFollowing` と同じ
        let stale = following != nil && !takesFollowing(ticket, for: viewerId)
        if stale {
            // 一覧はそのまま（並びと範囲だけ下で更新する）
        } else if let following {
            followingIds = following
            followingOwner = viewerId
            followingFailed = false
        } else if viewerId == nil || followingOwner != viewerId {
            followingIds = []
            followingOwner = nil
            followingFailed = viewerId != nil
        }
        if viewerId == nil && feed.needsSignIn { feed = .recommended }
        let previousSort = sort
        scope = feed.scope
        sort = feed.sort
        // **並びが変わったときだけ**並べ直す（同じなら一覧を入れ替えない——
        // 開いている詳細の元のタイルが作り直されて閉じる）
        if sort != previousSort || feed != previousFeed { all = sorted(all) }
        if case .loaded = state { state = .loaded(filtered()) }
    }

    /// フォロー一覧を取りに行く前に呼び、返った番号を `use`・`refreshFollowing` に渡す。
    ///
    /// 🔴 **後から始めた取得の答えを、先に始めた取得の遅れた答えで上書きしない。**
    /// 「フォロー中」を押したとき・引き下げ・`.task` の3か所から取りに行き、順番の札が
    /// 無かったので、先に始めた（古い）一覧が後から着くと新しい一覧を戻していた
    /// （フォローしたばかりの人が「フォロー中」から消える）
    func beginFollowingFetch() -> Int {
        followingFetchSeq += 1
        return followingFetchSeq
    }

    private var followingFetchSeq = 0
    /// いま入っている一覧を取りに行った番号
    private var appliedFollowingSeq = 0

    /// 番号の無い呼び出し（試験・未ログイン）はいつも入れる。入れたら番号を進める。
    /// **比べるのは、いま入っている一覧が同じ人のものなときだけ**——別の人の一覧が入っている
    /// なら、古い番号でもこの人の答えの方が正しい（A→B→A と戻った回に B の一覧を A に残さない）
    private func takesFollowing(_ ticket: Int?, for viewerId: String?) -> Bool {
        guard let ticket else { return true }
        if followingOwner == viewerId, ticket <= appliedFollowingSeq { return false }
        // **max を取らずに置き換える。** 番号は入っている一覧の番号——別の人の新しい番号を
        // 残すと、戻った人の古い答えのあとに着いた同じ人の新しい答えを捨てていた
        appliedFollowingSeq = ticket
        return true
    }

    private func filtered() -> [Photo] {
        let inScope = scope.photos(all, viewerId: viewerId, followingIds: followingIds)
        // **チップは、いまの範囲にある写真から作る。** 全体から作ると
        // 「自分」に切り替えたときに**自分の写真に無いカテゴリ**が並び、
        // 押すと空になる（押しても空になるボタンを置かない）
        categories = Self.categories(in: inScope)
        // 範囲を変えて、選んでいたカテゴリが消えたら絞りも外す
        if let category, !categories.contains(where: { CategoryChoices.isChosen(current: $0, choice: category) }) {
            self.category = nil
            if usesPagedFeed { return pagedPhotos }
            return inScope
        }
        // 「新着」で絞りが無いときは、ページで読んだ並び（`/feed`・2026-10-03）
        if usesPagedFeed { return pagedPhotos }
        guard let category else {
            return PhotoQuery.photos(
                PhotoQuery.photos(inScope, withAllTags: selectedTags),
                matching: query
            )
        }
        // 綴りではなく鍵で比べる（`建築` を押したら `architecture` も出る）
        let key = CategoryChoices.key(category)
        return PhotoQuery.photos(
            PhotoQuery.photos(
                inScope.filter { CategoryChoices.key($0.category ?? "") == key },
                withAllTags: selectedTags
            ),
            matching: query
        )
    }

    /// 出てくる順に、重複を落として並べる。**件数の多い順にしない**
    /// ——並びが日によって変わると、押す場所を覚えられない
    static func categories(in photos: [Photo]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        // **日英を畳んでから数える。** 実データには `architecture` と `建築`、
        // `landscape` と `風景` が両方ある（30枚中の実測）。生の値で
        // 並べると**同じ「建築」のチップが2つ出て、押すと結果も割れる**
        // ——Web は `slugify(_, "category")` で畳んでいる。
        // **代表は最初に出てきた綴り**（どちらを押しても同じ結果になる）
        for category in photos.compactMap(\.category) where !category.isEmpty {
            if seen.insert(CategoryChoices.key(category)).inserted { result.append(category) }
        }
        return result.sorted { Labels.Category.name($0) < Labels.Category.name($1) }
    }

    /// 並びは `GallerySort` に置いてある（画面を持たない層なので
    /// Linux 上の `swift test` で検証できる）。
    /// 🔴 **おすすめは owner が選んだ写真（featured）を先頭に。** 以前は
    /// フィードの札を押したとき（`select(feed:)`）しか `arrange` を通らず、
    /// 起動・引き下げ・ブロック後の読み直しでは新しい順のまま出ていた
    private func sorted(_ photos: [Photo]) -> [Photo] {
        sort == feed.sort ? feed.arrange(photos) : sort.apply(photos)
    }

    /// タグのチップ。**押し直すと外れる**（カテゴリと同じ約束）
    func toggle(tag: String) {
        let key = TagChoices.key(tag)
        if let index = selectedTags.firstIndex(where: { TagChoices.key($0) == key }) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
        state = .loaded(filtered())
    }

    /// 絞り込みに出すタグ。
    ///
    /// **決まった20語だけ**（`TagChoices.all`）。owner の指示:
    /// 「タグみたいなの多すぎる／フィンランドみたいな個別なのは候補に
    /// 置きたくない」。以前は写真に付いている語をそのまま多い順に出して
    /// いたので、`finland`・`helsinki` のような**その旅にしか出てこない
    /// 固有名詞**が候補に並んでいた（次の写真で押す相手ではない）。
    ///
    /// **1枚も無い語は出さない。** 押しても空になるチップを置かない。
    /// **2026-10-03 判断:** 全件（`photos.json`）から作る。読んだページだけから作ると、
    /// 下まで送るたびにチップが増えて並びが動く
    var tags: [String] {
        let present = Set(all.flatMap { $0.tags ?? [] }.map { TagChoices.key($0) })
        return TagChoices.all.filter { present.contains(TagChoices.key($0)) }
    }

    /// フィードを選ぶ。**範囲と並びを一緒に切り替える**。
    ///
    /// **`use(viewerId:following:)` は呼ばない。** あちらは範囲を
    /// 「自分」に倒すので、押したフィードが即座に打ち消される
    /// （組み込んだ直後に踏んだ）。
    func select(feed: HomeFeed, viewerId: String?) {
        self.feed = feed
        self.scope = feed.scope
        self.sort = feed.sort
        // 人が替わっていたら、手元のフォロー一覧は前の人のもの——持ち越さない
        // （`use` の前に取れていた今の人の集合は残す）
        if viewerId != self.viewerId, followingOwner != viewerId {
            followingIds = []
            followingOwner = nil
            // 前の人の「読み込めませんでした／読めた」を持ち越さない。今の人の集合は
            // まだ無い＝`use` と同じく「取れていない」（空の集合で「まだありません」と言わない）
            followingFailed = viewerId != nil
        }
        setViewer(viewerId)
        all = feed.arrange(all)
        state = .loaded(filtered())
        // 「新着」を初めて選んだ回・1ページ目が古い回は `/feed` の1ページ目を読む（おすすめでは読まないので）
        if feed == .latest, feedPages != nil, pageSource == .untried || firstPageIsStale {
            pagesTask = Task { await self.loadPagesIfNeeded() }
        }
    }

    func select(sort: GallerySort) {
        self.sort = sort
        all = sort.apply(all)
        state = .loaded(filtered())
    }

    /// トップに出す「おすすめ」。**絞り込みが掛かっているときは出さない**
    /// ——絞った結果の上に別の並びが出ると、何を見ているのか分からなくなる。
    ///
    /// **「おすすめ」の札のときだけ出す**（owner の判断 2026-09-27）。全員の写真から
    /// 作る段なので、「フォロー中」ではフォローしていない人の写真が
    /// 「フォロー中の人の写真はまだありません」の上に並んでいた
    /// **2026-10-03 判断:** owner が選んだ写真は日付を問わず全件から拾うので `photos.json` のまま
    var featured: [FeaturedGroups.Group] {
        guard category == nil, feed == .recommended else { return [] }
        return FeaturedGroups.groups(from: all)
    }
}
