import XCTest

/// **撮影地の欄（`PlaceSearchField`）の候補の行の当たりが 44pt あり、隣の行と重ならないか**（2026-11-15・人間工学の点検）。
///
/// 候補の行は字（12pt）の行で、当たりは縦に 22pt しかなかった（決まりは 44pt。見た目は大きくせず当たりだけ広げる）。
/// 見本の1枚の投稿画面（`-JPPreviewUploadSample`・端末の中の通信）で撮影地の欄に「神社」などと打ち、撮影スポットの候補を出して、
/// **行の真ん中から上下にずらした所を実際に押し**、どの行が選ばれたか（欄に入った名前）で当たりの広さを測る。
/// 読み上げの枠（`frame`）は当たり（`contentShape`）と一致するとは限らないので、押して確かめる。
///
/// 数は `PLACEHIT …` の行でログに出す（Mac の `xcodebuild-full.log`）:
/// - `frames`: 候補の行の読み上げの枠と行の間隔
/// - `probe row=<i> dy=<ずらした量> -> self|row<j>|none`: 押した結果
/// - `extent row=<i> up=<上へ届いた量> down=<下へ届いた量>`: 自分の行が選ばれた一番遠い所
///
/// **確かめること（2026-11-15 判断・run 1355・1360 の数から）**: 行は 44pt おきに並び（`pitch`）、どの行も真ん中から上 21pt・下 16pt までは
/// 自分の行が選ばれる。真ん中から下 20・21pt（当たりの境目＝真ん中から 22pt の手前）は、自分の行か下の行のどちらかならよい（押して何も起きない所が無い）。
/// 測った数: 直した後は2回とも上 21・下 16 が自分の行（run 1360 では下 17〜20 も自分の行）。下 21 は下の行が選ばれ、
/// 下に行の無い3行目の下 21 は自分の行だった（当たりは 44pt あり、境目の 1pt 手前だけ下の行に取られる）。
/// 直す前（run 1353）は行が 22pt おきで、下 8pt で下の行が選ばれた
final class PlaceSuggestionHitTests: JPUITestCase {

    private static let previewUserId = "67d49a68-80f1-7083-b0e0-c767886ef868"
    /// 撮影スポットの名前に多い語。2件以上の候補が出るものを前から使う
    private static let queries = ["神社", "公園", "寺", "城"]
    /// 押す所（行の真ん中からのずれ・pt）。自分の行が選ばれなければならない所
    private static let offsets: [CGFloat] = [-21, -16, -8, 8, 16]
    /// 下の行との境目の手前（数だけ取る。自分の行か下の行のどちらか）
    private static let boundaryOffsets: [CGFloat] = [20, 21]
    private static let spotPrefix = "観光スポット "
    /// 押せるものの大きさの決まり（`WebTheme.minTapTarget`。UI テストからはアプリの型を読めないので写す）
    private static let minTapTarget: CGFloat = 44

    override func setUp() {
        continueAfterFailure = true
        // 1か所押すたびに打ち直すので 15 か所で約 4 分かかる。既定の 5 分の上限に近いので 10 分にする（run 1360 で 18 か所が 5 分を越えた）
        executionTimeAllowance = 600
    }

    func testPlaceSuggestionRowsHave44ptHitAreaWithoutOverlap() {
        guard let app = openUpload() else { return XCTFail("投稿の画面（見本の1枚）まで行けない") }
        let field = app.textFields["upload.place"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "撮影地の欄が無い")
        raise(field, in: app)

        guard let query = showCandidates(app, field) else {
            return XCTFail("撮影地の欄に打っても撮影スポットの候補が2件以上出ない（\(Self.queries)）")
        }
        var rows = candidates(app)
        logFrames(app, rows, field)
        let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : .greatestFiniteMagnitude
        XCTAssertLessThan(rows[1].frame.maxY, keyboardTop, "候補の2行目がキーボードの裏にある（押せない）")

        // 1行目と2行目を、真ん中から上下にずらして押す
        var extents: [Int: (up: CGFloat, down: CGFloat)] = [0: (0, 0), 1: (0, 0)]
        var results: [String: String] = [:]
        // 3行目があれば、その下 21（下に撮影スポットの候補の行が無い所）も数だけ取る
        let lastIndex = rows.count >= 3 ? 2 : nil
        var plan: [(index: Int, dy: CGFloat)] = (0..<2).flatMap { index in
            (Self.offsets + Self.boundaryOffsets).map { (index, $0) }
        }
        if let lastIndex { plan.append((lastIndex, 21)) }
        for (index, dy) in plan {
            rows = candidates(app)
            guard rows.count > index else { break }
            let names = rows.map(\.name)
            let target = rows[index].frame
            let point = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: target.minX + min(40, target.width / 2), dy: target.midY + dy))
            point.tap()
            Thread.sleep(forTimeInterval: 0.8)
            let value = (field.value as? String) ?? ""
            let result: String
            if let picked = names.firstIndex(of: value) {
                result = picked == index ? "self" : "row\(picked)"
            } else {
                result = "none"
            }
            results["\(index)|\(Int(dy))"] = result
            log("probe row=\(index) dy=\(Int(dy)) -> \(result) value=\(value)")
            if result == "self" {
                var e = extents[index] ?? (0, 0)
                if dy < 0 { e.up = max(e.up, -dy) } else { e.down = max(e.down, dy) }
                extents[index] = e
            }
            if value != query {
                // 選ばれたら、打ち直して候補を出し直す
                guard retype(app, field, query) else { return XCTFail("打ち直しても候補が出ない（\(query)）") }
            }
        }
        for index in 0..<2 {
            let e = extents[index] ?? (0, 0)
            log("extent row=\(index) up=\(Int(e.up)) down=\(Int(e.down)) height>=\(Int(e.up + e.down))")
        }

        // 行は 44pt おきに並ぶ（直す前は 22pt おき）
        let pitch = rows.count >= 2 ? rows[1].frame.midY - rows[0].frame.midY : 0
        XCTAssertGreaterThanOrEqual(pitch, Self.minTapTarget - 0.5, "候補の行の間隔が \(pitch)pt（44pt おきに並ばない）")
        // 真ん中から上 21・下 16 までは自分の行。2行目の上 21 は1行目の真ん中から下 23 なので、1行目の当たりが2行目へはみ出していない
        for index in 0..<2 {
            for dy in Self.offsets {
                XCTAssertEqual(results["\(index)|\(Int(dy))"], "self",
                               "候補の \(index + 1) 行目の真ん中から \(Int(dy))pt の所を押すと \(results["\(index)|\(Int(dy))"] ?? "-") が選ばれる（当たりが 44pt 無い・重なる）")
            }
            // 境目の手前は、自分の行か下の行（押して何も起きない所が無い）
            for dy in Self.boundaryOffsets {
                let result = results["\(index)|\(Int(dy))"]
                XCTAssertTrue(result == "self" || result == "row\(index + 1)",
                              "候補の \(index + 1) 行目の真ん中から \(Int(dy))pt の所を押すと \(result ?? "-")（自分の行か下の行のはず）")
            }
        }
    }

    // MARK: - 道具

    private struct Row {
        let name: String
        let frame: CGRect
    }

    /// 撮影スポットの候補の行（上から）。名前は読み上げの「観光スポット <名前>、<地域>」から取る
    private func candidates(_ app: XCUIApplication) -> [Row] {
        let buttons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Self.spotPrefix))
        return buttons.allElementsBoundByIndex.compactMap { button -> Row? in
            guard button.exists else { return nil }
            let rest = button.label.dropFirst(Self.spotPrefix.count)
            let name = rest.split(separator: "、", maxSplits: 1).first.map(String.init) ?? String(rest)
            return Row(name: name, frame: button.frame)
        }
        .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// 候補が2件以上出るまで、語を替えて打つ。出た語を返す
    private func showCandidates(_ app: XCUIApplication, _ field: XCUIElement) -> String? {
        for query in Self.queries where retype(app, field, query) {
            return query
        }
        return nil
    }

    /// 欄を空にして `query` を打ち、候補が2件以上出るまで待つ
    private func retype(_ app: XCUIApplication, _ field: XCUIElement, _ query: String) -> Bool {
        guard waitForFocus(field) else { return false }
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(query)
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if candidates(app).count >= 2 {
                // キーボード・候補の並びが落ち着くまで
                Thread.sleep(forTimeInterval: 1)
                return candidates(app).count >= 2
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func logFrames(_ app: XCUIApplication, _ rows: [Row], _ field: XCUIElement) {
        let pitches = zip(rows, rows.dropFirst()).map { Int(($1.frame.midY - $0.frame.midY).rounded()) }
        log("frames field=\(field.frame) keyboard=\(app.keyboards.firstMatch.exists ? "\(app.keyboards.firstMatch.frame)" : "none")"
            + " rows=\(rows.map { "\($0.name)@\($0.frame)" }) pitch=\(pitches)")
    }

    /// 欄を画面の上の方へ送る（下に候補の行が3つ出る場所を空ける）
    private func raise(_ field: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let start = field.frame
        var pushes = 0
        // run 1511（2026-11-18・案 B1 で投稿の画面が全画面になった後）: 1回の送り（画面の 20%）で欄が y=85 まで上がり、
        // 上のバーの裏に入って押せず（`isHittable` が偽のまま 4 語×8 秒）、語を打てずに落ちた。
        // run 1360 では送ったあと y=205 で押せていた。送りを 10% に細かくし、上がりすぎたら少し戻す
        while field.exists, field.frame.minY > window.height * 0.3, pushes < 12 {
            let before = field.frame.minY
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            pushes += 1
            if abs(field.frame.minY - before) < 1 { break }
        }
        var backs = 0
        while field.exists, !field.isHittable, backs < 3 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
            from.press(forDuration: 0.05, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            backs += 1
        }
        log("raised start=\(start) field=\(field.frame) hittable=\(field.isHittable) pushes=\(pushes) backs=\(backs) window=\(window)")
    }

    private func openUpload() -> XCUIApplication? {
        let app = XCUIApplication.jp()
        app.launchArguments += ["-legal.consent.version", "0"]
        app.launchArguments += ["-JPSiteBaseURL", "https://journey-photo.com"]
        app.launchArguments += ["-JPUserApiBaseURL", "https://gu7kxwdc5l.execute-api.ap-northeast-1.amazonaws.com"]
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-JPPreviewUserId", Self.previewUserId]
        app.launchArguments += ["-foundingGift.done.\(Self.previewUserId)", "YES"]
        app.launchArguments += ["-JPPreviewLocalBackend", "YES", "-JPPreviewUploadSample", "YES"]
        app.launch()
        let agree = app.buttons["legal.agree"]
        if agree.waitForExistence(timeout: 60) { agree.tap() }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 20), tabBar.buttons.count > 2 else { return nil }
        tabBar.buttons.element(boundBy: 2).tap()
        // 2026-11-18（案 B1）: 下の「投稿」で写真の一覧が開き、見本の1枚（`-JPPreviewUploadSample`）はそのまま欄の段に入る
        // （前の選ぶシートの「写真を投稿」を押す手は無くなった）
        guard app.buttons["upload.thumb.0"].firstMatch.waitForExistence(timeout: 60) else { return nil }
        // 写真の位置から撮影地を引く・撮影スポットの索引を読む間を待つ
        Thread.sleep(forTimeInterval: 3)
        return app
    }

    /// 欄そのものの焦点（非公開の属性なので在るときだけ読む。読めない環境ではキーボードが出ているか）
    private func waitForFocus(_ field: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let app = XCUIApplication.jp()
        func focused() -> Bool {
            if field.responds(to: NSSelectorFromString("hasKeyboardFocus")) {
                return (field.value(forKey: "hasKeyboardFocus") as? Bool) == true
            }
            return app.keyboards.firstMatch.exists
        }
        // 右の端を押す（真ん中を押すと字の途中に入り、消す字が残る）
        func tapEnd() { field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        if !focused(), field.isHittable { tapEnd() }
        let deadline = Date().addingTimeInterval(timeout)
        while !focused(), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            if !focused(), field.isHittable { tapEnd() }
        }
        return focused()
    }

    private func log(_ line: String) {
        print("PLACEHIT \(line)")
    }
}
