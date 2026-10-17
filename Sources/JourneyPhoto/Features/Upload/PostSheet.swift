import SwiftUI

/// 「写真を投稿／ストーリーを投稿／旅の写真からまとめて／構図を重ねて撮る（Pro）」の4択。
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
        /// 構図を重ねて撮る（Pro・作例なし・2026-10-10 owner）。撮ってから投稿へ進める。
        /// Pro でなければ Pro の案内（`ComposeGuideLauncher`・呼び手が開く）
        case composition
    }

    var body: some View {
        // v2 PostSheet: 下から出る短いシート。左に明朝 26 の見出し、右に × の丸、
        // 4つの行き先を「52 の角丸の札＋明朝の題＋一行の説明」の行で（行の間は白 8% の線）
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("投稿する", "Create"))
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.close)
            }
            .padding(.top, JPSpace.s)
            .padding(.bottom, JPSpace.xxs)
            choice(
                thumb: thumbs.first,
                title: L("写真を投稿", "Post a photo"),
                detail: L("撮影地やタグを付けて残します。ずっと出ます。", "Keep it with a place and tags. It stays."),
                systemImage: "photo",
                kind: .photo
            )
            // 2026-10-16 判断: 「カメラで撮る」は写真の投稿の次（同じ「写真を投稿」の入口の別の手）。
            // 札に自分の写真は敷かない（敷く写真は4枚まで・`PostSheetThumbs`）。カメラの無い端末では出さない
            if CameraPicker.isAvailable {
                choice(
                    thumb: nil,
                    title: Self.cameraTitle,
                    detail: L("撮った1枚から、そのまま投稿します。", "Take a photo and post it right away."),
                    systemImage: "camera",
                    kind: .camera
                )
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
                kind: .trip
            )
            // 2026-10-10: 4つ目。題の横に合図の「PRO」（真鍮の縁と字・黒地の上）。印も真鍮の線（v2）
            choice(
                thumb: thumbs.dropFirst(3).first,
                title: L("構図を重ねて撮る", "Shoot with a composition guide"),
                detail: L("三分割や黄金比の線をカメラに重ねて撮り、そのまま投稿できます。",
                          "Overlay thirds, golden ratio and more on the camera, then post."),
                systemImage: "camera.viewfinder",
                kind: .composition,
                badge: "PRO",
                last: true
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JPSpace.l)
        // 文字を大きくしたときに切れないよう、全画面にも伸ばせる
        .presentationDetents([.height(Self.sheetHeight), .large])
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
        }
    }

    /// 「カメラで撮る」の題
    static var cameraTitle: String { L("カメラで撮る", "Take a photo") }

    /// シートの高さ（見出し 68 ＋ 行 5 本 × 約 92 ＋ 下の余白）。札から行にして詰まった。
    /// 2026-10-16: 「カメラで撮る」の1行ぶん伸ばした（カメラの無い端末では1行ぶん下が空く）
    static let sheetHeight: CGFloat = 572
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
                        badge: String? = nil, last: Bool = false) -> some View {
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
                            .foregroundStyle(Self.iconColor(hasPhoto: thumb != nil, pro: badge != nil))
                            .shadow(color: Color.black.opacity(thumb == nil ? 0 : 0.8), radius: 3, x: 0, y: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Self.tileRadius))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: JPSpace.xs) {
                        Text(title)
                            .font(JPFont.rowTitle)
                            .foregroundStyle(WebTheme.text)
                        if let badge {
                            // v2: PRO の合図は真鍮の縁と字（黒地の上・Components 03）
                            Text(badge)
                                .jpEyebrow()
                                .foregroundStyle(WebTheme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .overlay(Capsule().strokeBorder(WebTheme.accent.opacity(0.6), lineWidth: JPStroke.hairline))
                                .accessibilityLabel(L("Pro の機能", "Pro feature"))
                        }
                    }
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

    /// 印の色。**写真の上は白、写真が無い札の上の構図の印だけ真鍮**（v2 の板の真鍮の線・黒い札の上）
    @MainActor static func iconColor(hasPhoto: Bool, pro: Bool) -> Color {
        !hasPhoto && pro ? WebTheme.accent : WebTheme.foreground
    }
}

/// 空の画面の「次の一手」から投稿の流れを開いてよいか（`TabRouter.openPost`・2026-10-16）。
/// **ほかの投稿の画面（旅の写真・投稿・ストーリー・投稿のシート・カメラ）が出ていたら開かない**——
/// 重ねると iOS が遷移を取りこぼすか、書きかけの上に別の画面が出る
enum PostRequestGate {
    nonisolated static func opens(busy: [Bool]) -> Bool { !busy.contains(true) }
}
