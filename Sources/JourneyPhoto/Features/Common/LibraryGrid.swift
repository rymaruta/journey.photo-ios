import SwiftUI
import UIKit
import Photos

/// **最近の写真（と動画）の一覧**。投稿とストーリーで同じ1つ（2026-11-18 判断・案 B1「投稿の入口」を owner 採用）。
///
/// 1.1.96 でストーリーの「＋」のために作った一覧（札 #627）を、投稿の入口にも使う。今のインスタと同じ形:
/// 先頭のマスはカメラ、続いて写真が新しい順。**マスを押すとそのまま次の画面へ**（投稿は欄を書く画面、
/// ストーリーは作る画面）。右上の「選択」で何枚かに印を付けて「次へ（N枚）」でも進める。
/// 決まりは `StoryLibraryRules`（名前はストーリーのままだが、投稿と共通）。許可の段（すべて・一部・無し）で
/// 何を出すかは使う画面（`UploadView.libraryStage`・`StoryComposerView.pickStage`）が決める。
///
/// 寸法は案 B1 の模型: **4列・隙間 4・角なし・正方形のマス**（アクセシビリティの大きさでは3列）。
/// 先頭のカメラのマスは surface-3（#1A1A1C）に白い印。写真の上に置くもの（動画の長さ・印）は白だけ
struct LibraryGrid: View {

    let items: [StoryLibraryRules.Item]
    /// 一覧を読み終えたか（読み終えて0件なら「まだ写真がありません」）
    let loaded: Bool
    /// 「選択」を入れている（印を付ける）
    let selecting: Bool
    /// 印を付けた id（選んだ順）
    let marked: [String]
    /// 読み込んでいる1件（押したマス）。読み込み中はどのマスも押せない
    let loadingId: String?
    /// 読み込み中（並びに入れている最中）
    let loading: Bool
    /// 識別子の頭（投稿は `post.library`、ストーリーは `story.library`）
    var idPrefix: String = "story.library"
    /// カメラのマスの読み上げの補足（投稿とストーリーで言うことが違う）
    var cameraHint: String = L("撮ってストーリーにします", "Take a photo or video for your story")
    /// カメラを使える端末か（シミュレータでは押せない形で残す・マスの並びを端末で変えない）
    var cameraAvailable: Bool = StoryCameraView.isAvailable
    let onCamera: () -> Void
    /// 「構図を重ねて撮る」のマス（投稿の入口だけ・2026-11-18 判断）。nil なら出さない。
    /// 前は投稿のシートの札だった（入口を増やさないよう、シートをやめた分を一覧の中へ移した）
    var onComposition: (() -> Void)? = nil
    let onTap: (StoryLibraryRules.Item) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = StoryLibraryRules.columns(accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        return Array(repeating: GridItem(.flexible(), spacing: WebTheme.gridSpacing), count: count)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: WebTheme.gridSpacing) {
                cameraCell
                if let onComposition { compositionCell(onComposition) }
                ForEach(items) { item in
                    cell(item)
                }
            }
            if loaded && items.isEmpty {
                Text(StoryLibraryRules.emptyTitle)
                    .font(JPFont.display(20, relativeTo: .title3))
                    .foregroundStyle(WebTheme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("\(idPrefix).empty")
            }
        }
    }

    // MARK: - カメラのマス

    /// 先頭のマス。押すと今のカメラ。「選択」の間・読み込み中は押せない
    private var cameraCell: some View {
        let enabled = cameraAvailable && StoryLibraryRules.cameraEnabled(selecting: selecting, loading: loading)
        return Button(action: onCamera) {
            tile {
                // 案 B1: #1A1A1C に白い印（30pt）。字は置かない（印だけで分かる・読み上げは名前で言う）
                Image(systemName: "camera")
                    .font(.system(size: StoryLibraryRules.cameraIconSize, weight: .regular))
                    .foregroundStyle(WebTheme.foreground)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(L("カメラ", "Camera"))
        .accessibilityHint(cameraAvailable ? cameraHint : L("この端末ではカメラを使えません", "This device has no camera"))
        .accessibilityIdentifier("\(idPrefix).camera")
    }

    /// 「構図を重ねて撮る」（投稿の入口だけ）。印は真鍮（黒い札の上・前の投稿のシートと同じ扱い）、下に短い名前。
    /// 2026-11-18 判断: 模型のカメラのマスは字なしだが、構図の印だけでは何のマスか分からないので「構図」と添える
    private func compositionCell(_ action: @escaping () -> Void) -> some View {
        let enabled = cameraAvailable && StoryLibraryRules.cameraEnabled(selecting: selecting, loading: loading)
        return Button(action: action) {
            tile {
                VStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: StoryLibraryRules.cameraIconSize - 4, weight: .regular))
                        .foregroundStyle(WebTheme.accent)
                    Text(StoryLibraryRules.compositionShortTitle)
                        .font(JPFont.caption.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(4)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(StoryLibraryRules.compositionTitle)
        .accessibilityHint(L("三分割や黄金比の線をカメラに重ねて撮り、そのまま投稿できます。",
                             "Overlay thirds, golden ratio and more on the camera, then post."))
        .accessibilityIdentifier("post.choice.composition")
    }

    /// 一段浮かせた正方形の札（surface-3）
    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Color.clear
            .aspectRatio(StoryLibraryRules.cellAspect, contentMode: .fit)
            .overlay {
                ZStack {
                    RaisedTile.fill
                    content()
                }
            }
            .contentShape(Rectangle())
    }

    // MARK: - 写真・動画のマス

    private func cell(_ item: StoryLibraryRules.Item) -> some View {
        let number = StoryLibraryRules.markNumber(marked, id: item.id)
        return Button { onTap(item) } label: {
            Color.clear
                .aspectRatio(StoryLibraryRules.cellAspect, contentMode: .fit)
                .overlay {
                    // 縮小は一辺 160pt ぶん（4列のマスの2倍ほど）。管理役は使い回す（`LibraryThumbnails`）
                    LibraryThumbView(id: item.id, side: 160)
                }
                .clipped()
                // 印を付けたマスは少し沈める（案 B1 の 75%）
                .opacity(number != nil ? StoryLibraryRules.markedOpacity : 1)
                .overlay(alignment: .bottomTrailing) {
                    if item.isVideo { durationBadge(item.duration) }
                }
                .overlay(alignment: .topTrailing) {
                    if selecting { markCircle(number) }
                }
                .overlay {
                    if loadingId == item.id {
                        ZStack {
                            Color.black.opacity(0.45)
                            ProgressView().tint(.white)
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(StoryLibraryRules.accessibilityLabel(item))
        .accessibilityValue(number.map { L("\($0)番目に選択", "Selected, \($0)") } ?? "")
        .accessibilityAddTraits(number != nil ? .isSelected : [])
        .accessibilityIdentifier("\(idPrefix).item")
    }

    /// 動画の長さ（右下・写真の上なので白。下に薄い影の帯を敷いて明るい写真でも読めるように）
    private func durationBadge(_ seconds: Double) -> some View {
        Text(StoryLibraryRules.durationLabel(seconds))
            .font(JPFont.mono(12, medium: true))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
    }

    /// 印（右上）。写真の上なので白: 付いていなければ白い輪、付いていれば白い丸に墨の番号
    private func markCircle(_ number: Int?) -> some View {
        ZStack {
            if let number {
                Circle().fill(Color.white)
                Text("\(number)")
                    .font(JPFont.mono(12, medium: true))
                    .foregroundStyle(WebTheme.accentText)
            } else {
                Circle().fill(Color.black.opacity(0.25))
                Circle().strokeBorder(Color.white, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
        .padding(6)
        .accessibilityHidden(true)
    }
}

/// 一覧の中身（許可の段と、新しい順の写真と動画）。**ライブラリが変わったら読み直す**
/// （「写真を増やす」で許す写真を足した・撮った写真が増えた）。投稿は写真だけ（`includesVideos: false`）
@MainActor
final class LibraryFeed: ObservableObject {

    @Published private(set) var access: StoryCameraRules.LibraryAccess
    @Published private(set) var items: [StoryLibraryRules.Item] = []
    @Published private(set) var loaded = false

    /// 動画も並べるか（ストーリーは並べる・投稿は写真だけ）
    private let includesVideos: Bool
    /// ライブラリの変化の受け手。**この箱が消えるときに外す**（画面を閉じたら一緒に消える）
    private var watcher: ChangeWatcher?
    private var fetchTask: Task<Void, Never>?

    init(includesVideos: Bool = true) {
        self.includesVideos = includesVideos
        access = Self.currentAccess()
    }

    var content: StoryLibraryRules.Content { StoryLibraryRules.content(for: access) }

    /// 許可の段を読み直し、一覧を出す段なら読み直す
    func refresh() {
        access = Self.currentAccess()
        guard case .grid = content else {
            fetchTask?.cancel()
            items = []
            loaded = false
            return
        }
        watchChanges()
        fetchTask?.cancel()
        let videos = includesVideos
        fetchTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { Self.fetchItems(includesVideos: videos) }.value
            guard !Task.isCancelled, let self else { return }
            self.items = found
            self.loaded = true
        }
    }

    /// 「すべての写真をここに並べる」: iOS の許可のダイアログ（まだ聞いていないときだけ出る）
    func requestAccess() async {
        _ = await PhotoLibrary.requestAccess()
        refresh()
    }

    /// 「写真を増やす」: 一部だけ許可した人が、許す写真を選び足す（閉じたら読み直す）
    func addAllowedPhotos() async {
        _ = await PhotoLibrary.presentLimitedPicker()
        refresh()
    }

    private func watchChanges() {
        guard watcher == nil else { return }
        watcher = ChangeWatcher { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// 変化の受け手（`DeviceTripChangeObserver` を使い回す）を登録し、消えるときに外す箱
    private final class ChangeWatcher {
        private let observer: DeviceTripChangeObserver

        init(onChange: @escaping @Sendable () -> Void) {
            observer = DeviceTripChangeObserver(onChange: onChange)
            PHPhotoLibrary.shared().register(observer)
        }

        deinit {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
        }
    }

    private static func currentAccess() -> StoryCameraRules.LibraryAccess {
        #if canImport(Darwin)
        return StoryCameraRules.libraryAccess(PhotoLibrary.status)
        #else
        return .notDetermined
        #endif
    }

    /// 新しい順の写真と動画（`StoryLibraryRules.maxItems` まで）。**重いので画面の処理の外で**
    nonisolated private static func fetchItems(includesVideos: Bool) -> [StoryLibraryRules.Item] {
        let options = PHFetchOptions()
        // 絞り込みと並べ替えは PhotoKit に任せる（Linux の Foundation ではキー文字列の並べ替えが作れない・`PhotoLibrary`）
        #if canImport(Darwin)
        options.predicate = includesVideos
            ? NSPredicate(format: "mediaType == %d || mediaType == %d",
                          PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            : NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        #endif
        options.fetchLimit = StoryLibraryRules.maxItems
        let result = PHAsset.fetchAssets(with: options)
        var items: [StoryLibraryRules.Item] = []
        items.reserveCapacity(result.count)
        for index in 0..<result.count {
            let asset = result.object(at: index)
            let isVideo = asset.mediaType == .video
            guard isVideo ? includesVideos : asset.mediaType == .image else { continue }
            items.append(StoryLibraryRules.Item(id: asset.localIdentifier, isVideo: isVideo,
                                                duration: isVideo ? asset.duration : 0,
                                                date: asset.creationDate))
        }
        return items
    }
}
