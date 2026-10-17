import Foundation

/// ストーリー作成「かんたん版」の決まり（owner・2026-10-02 に候補を見て「めっちゃいい」）。
///
/// 画面（`StoryComposerView`・`StoryTextTypingView`）から**判断だけ**を出して試せるようにしたもの。
/// 文字のデータの型（`TextOverlay` の書体・色・見た目・大きさ）と保存は今のまま——ここは
/// **既存の値のどれへ移すか**を決めるだけ。
enum StorySimpleRules {

    // MARK: - 写真を選ぶ画面の「次へ」

    /// 写真を選ぶ画面の下の白い主ボタン
    struct NextButton: Equatable {
        let title: String
        let enabled: Bool
    }

    /// 「次へ（N枚）」。**0枚なら押せず「写真を選んでください」**。
    /// 読み込みの最中も押せない（2本の読み込みが混ざって並んだ・既存の `loadingPicks` の決まり）
    static func nextButton(selected: Int, loading: Bool) -> NextButton {
        guard selected > 0 else {
            return NextButton(title: L("写真を選んでください", "Choose photos"), enabled: false)
        }
        return NextButton(title: L("次へ（\(selected)枚）", "Next (\(selected))"), enabled: !loading)
    }

    // MARK: - 裏に回ったときの自動の書きかけ（2026-10-16）

    /// 裏に回ったときに自動の書きかけ（`StoryDraftStore.Slot.auto`）をどうするか
    enum AutoSave: Equatable {
        /// 書く（並べた写真と置いた文字を残す）
        case write
        /// 前の分を消す（写真を全部外した——次に開いて外した写真が蘇らない）
        case clear
        /// 何もしない（読み込み中。読みかけの写真が落ちた書きかけを作らない・前の分は残す）
        case skip
    }

    /// 写真が無ければ書かない（何も書いていない）。読み込み中は触らない
    static func autoSave(hasShots: Bool, loading: Bool) -> AutoSave {
        if loading { return .skip }
        return hasShots ? .write : .clear
    }

    /// ✕ を押したときにどうするか（`UnsavedLeave` から）
    enum Close: Equatable {
        /// 確かめずに閉じ、**自動の書きかけも消す**（写真を全部外した・戻した下書きから何も変えていない）
        case closeClearingAutoDraft
        /// 閉じる確認を出す（「下書きに保存」「保存せずに閉じる」。どちらも自動の書きかけを消す）
        case confirm
        /// 閉じない
        case stay
    }

    /// 🔴 **2026-10-16 判断: 変更なし（`.now`）で閉じる道でも自動の書きかけを消す。** 以前は写真を全部外して
    /// ✕ で閉じると消さず、次に開くと外した写真が「書きかけの続き」で戻った。変更なしで閉じるのは
    /// 写真が無い（残すものが無い）か、戻した本人の下書きのまま（同じものが本人の下書きに残る）のどちらかなので、
    /// 自動の枠に残す理由が無い。この画面が触ってよい枠か（`ownsAutoSlot`）は消す側が見る
    static func close(_ leave: UnsavedLeave) -> Close {
        switch leave {
        case .now: return .closeClearingAutoDraft
        case .confirm: return .confirm
        case .wait: return .stay
        }
    }

    /// この画面が自動の枠に触って（書いて・消して）よいか。開いたとき空だった・この画面で尋ねたときだけ
    /// ——尋ねていない書きかけ（送れなかった問いが先に出た・写真を持って開いた回）を黙って上書き・削除しない
    static func ownsAutoSlot(hasAutoDraft: Bool, asked: Bool) -> Bool {
        !hasAutoDraft || asked
    }

    /// 自動の書きかけが、いまの本人の下書きを開いて書いていたものか（`StoryDraftStore.Draft.basedOn`）。
    /// そうなら続きから出したとき元の下書きも片づける（同じ写真が二度出ない）
    static func autoRestoreContinuesSaved(basedOn: String?, savedStamp: String?) -> Bool {
        guard let basedOn else { return false }
        return basedOn == savedStamp
    }

    // MARK: - 選んだ写真の読み込み

    /// ライブラリの写真1枚を読むのを待つ上限（秒）。過ぎたら「読めなかった」に回す。
    ///
    /// 🔴 **2026-10-07 判断: 投稿の写真（`UploadViewModel.pickedLoadTimeout`）と同じ 60 秒。**
    /// iCloud にしか無い写真は数十秒かかることがあり、短いと読める写真まで落とす。
    /// 上限が無いと、返らない1枚のために読み込み中（`loadingPicks`）が解けず、
    /// 「シェアする」・並びの「＋」・カメラが止まったままだった（閉じて開き直すまで）
    static let pickLoadTimeout: TimeInterval = 60

    /// 選んだ写真を順に読み、読めたものを `accept` に渡す。**1枚ごとに上限時間を設ける**
    /// （`AsyncTimeout.firstWithin`——取り消しに応えない読み込みでも時間切れが効く。
    /// 呼んだ側が取り消されたときもすぐ戻る）。
    ///
    /// - Returns: 読めなかった（時間切れ・失敗・取り消し）枚数
    @MainActor
    static func readPicks<Item>(_ items: [Item], timeout: TimeInterval = pickLoadTimeout,
                                read: @escaping (Item) async throws -> Data?,
                                accept: (Data) async -> Void) async -> Int {
        var failed = 0
        for item in items {
            // nil は時間切れ・取り消し・読めなかった
            let data = await AsyncTimeout.firstWithin(seconds: timeout) { () async -> Data? in
                try? await read(item)
            }
            if let data {
                await accept(data)
            } else {
                failed += 1
            }
        }
        return failed
    }

    // MARK: - カメラ・並びの帯

    /// 写真を選ぶ段でカメラを撮ったとき、**撮った1枚より先に読み込む印付きの写真**。
    /// まだ1枚も入っていない（写真を選ぶ段）ときだけ。仕上げる段のカメラは足すだけ
    static func picksToLoadBeforeCamera<Item>(_ selection: [Item], hasShots: Bool) -> [Item] {
        hasShots ? [] : selection
    }

    /// 写真を選ぶ段のカメラを押せるか。**印が上限（`StoryQueue.maxShots`）まで付いていれば押せない**
    /// ——印の写真を先に読み込むので、撮った1枚が上限で入らず失われる
    static func canUseCameraOnPickStage(selected: Int) -> Bool {
        selected < StoryQueue.maxShots
    }

    /// 並びの帯の「この写真を外す」を通すか。**読み込み中は止める**（全部外れて写真を選ぶ段へ戻り、
    /// 届いた写真でまた仕上げる段へ、と段が行き来する）
    static func canRemoveShot(loading: Bool) -> Bool {
        !loading
    }

    // MARK: - 書体（「Aa 明朝」のボタン）

    /// 押すたびに回る順。**明朝 → ゴシック → 手書き風 → …（残りの5つ）→ 明朝**。
    /// 候補の見本は 明朝・ゴシック・手書き風 の3つだが、2026-09-29 に owner の「フォントの種類が少ない」で
    /// 足した5つを選べなくすると後戻りになるので、3つの後ろに並べる（`Face.allCases` と同じ順）
    static let faceCycle: [TextOverlay.Face] = TextOverlay.Face.allCases

    /// 書体を次へ。書体を持たない札（スタンプ）は変えない
    static func nextFace(_ overlay: TextOverlay) -> TextOverlay {
        guard overlay.kind.hasTypography else { return overlay }
        var next = overlay
        let i = faceCycle.firstIndex(of: overlay.face) ?? -1
        next.face = faceCycle[(i + 1) % faceCycle.count]
        return next
    }

    // MARK: - 背景（無し → 帯 → 縁取り）

    /// キーボードの上の「背景」ボタンが見せる段。データの見た目（`TextOverlay.Style`）の4つを3つに畳む:
    /// 白（影）と黒（白い縁）は**どちらも「背景無し」**で、どちらになるかは色で決める（`choose`）
    enum Backdrop: Equatable {
        case none, banner, outline

        var label: String {
            switch self {
            case .none: return L("背景なし", "No background")
            case .banner: return L("帯", "Banner")
            case .outline: return L("縁取り", "Outline")
            }
        }
    }

    static func backdrop(of style: TextOverlay.Style) -> Backdrop {
        switch style {
        case .light, .dark: return .none
        case .banner: return .banner
        case .outline: return .outline
        }
    }

    /// 背景を次へ（無し → 帯 → 縁取り → 無し）。候補の見本は 無し ⇄ 帯 だが、縁取り（2026-09-29 に
    /// owner の「自由度が低い」で足したもの）を無くさないよう3つで回す。
    /// 色の寄せ方は既存の `TextOverlay.withStyle`。**帯で固定の札とスタンプは変えない**
    static func nextBackdrop(_ overlay: TextOverlay) -> TextOverlay {
        guard overlay.kind.forcedStyle == nil else { return overlay }
        switch backdrop(of: overlay.style) {
        case .none: return overlay.withStyle(.banner)
        case .banner: return overlay.withStyle(.outline)
        case .outline: return overlay.withStyle(.light)
        }
    }

    // MARK: - 色の丸（5つ）

    /// キーボードの上に出す5色（板 v2 `StoryComposerText`: 白・黒（墨）・真鍮・空色・珊瑚）。
    /// 残りの7色と好きな色は「ほかの色」から。
    ///
    /// 2026-10-16 判断: 珊瑚を「ほかの色」の奥から前へ出した（板 v2 の5色）。
    /// **真鍮は文字の色として残す。** CLAUDE.md の「真鍮は黒い地の上だけ」は UI の部品（合図・リンク・
    /// 選んでいるもの）の決まりで、ここは使う人が自分の写真に載せる文字の色（板 v2 も5色に置いている・
    /// 2026-10-02 のかんたん版から既に出ていた）。背景無しでも影（`.light`）が付き、帯は背景ボタン1回で
    /// 付く。**帯を前提に縛ることはしていない**（真鍮を選んでも背景は変えない）——写真によっては
    /// 読みにくいので、縛るかは owner に尋ねる
    static let quickInks: [TextOverlay.Ink] = [.white, .ink, .brass, .sky, .coral]

    /// いまの札で出す丸。**背景無しは5つとも**（墨を選ぶと黒の見た目に移る）。
    /// 帯・縁取りでは読めない墨を出さない（`TextOverlay.inks(for:)` と同じ決まり）
    static func inks(for overlay: TextOverlay) -> [TextOverlay.Ink] {
        guard overlay.kind.forcedStyle != nil || backdrop(of: overlay.style) != .none else { return quickInks }
        let allowed = TextOverlay.inks(for: overlay.style)
        return quickInks.filter { allowed.contains($0) }
    }

    /// 丸で選んでいる色か（好きな色を選んでいれば、どれも選んでいない）
    static func isSelected(_ ink: TextOverlay.Ink, in overlay: TextOverlay) -> Bool {
        overlay.customHex == nil && overlay.drawnInk == ink
    }

    /// 丸を押した。**背景無しで墨を選ぶと黒の見た目（墨の字に白い縁）、他の色は白の見た目（影）**
    /// ——写真の上で墨の字を読めるのは白い縁の方。好きな色は外す（12色から選び直したのと同じ）
    static func choose(_ ink: TextOverlay.Ink, for overlay: TextOverlay) -> TextOverlay {
        var next = overlay
        if overlay.kind.forcedStyle == nil, backdrop(of: overlay.style) == .none {
            next.style = ink == .ink ? .dark : .light
        }
        next.ink = ink
        next.customHex = nil
        return next
    }
}
