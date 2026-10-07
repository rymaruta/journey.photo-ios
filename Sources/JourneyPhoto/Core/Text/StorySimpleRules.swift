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

    // MARK: - 色の丸（4つ）

    /// キーボードの上に出す4色（白・墨・真鍮・空色）。残りの8色と好きな色は「ほかの色」から
    static let quickInks: [TextOverlay.Ink] = [.white, .ink, .brass, .sky]

    /// いまの札で出す丸。**背景無しは4つとも**（墨を選ぶと黒の見た目に移る）。
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
