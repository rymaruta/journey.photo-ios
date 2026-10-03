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

    init(gallery: PublicGalleryService = PublicGalleryService()) {
        self.gallery = gallery
    }

    /// 画面が出たら、環境が持っている1つに繋ぎ直す。
    func use(gallery: PublicGalleryService) {
        self.gallery = gallery
    }

    /// - Parameter force: 控えを無視して取り直す（引き下げ更新）。
    func load(force: Bool = false) async {
        // 再読み込みのときに画面を空にしない（読み込み中の白画面を挟まない）
        if case .loaded = state {} else { state = .loading }
        let generation = viewerGeneration
        loadSerial += 1
        let mine = loadSerial
        // 引き下げ（force）の回は、走っている間だけ覚える（`writes` の3つ目）
        if force { runningForced.insert(mine) }
        defer { runningForced.remove(mine) }
        loadedEpoch = await gallery.restrictedEpoch
        do {
            let photos = try await gallery.fetchPhotos(force: force)
            guard writes(mine, force: force, generation: generation) else { return }
            all = sorted(photos)
            state = .loaded(filtered())
        } catch {
            guard writes(mine, force: force, generation: generation) else { return }
            state = .failed((error as? APIError)?.errorDescription ?? Labels.Common.loadFailed)
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
    private func writes(_ serial: Int, force: Bool, generation: Int) -> Bool {
        guard !keepsShownFeed, generation == viewerGeneration, serial > lastWrittenSerial else { return false }
        if !force, runningForced.contains(where: { $0 < serial }) { return false }
        lastWrittenSerial = serial
        return true
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

    /// 今日のテーマの背景に使う公開写真（絞り込みの影響を受けない全件）
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
            return inScope
        }
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
    var featured: [FeaturedGroups.Group] {
        guard category == nil, feed == .recommended else { return [] }
        return FeaturedGroups.groups(from: all)
    }
}
