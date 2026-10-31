import XCTest
@testable import JourneyPhoto

/// 🔴 **画面が判定の関数につながっていること**（2026-10-02 のレビュー）。
///
/// 判定（`StoryPlayback.timeUp`・`StoryReel.faceLook`・`PhotoMapView.listEmpty` …）は
/// それぞれの試験で縛っているが、**画面側のつなぎを外しても**それらは通ったままになる。
/// 画面は Linux で描けないので、ソースに**つなぎの呼び出しが残っていること**を見る。
/// 書き方を変えたら、ここも合わせて直す（消したら落ちるのが目的）
final class ScreenWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// 読み上げ: 自動で送らない判定に読み上げの状態を渡す・操作を出す
    func testStoryViewerWiresVoiceOver() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("@Environment(\\.accessibilityVoiceOverEnabled)"))
        XCTAssertEqual(count("voiceOver: voiceOverOn", in: viewer), 2,
                       "時計（timeUp）と動画の終わり（mediaEnded）の両方に読み上げの状態を渡していない")
        XCTAssertTrue(viewer.contains(".onChange(of: voiceOverOn) { _, _ in settlePendingEnd() }"),
                      "読み上げを切っても控えた動画の終わりで進まない")
        XCTAssertTrue(viewer.contains(#".accessibilityAction(named: L("次へ", "Next")) { forward() }"#))
        XCTAssertTrue(viewer.contains(#".accessibilityAction(named: L("前へ", "Previous")) { voiceOverBack() }"#))
        XCTAssertTrue(viewer.contains("StoryPlayback.voiceOverPrevious("))
        XCTAssertTrue(viewer.contains(".accessibilityAction(.escape)"))
        XCTAssertEqual(count("StoryPlayback.forward(", in: viewer), 1)
        XCTAssertTrue(viewer.contains(".onTapGesture { forward() }"),
                      "右を押したときと読み上げの「次へ」が別の判定になっている")
    }

    /// 動きを減らす: 面の見せ方は `faceLook` の答えだけで描く
    func testStoryReelWiresReduceMotion() throws {
        let reel = try source("Features/Stories/StoryReelView.swift")
        XCTAssertTrue(reel.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(reel.contains("StoryReel.faceLook(minX: minX, width: width, reduceMotion: reduceMotion)"))
        XCTAssertTrue(reel.contains(".rotation3DEffect(.degrees(look.angle)"))
        XCTAssertTrue(reel.contains(".offset(x: look.offsetX)"))
        XCTAssertTrue(reel.contains(".opacity(look.opacity)"))
        XCTAssertFalse(reel.contains("StoryReel.cubeAngle("), "faceLook を通らずに回している")
        // ばねは「動きを減らす」を見る1か所（settleAnimation）だけ
        XCTAssertEqual(count(".spring(", in: reel), 1, "ばねを settleAnimation の外で使っている")
        XCTAssertTrue(reel.contains("reduceMotion ? .easeOut(duration: 0.2) : .spring("))
    }

    /// 地図のリスト: 空と失敗を `listEmpty` で分けている
    func testMapListWiresListEmpty() throws {
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertTrue(map.contains("switch Self.listEmpty(loadFailed: model.loadFailed, photosEmpty: model.photos.isEmpty,"))
    }

    /// ログアウト: メニューと設定の両方が共有の印（`AuthStore.startSigningOut`）を通る
    func testSignOutButtonsShareTheGate() throws {
        for path in ["Features/Common/SiteMenuView.swift", "Features/Settings/SettingsView.swift"] {
            let screen = try source(path)
            XCTAssertTrue(screen.contains("auth.startSigningOut {"), "\(path) が共有の印を通らずにログアウトしている")
            XCTAssertFalse(screen.contains("await auth.signOut()"), "\(path) が直にログアウトしている")
        }
    }

    /// ストーリー: 選んだ写真は上限時間つきで読む（`StorySimpleRules.readPicks`）
    func testStoryComposerReadsPicksWithTimeout() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("StorySimpleRules.readPicks("), "上限時間を通らずに写真を読んでいる")
        XCTAssertEqual(count("loadTransferable(", in: composer), 1, "readPicks の外で写真を読んでいる")
    }

    /// 🔴 ストーリー: 埋め込みの写真選びは**印を付けた瞬間に選択を渡す**（`.continuousAndOrdered`）。
    /// 「追加」を止めた（`.selectionActions`）まま `.ordered` にすると、選択が一度も渡らず
    /// 「次へ」が押せないまま（2026-10-09・owner の報告。Mac の run 364 で再現）
    func testStoryInlinePickerDeliversSelectionContinuously() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains(".photosPickerDisabledCapabilities(.selectionActions)"))
        XCTAssertTrue(composer.contains("selectionBehavior: .continuousAndOrdered"),
                      "「追加」を止めた埋め込みの写真選びが、選択を渡さない")
        XCTAssertFalse(composer.contains("selectionBehavior: .ordered"),
                       "「追加」を押した時にしか選択を渡さない形が残っている")
    }

    /// ストーリー: 閉じる確認の「下書きに保存」は読み込み中を見る（`leaveDialog`）
    func testStoryComposerLeaveDialogSeesLoading() throws {
        let composer = try source("Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("canSave: leaveDialog.canSave"))
        XCTAssertTrue(composer.contains("loading: loadingPicks > 0"))
        XCTAssertTrue(composer.contains("if let blocked = Self.draftSaveBlockedNote(loading: loadingPicks > 0) {"),
                      "読み込み中の下書き保存が黙って戻る")
    }

    /// 写真詳細: 吹き出しの数と読み上げは見出しと同じ `visibleCommentCount`（ブロックした人の分を引く・2026-10-07）
    func testPhotoDetailBubbleCountMatchesHeading() throws {
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains(#"actionLabel(systemImage: "bubble.right", count: visibleCommentCount)"#),
                      "吹き出しの数がサーバーの総数のまま（見出しと食い違う）")
        XCTAssertEqual(count("CommentsHeading.label(commentCount: visibleCommentCount)", in: detail), 2,
                       "吹き出しの読み上げと見出しが同じ数を読まない")
        XCTAssertFalse(detail.contains("commentCount: model.commentCount"), "ブロックした人の分を含む数を出している")
        XCTAssertFalse(detail.contains("count: model.commentCount"), "ブロックした人の分を含む数を出している")
    }

    /// ストーリーの反応: 数はブロックした人を落としてから数える（一覧と合わせる・2026-10-07）
    func testStoryInsightsCountsDropBlockedPeople() throws {
        let insights = try source("Features/Stories/StoryInsightsView.swift")
        XCTAssertTrue(insights.contains("viewersLoaded ? dropped.viewers(viewers).count : nil"))
        XCTAssertTrue(insights.contains("repliesLoaded ? dropped.replies(replies).reactionCount : nil"))
        XCTAssertTrue(insights.contains("repliesLoaded ? dropped.replies(replies).textReplies.count : nil"))
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        XCTAssertEqual(count("viewers = BlockFilter.viewers(loaded, blocked: hidden.blockedUserIds)", in: viewer), 1,
                       "見た人の数・顔がブロックした人を含む")
        XCTAssertEqual(count("replies = BlockFilter.replies(loaded, blocked: hidden.blockedUserIds)", in: viewer), 2,
                       "初めの読み込みと読み直しの両方で返信を落としていない")
        XCTAssertFalse(viewer.contains("viewers = loaded"))
        XCTAssertFalse(viewer.contains("replies = loaded"))
    }

    /// ストーリーの返信の一覧・反応の一覧を閉じたら、**見た人と返信の両方**からブロックした人を落とす。
    /// 返信の一覧でブロックしても見た人を落とさず、「見た人 N」に数えたままだった（2026-10-07 のレビュー）
    func testStorySheetsDropBlockedViewersAndRepliesOnDismiss() throws {
        let viewer = try source("Features/Stories/StoryViewerView.swift")
        for sheet in ["showReplies", "showInsights"] {
            let head = ".sheet(isPresented: $\(sheet), onDismiss: {"
            let parts = viewer.components(separatedBy: head)
            XCTAssertEqual(parts.count, 2, "\(sheet) のシートが見つからない（書き方を変えたらここも直す）")
            guard parts.count == 2, let end = parts[1].range(of: "}) {") else { continue }
            let dismiss = String(parts[1][..<end.lowerBound])
            XCTAssertTrue(dismiss.contains("viewers = BlockFilter.viewers(viewers, blocked: hidden.blockedUserIds)"),
                          "\(sheet) を閉じたとき、ブロックした人が「見た人」に残る")
            XCTAssertTrue(dismiss.contains("replies = BlockFilter.replies(replies, blocked: hidden.blockedUserIds)"),
                          "\(sheet) を閉じたとき、ブロックした人の返信が残る")
        }
    }

    /// 写真詳細の撮影地の行: 開いた写真を一覧に渡す。共有は並ぶ写真で URL を決める（2026-10-07）
    func testPlaceRowPassesOpenedPhotoAndShareSeesPhotos() throws {
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("TagPhotosView(kind: .location(location), opened: shown)"),
                      "下書き・限定写真から開くと空の一覧になる")
        let tag = try source("Features/Gallery/TagPhotosView.swift")
        XCTAssertTrue(tag.contains("CollectionScreen.withOpened(PhotoQuery.photos(all, in: kind), opened: opened, kind: kind)"))
        XCTAssertFalse(tag.contains("onAppear { photos = hidden.visible(photos) }"),
                       "タグ一覧が戻るスワイプ途中で photos を即絞っている")
        let screen = try source("Features/Gallery/CollectionPhotosScreen.swift")
        XCTAssertTrue(screen.contains("photos: shown)"), "共有の URL を並ぶ写真で決めていない")
        XCTAssertTrue(screen.contains("FrontConfirm"), "色・機材・季節の一覧が前面確定前に絞っている")
        XCTAssertTrue(screen.contains("FrontConfirm.settleNanoseconds"),
                      "戻り後の絞りをスワイプキャンセルで止められない")
    }

    /// プロフィール編集: 準備中／保存中に写真を選び直したら知らせる（黙って picker だけ消さない）
    func testProfileEditBusyPickerShowsMessage() throws {
        let edit = try source("Features/Profile/ProfileEditView.swift")
        XCTAssertTrue(edit.contains("いま準備中です。終わってから選んでください"),
                      "準備中の再選択が黙って終わっている")
        XCTAssertTrue(edit.contains("保存が終わるまでお待ちください"),
                      "保存中の再選択が黙って終わっている")
    }

    /// 英語の枚数は単数形を持つ `photoCountLabel` を通す（「1 photos」と出ていた・2026-10-07）
    func testPhotoCountsUseSingularAwareLabel() throws {
        for path in ["Core/Text/CollectionScreen.swift", "Features/Gallery/HomeTopCardView.swift",
                     "Core/Text/TripBookFacts.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains(".photoCountLabel("), path)
            XCTAssertFalse(text.contains("count) photos\")"), "\(path) が「1 photos」と出す")
            XCTAssertFalse(text.contains("count)枚\", \"\\("), "\(path) が単数形を持たない枚数を組んでいる")
        }
    }

    /// ホーム: 切り替えの下には選んだフィードの中身だけ（2026-10-11）。
    /// 「撮影地を探す／写真から探す」の札は消し、おすすめの横並びは「おすすめ」のときだけ
    func testHomeShowsSelectedFeedRightBelowPicker() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertFalse(gallery.contains("discoveryBridge"), "切り替えの下に「撮影地を探す」の札が戻っている")
        XCTAssertFalse(gallery.contains("home.exploreMap"))
        // 横並びを置くのは1か所（定義と、絞った中の1回）
        XCTAssertEqual(count("featuredSections", in: gallery), 2, "横並びを絞らずに置いている所がある")
        // #417 ⑧: 切り替えは写真の一覧の見出し（Section の header）。中身は `feedSection` の先頭から
        XCTAssertTrue(gallery.contains("Section {\n                    feedSection(photos)\n                } header: {\n                    feedPicker("),
                      "切り替えの下に中身以外が挟まっている")
        let lines = gallery.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let section = lines.firstIndex(of: "private func feedSection(_ photos: [Photo]) -> some View {") else {
            return XCTFail("切り替えの下の中身が無い")
        }
        XCTAssertEqual(lines[section + 1], "if model.feed.showsFeatured {", "切り替えのすぐ下に別のものが挟まっている")
        XCTAssertEqual(lines[section + 2], "featuredSections")
    }

    /// ホームの上段札: 消した自分の写真だけ落とす（全部の gone は回帰するので使わない・2026-10-12）
    func testHomeTopCardsDropDeletedOwnPhotosOnly() throws {
        let gallery = try source("Features/Gallery/GalleryView.swift")
        XCTAssertTrue(gallery.contains("myPhotos: model.myPhotos.filter { !dropped.deleted.contains($0.id) }"),
                      "消した写真を札から落としていない")
        // 全部の gone で myPhotos を絞ると公開に戻した写真が最大7日消える
        XCTAssertFalse(gallery.contains("myPhotos: dropped.visible(model.myPhotos)"),
                       "myPhotos を全部の gone で絞っている（回帰）")
    }

    /// 探す: 戻った瞬間に手元を写しで絞る（読み直し待ちのフラッシュを止める・2026-10-12）
    func testSearchAppliesHiddenOnAppearWithoutWaitingForReload() throws {
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains("model.applyHidden(dropped)"),
                      "戻ったときに手元の一覧を写しで絞っていない")
        XCTAssertTrue(search.contains("func applyHidden(_ hidden: ModerationSnapshot)"),
                      "通信なしの絞り直し口が無い")
        XCTAssertTrue(search.contains("FrontConfirm"),
                      "探すがスワイプ途中キャンセルで applyHidden して詳細が閉じる")
        XCTAssertTrue(search.contains("FrontConfirm.settleNanoseconds"))
    }

    /// 写真詳細・地図・旅・撮影地なども、戻りは前面確定後に絞る（2026-10-12）。
    /// スワイプ途中の `onAppear` で押した元を消すと、開いている詳細が閉じる
    func testRemainingScreensDeferHiddenUntilFrontConfirmed() throws {
        let paths = [
            "Features/PhotoDetail/PhotoDetailView.swift",
            "Features/Map/PhotoMapView.swift",
            "Features/Map/VisiblePhotos.swift",
            "Features/Map/NearbyPhotosSheet.swift",
            "Features/Trips/TripBookView.swift",
            "Features/Trips/TripPlanDetailView.swift",
            "Features/Spots/SpotDetailView.swift",
            "Features/Spots/OfficialSpotView.swift",
            "Features/Gallery/HomeTopCardView.swift",
            "Features/Albums/InviteView.swift",
            "Features/Stories/StoryInsightsView.swift",
            "Features/Profile/MyPhotosMap.swift",
        ]
        for path in paths {
            let text = try source(path)
            XCTAssertTrue(text.contains("FrontConfirm"), "\(path) が前面確定前に絞っている")
            XCTAssertTrue(text.contains("FrontConfirm.settleNanoseconds"), path)
            XCTAssertTrue(text.contains("front.disappear()"), "\(path) がスワイプキャンセルで待ちを止めていない")
            XCTAssertFalse(text.contains(".onAppear { dropped = hidden.snapshot }"),
                           "\(path) が戻るスワイプ途中で写しを即入れている")
        }
    }

    /// ホーム・人の頁・マイページも戻りは前面確定後に絞る（探索メモの同型穴）
    func testHomeProfileMyPageDeferModerationUntilFrontConfirmed() throws {
        for path in ["Features/Gallery/GalleryView.swift",
                     "Features/Profile/UserProfileView.swift",
                     "Features/Profile/MyPageView.swift",
                     "Features/Profile/FollowListView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("FrontConfirm"), "\(path) が前面確定前に絞っている")
            XCTAssertTrue(text.contains("FrontConfirm.settleNanoseconds"), path)
        }
    }

    /// ブロックの確認は5か所で同じ部品（2026-10-11）。写真の詳細の持ち主・コメントを書いた人は
    /// 押した時点の相手を受け取る `presenting:` 版。確認の文言を自前で持つ所があると落ちる
    func testEveryBlockGoesThroughTheSameConfirmation() throws {
        for path in ["Features/Gallery/HomeMosaic.swift", "Features/Profile/UserProfileView.swift",
                     "Features/Stories/StoryViewerView.swift"] {
            let text = try source(path)
            XCTAssertEqual(count(".blockConfirmation(isPresented: $showBlockConfirm)", in: text), 1,
                           "\(path) が共通の確認を使っていない")
            XCTAssertFalse(text.contains("この人をブロックしますか"), "\(path) が確認の文言を自前で持っている")
        }
        let detail = try source("Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertFalse(detail.contains("この人をブロックしますか"), "写真の詳細が確認の文言を自前で持っている")
        XCTAssertFalse(detail.contains("Block this person?"))
        XCTAssertEqual(count(".blockConfirmation(", in: detail), 2, "写真の詳細のブロックが共通の確認を通っていない")
        XCTAssertTrue(detail.contains(".blockConfirmation(presenting: $ownerPendingBlock) { owner in"),
                      "写真の持ち主のブロックが押した時点の相手を受け取っていない")
        XCTAssertTrue(detail.contains("Task { await block(owner) }"))
        XCTAssertTrue(detail.contains(".blockConfirmation(presenting: $commentPendingBlock) { comment in"),
                      "コメントを書いた人のブロックが共通の確認を通っていない")
        XCTAssertTrue(detail.contains("Task { await block(comment.uid) }"))
        XCTAssertEqual(count("await block(", in: detail), 2, "確認を通らずにブロックする口がある")
        XCTAssertFalse(detail.contains("Task { await block(ownerId) }"), "写真の詳細のブロックが確認なしで走る")
        let lines = detail.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(lines.contains("ownerPendingBlock = ownerId"), "メニューの「この人をブロック」が確認を出していない")
        XCTAssertTrue(lines.contains("Button(role: .destructive) { commentPendingBlock = comment } label: {"),
                      "コメントの「ブロック」が確認を出していない")
        // 共通の部品は文言を1か所だけに持つ（presenting 版も同じ文言を使う）
        let common = try source("Features/Common/BlockConfirmation.swift")
        XCTAssertEqual(count("BlockConfirmationText.message", in: common), 2)
        XCTAssertTrue(common.contains("onConfirm(pending)"), "押した時点の相手でなく、閉じたあとの値を読んでいる")
    }

    /// 通知: 初めての投稿のあとに説明を出す・「前の晩に知らせる」の行に届かないことを出す（2026-10-11）
    func testPushPrimerAndLightAlertNoticeAreWired() throws {
        let upload = try source("Features/Upload/UploadViewModel.swift")
        XCTAssertTrue(upload.contains("PushPrimerStore.shared.notePosted()"), "投稿が上がっても説明の合図を出していない")
        let root = try source("App/RootView.swift")
        XCTAssertTrue(root.contains(".onChange(of: pushPrimer.requests)"))
        XCTAssertTrue(root.contains("pushPrimer.consume(signedIn: auth.userId != nil, permission: push.permission)"),
                      "許可の状態を見ずに説明を出している")
        XCTAssertTrue(root.contains("await push.refreshAuthorization()"), "出す直前に許可を読み直していない")
        XCTAssertTrue(root.contains(".sheet(isPresented: $showPushPrimer) { PushPrimerView() }"))
        // 評価のお願いと重ねない（2026-10-11）: 説明が決め終わるまで待ち、出ている・出した回は頼まない
        XCTAssertTrue(root.contains("defer { pushPrimer.finishDeciding() }"), "説明を決め終えても評価の待ちを解いていない")
        // 2026-10-17: 待ち方と条件は `PostModalGate` に寄せた（条件そのものは TrunkReviewFixesTests が振る舞いで見る）
        XCTAssertTrue(root.contains("until: PostModalGate.reviewWaitIsOver"),
                      "評価のお願いが説明を決め終わるのを待っていない")
        XCTAssertFalse(PostModalGate.reviewWaitIsOver(PostModalSnapshot(pushPrimerDeciding: true)))
        XCTAssertFalse(PostModalGate.reviewMayAsk(PostModalSnapshot(pushPrimerShowing: true)),
                       "評価のお願いが、出ている通知の説明を見ていない")
        let rootLines = root.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let guardLine = rootLines.firstIndex(where: { $0 == "guard PostModalGate.reviewMayAsk(postModalSnapshot())," }) else {
            return XCTFail("評価のお願いが、出ている画面を見ていない")
        }
        XCTAssertEqual(rootLines[guardLine + 1], "pushPrimer.letsReviewAsk(offeredAtStart: offeredAtStart),",
                       "説明を出した回にも評価を頼む")
        XCTAssertEqual(rootLines[guardLine + 2], "reviewPrompt.consume() else { return }")
        let primer = try source("Features/Settings/PushPrimerView.swift")
        XCTAssertTrue(primer.contains("await push.enable()"), "「通知を受け取る」がシステムの許可へ進まない")
        XCTAssertTrue(primer.contains("push.primer.later"))
        let rows = try source("Features/Pro/LightAlertSettingsRows.swift")
        XCTAssertTrue(rows.contains("LightAlertPushNotice.state(wants: wants, knownNotPro: knownNotPro,"),
                      "「前の晩に知らせる」がプッシュの状態を見ていない")
        XCTAssertTrue(rows.contains("permission: push.permission, enabled: push.isEnabled)"))
        XCTAssertTrue(rows.contains("UIApplication.openNotificationSettingsURLString"),
                      "断られた人を設定アプリの「通知」へ案内していない")
        XCTAssertFalse(rows.contains("UIApplication.openSettingsURLString"),
                       "通知の案内がアプリの設定の一番上を開く（「通知」の行を探す手間が増える）")
        // v2（2026-10-14）: 地は brass-soft（真鍮 8% を黒に重ねた #1C170E）。行いっぱいの矩形のまま。
        // 2026-10-16: ボタンに付けた地は実機で上の角が丸く抜けた → ボタンの後ろに別の矩形として敷く
        // 2026-10-16: 行は部品（`PushOffNoticeRow`）に出した（すれちがいの設定と同じものを使う）
        XCTAssertTrue(rows.contains("PushOffNoticeRow(notice: notice"), "「前の晩に知らせる」が案内の行の部品を使っていない")
        let notice = try source("Features/Common/PushOffNoticeRow.swift")
        XCTAssertTrue(notice.contains(".fill(WebTheme.accentSoft)"),
                      "「通知がオフのため届きません」の地が行いっぱいに塗られていない")
        XCTAssertFalse(notice.contains(".background(WebTheme.accentSoft)"),
                       "案内の地をボタンに付けると、実機で上の角が丸く抜ける（2026-10-16）")
        XCTAssertFalse(notice.contains("RoundedRectangle(cornerRadius: 12)"),
                       "案内の地を角丸にすると、角の外側が札の地のまま残り文字が塗りの外に出る")
        let settings = try source("Features/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains(".onChange(of: push.isEnabled)"),
                      "ほかの所で「受け取る」にしても設定のトグルが「切」のまま残る")
        // 起動したときには聞かない（設定の「受け取る」・説明・「前の晩に知らせる」の行の3か所だけ）
        XCTAssertEqual(count("requestAuthorization(options:", in: try source("Core/Push/PushCenter.swift")), 1)
    }
}
