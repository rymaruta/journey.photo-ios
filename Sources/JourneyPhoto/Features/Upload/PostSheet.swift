import SwiftUI

/// 「写真を投稿／カメラで撮る・構図を重ねて撮る／ストーリーを投稿／旅の写真からまとめて」の4行
/// （＋下書きがあれば「下書き n ›」・2026-11-12）。
///
/// Web 側の `app/components/PostSheet.tsx` と対。owner:「写真を追加のとこで
/// 投稿かストーリーを選べるようにしたい」。
///
/// **入口は下の札の「投稿」1つ**（整理案 05c でマイページの「投稿する」を
/// 外した）——入口が2つあると、同じ2択を2か所に書くことになる。
struct PostSheet: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    /// 札の絵に敷く写真（板 21: 絵の後ろに写真・85%）。**本人の写真だけ**。無ければ地の色のまま
    @State private var thumbs: [URL] = []

    /// 端末の下書きの件数（投稿・ストーリーの合計・2026-10-29・#400）。1件以上ならシートの下に
    /// 「下書き n ›」の行（2026-11-12 判断）。**呼び手が開く前に数えて渡す**——出てから数えるとシートの高さ
    /// （`presentationDetents`）が出たあとに替わり、跳ねるか全画面に開き直す
    var drafts: Int = 0
    /// 選ばれたもの。閉じたあとに呼び手が開く
    let onSelect: (Kind) -> Void

    enum Kind {
        case photo
        case story
        /// カメラで撮って、その1枚で投稿へ（2026-10-16）。カメラは投稿画面の帯の「追加」→「写真を撮る」と
        /// 同じ `CameraPicker`、撮った1枚は構図を重ねて撮ったあとと同じ道（`UploadView.initialCapture`）で入れる
        case camera
        /// 端末の写真ライブラリから旅を見つけて、まとめて投稿（`LibraryTripFlowView`）
        case trip
        /// 構図を重ねて撮る（作例なし・2026-10-10 owner）。撮ってから投稿へ進める（`ComposeGuideLauncher`・呼び手が開く）。
        /// 2026-10-17 判断（owner）: 全員無料。Pro の案内は出さない
        case composition
        /// 下書きの一覧（シートの下の「下書き n ›」・2026-11-12 判断）。1件を選ぶと続きから開く（`TabRouter.openDraft`）
        case drafts
    }

    var body: some View {
        // UI テストのときだけ: body の評価を数える（`PerfTimeline`・札 #594 の下調べ。無効なら何もしない）
        let _ = PerfTimeline.shared.count("body.postSheet")
        // v2 PostSheet: 下から出る短いシート。明朝 26 の見出し、
        // 4つの行き先を「52 の角丸の札＋明朝の題＋一行の説明」の行で（行の間は白 8% の線）。
        // 閉じるは見出しの左のシートの「閉じる」（2026-11-13 owner 承認・#187。前は右の × の丸）
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: JPSpace.s) {
                SheetCloseButton(onContent: true)
                Text(L("投稿する", "Create"))
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.top, JPSpace.s)
            .padding(.bottom, JPSpace.xxs)
            // 2026-11-12 判断（1.1.83・案「投稿まわりのデザイン」01）: **行を5本から4本に。** 「カメラで撮る」と
            // 「構図を重ねて撮る」はどちらもカメラを開く入口なので、半分ずつの黒い札（surface-3）で1段に並べる。
            // 下書きの件数は行の右のバッジから、シートの下の「下書き n ›」の行に移した（押すと一覧 → 1件で続きから。
            // 前は 写真を投稿 → 選ぶ画面を閉じる → 下書き → 1件 の5回、いまは 投稿 → 下書き → 1件 の3回）
            choice(
                thumb: thumbs.first,
                title: L("写真を投稿", "Post a photo"),
                detail: L("撮影地やタグを付けて残します。ずっと出ます。", "Keep it with a place and tags. It stays."),
                systemImage: "photo",
                kind: .photo
            )
            // カメラの無い端末では段ごと出さない（構図を重ねて撮るもカメラを使う）
            if CameraPicker.isAvailable {
                cameraSplit
            }
            choice(
                thumb: thumbs.dropFirst().first,
                title: L("ストーリーを投稿", "Post a story"),
                detail: L("24時間で消えます。見た人が分かります。", "Disappears in 24 hours. You can see who viewed it."),
                systemImage: "clock",
                kind: .story
            )
            choice(
                thumb: thumbs.dropFirst(2).first,
                title: L("旅の写真からまとめて", "From a trip in your photos"),
                detail: L("撮影日と場所から旅を見つけます。", "Finds trips by when and where you shot."),
                systemImage: "suitcase",
                kind: .trip,
                last: true
            )
            if drafts > 0 {
                draftsLine
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JPSpace.l)
        // 文字を大きくしたときに切れないよう、全画面にも伸ばせる
        .presentationDetents([.height(Self.sheetHeight(hasCamera: CameraPicker.isAvailable, hasDrafts: drafts > 0)), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(WebTheme.sheet)
        .presentationCornerRadius(Self.sheetRadius)
        .task {
            // **自分が最近出した写真**（`PostSheetThumbs`）。取れない・まだ無いときは
            // 印だけの無地のまま——**他人の写真で埋めない**
            // ログインしていなければ聞きに行かない（無地のまま）
            guard let userId = auth.userId else { return }
            if let cached = PostSheetThumbs.cache.urls(for: userId) {
                thumbs = cached
                return
            }
            // **取れなかったときは控えない**（次に開いたときに取り直す）
            guard let mine = try? await environment.photos.myPhotos() else { return }
            let picked = PostSheetThumbs.pick(fromMine: mine, count: 4)
            PostSheetThumbs.cache.store(picked, for: userId)
            thumbs = picked
        }
    }

    private static func identifier(_ kind: Kind) -> String {
        switch kind {
        case .photo: return "photo"
        case .story: return "story"
        case .camera: return "camera"
        case .trip: return "trip"
        case .composition: return "composition"
        case .drafts: return "drafts"
        }
    }

    /// 下書きの件数（投稿・ストーリーの合計）。ログインしていなければ 0
    static func draftCount(userId: String?) -> Int {
        guard let userId else { return 0 }
        return DraftLibrary.shared.count(for: userId, kind: .post) + DraftLibrary.shared.count(for: userId, kind: .story)
    }

    /// 「カメラで撮る」の題
    static var cameraTitle: String { L("カメラで撮る", "Take a photo") }

    /// シートの高さ（見出し 68 ＋ 行 3 本 × 約 92 ＋ カメラの段 84 ＋ 下書きの行 56 ＋ 下の余白 44）。
    /// 2026-11-12 判断: 行を5本から4本にした（カメラの2つを1段に）。カメラの無い端末は段ごと、
    /// 下書きの無い人は下書きの行ぶん詰める（下に空きを残さない）
    static func sheetHeight(hasCamera: Bool, hasDrafts: Bool) -> CGFloat {
        sheetHeaderHeight + 3 * rowHeight + (hasCamera ? cameraRowHeight : 0)
            + (hasDrafts ? draftsRowHeight : 0) + sheetBottom
    }
    static let sheetHeaderHeight: CGFloat = 68
    static let rowHeight: CGFloat = 92
    static let cameraRowHeight: CGFloat = 84
    static let draftsRowHeight: CGFloat = 56
    static let sheetBottom: CGFloat = 44
    /// カメラの段の札（案: 高さ 56・角 16・surface-3）
    static let cameraTileHeight: CGFloat = 56
    /// シートの上の角（v2 PostSheet の 28）
    static let sheetRadius: CGFloat = 28
    /// 行の印の札（板 52・角 16）
    static let tileSize: CGFloat = 52
    static let tileRadius: CGFloat = JPRadius.l
    /// 印の札の地（板の `#1A1A1C`）。写真が無いときだけ見える
    @MainActor static var tileFill: Color { RaisedTile.fill }

    /// 1つの行き先（v2: 左に 52 の角丸の札、明朝 18 の題と 13 の説明、行の間は白 8% の線）。
    ///
    /// 2026-10-14 判断: **札の中の自分の写真は残す。** v2 の板は印だけの札だが、札に敷くのは
    /// 「その人自身が最近出した写真」という owner の決まり（`PostSheetThumbs`）があり、板より優先した。
    /// 写真の上の印は白（写真の上に真鍮を置かない）。写真が無いときだけ構図の印を真鍮にする
    private func choice(thumb: URL?, title: String, detail: String, systemImage: String, kind: Kind,
                        last: Bool = false) -> some View {
        Button {
            // 選択を先に記録し、シートが閉じきった後に呼び手が次の画面を開く
            onSelect(kind)
            dismiss()
        } label: {
            HStack(spacing: JPSpace.m) {
                Self.tileFill
                    .frame(width: Self.tileSize, height: Self.tileSize)
                    .overlay {
                        // 読めたときだけ敷く（読み込み中の回転や壊れた記号を出さない）
                        if let thumb {
                            AsyncImage(url: thumb) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().aspectRatio(contentMode: .fill).opacity(0.85)
                                }
                            }
                        }
                    }
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Self.iconColor(hasPhoto: thumb != nil, accent: false))
                            .shadow(color: Color.black.opacity(thumb == nil ? 0 : 0.8), radius: 3, x: 0, y: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Self.tileRadius))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(JPFont.rowTitle)
                        .foregroundStyle(WebTheme.text)
                    Text(detail)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 14)
            .frame(minHeight: WebTheme.minTapTarget)
            .overlay(alignment: .bottom) {
                if !last {
                    Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(JPRowButtonStyle())
        // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
        .accessibilityIdentifier("post.choice.\(Self.identifier(kind))")
    }

    /// 「カメラで撮る」「構図を重ねて撮る」を半分ずつの札で1段に（2026-11-12 判断・案 01）。
    /// 写真は敷かない黒い札（surface-3・`RaisedTile`）。構図の印だけ真鍮（黒い札の上）、カメラの印は白
    private var cameraSplit: some View {
        HStack(spacing: JPSpace.xs) {
            cameraTile(title: Self.cameraTitle, wrapped: nil, systemImage: "camera", kind: .camera, accentIcon: false)
            cameraTile(title: Self.compositionTitle, wrapped: Self.compositionTitleWrapped,
                       systemImage: "camera.viewfinder", kind: .composition, accentIcon: true)
        }
        .padding(.vertical, JPSpace.s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    /// 「構図を重ねて撮る」の題と、入らないときの2行の形（言葉の切れ目で折る）。
    /// 2026-11-12 確かめ役: 390〜402 幅の端末では1行に入らず、ふつうに折ると「構図を重ねて撮／る」と1字だけ落ちる
    static var compositionTitle: String { L("構図を重ねて撮る", "Composition guide") }
    static var compositionTitleWrapped: String { L("構図を重ねて\n撮る", "Composition\nguide") }

    private func cameraTile(title: String, wrapped: String?, systemImage: String, kind: Kind,
                            accentIcon: Bool) -> some View {
        Button {
            onSelect(kind)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Self.iconColor(hasPhoto: false, accent: accentIcon))
                    .accessibilityHidden(true)
                // 1行に入ればそのまま、入らなければ言葉の切れ目で2行（`ViewThatFits` が幅で選ぶ）
                ViewThatFits(in: .horizontal) {
                    Text(title)
                        .lineLimit(1)
                        .fixedSize()
                    Text(wrapped ?? title)
                        .lineLimit(wrapped == nil ? 2 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.text)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: Self.cameraTileHeight)
            .background(Self.tileFill, in: RoundedRectangle(cornerRadius: Self.tileRadius))
            .contentShape(RoundedRectangle(cornerRadius: Self.tileRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint(kind == .composition
                           ? L("三分割や黄金比の線をカメラに重ねて撮り、そのまま投稿できます。",
                               "Overlay thirds, golden ratio and more on the camera, then post.")
                           : L("撮った1枚から、そのまま投稿します。", "Take a photo and post it right away."))
        .accessibilityIdentifier("post.choice.\(Self.identifier(kind))")
    }

    /// シートの下の「下書き n ›」（2026-11-12 判断・案 01）。件数は真鍮のバッジ（黒地の上の合図）
    private var draftsLine: some View {
        Button {
            onSelect(.drafts)
            dismiss()
        } label: {
            HStack(spacing: JPSpace.s) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17))
                    .foregroundStyle(WebTheme.text2)
                    .accessibilityHidden(true)
                Text(DraftsText.title)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CountBadge(count: drafts)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: JPHeight.row)
            .overlay(alignment: .top) {
                Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(JPRowButtonStyle())
        .accessibilityLabel(DraftsText.entryAccessibility(drafts))
        .accessibilityIdentifier("post.choice.drafts")
    }

    /// 印の色。**写真の上は白、写真が無い札の上の構図の印だけ真鍮**（v2 の板の真鍮の線・黒い札の上）
    @MainActor static func iconColor(hasPhoto: Bool, accent: Bool) -> Color {
        !hasPhoto && accent ? WebTheme.accent : WebTheme.foreground
    }
}

/// 空の画面の「次の一手」から投稿の流れを開いてよいか（`TabRouter.openPost`・2026-10-16）。
/// **ほかの投稿の画面（旅の写真・投稿・ストーリー・投稿のシート・カメラ）が出ていたら開かない**——
/// 重ねると iOS が遷移を取りこぼすか、書きかけの上に別の画面が出る
enum PostRequestGate {
    nonisolated static func opens(busy: [Bool]) -> Bool { !busy.contains(true) }
}
