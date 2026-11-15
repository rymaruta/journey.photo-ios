import SwiftUI
import UIKit
import Photos

/// ストーリーの「＋」で先に開く**最近の写真と動画の一覧**（札 #627・2026-11-15 判断）。
///
/// 今のインスタと同じ形: 先頭のマスはカメラ、続いて写真と動画が新しい順。**マスを押すとそのまま作る画面へ**
/// （押す回数は「＋ → 選ぶ」の2回）。右上の「選択」で何枚かに印を付けて「次へ（N枚）」でも進める。
/// 決まりは `StoryLibraryRules`。許可の段（すべて・一部・無し）で何を出すかは作る画面（`StoryComposerView.pickStage`）が決める。
///
/// 板の決まり: 写真の格子は3列（アクセシビリティの大きさでは2列）・隙間 4・角なし。写真の上に置くもの
/// （動画の長さ・印）は白だけ。黒い地の上のカメラの印は真鍮
struct StoryLibraryGrid: View {

    let items: [StoryLibraryRules.Item]
    /// 一覧を読み終えたか（読み終えて0件なら「まだ写真がありません」）
    let loaded: Bool
    /// 「選択」を入れている（印を付ける）
    let selecting: Bool
    /// 印を付けた id（選んだ順）
    let marked: [String]
    /// 読み込んでいる1件（押したマス）。読み込み中はどのマスも押せない
    let loadingId: String?
    /// 読み込み中（並びに入れている最中・`loadingPicks > 0`）
    let loading: Bool
    let onCamera: () -> Void
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
                    .accessibilityIdentifier("story.library.empty")
            }
        }
    }

    // MARK: - カメラのマス

    /// 先頭のマス。押すと今のカメラ（`StoryCameraView`）。「選択」の間・読み込み中は押せない。
    /// カメラの無い端末（シミュレータ）では押せない形で残す（マスの並びを端末で変えない）
    private var cameraCell: some View {
        let available = StoryCameraView.isAvailable
        let enabled = available && StoryLibraryRules.cameraEnabled(selecting: selecting, loading: loading)
        return Button(action: onCamera) {
            Color.clear
                .aspectRatio(StoryLibraryRules.cellAspect, contentMode: .fit)
                .overlay {
                    ZStack {
                        WebTheme.surface
                        VStack(spacing: 8) {
                            Image(systemName: "camera")
                                .font(.system(size: 26, weight: .regular))
                                .foregroundStyle(WebTheme.accent)
                            Text(L("カメラ", "Camera"))
                                .font(JPFont.footnote.weight(.semibold))
                                .foregroundStyle(WebTheme.text)
                                .multilineTextAlignment(.center)
                        }
                        .padding(8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(L("カメラ", "Camera"))
        .accessibilityHint(available ? L("撮ってストーリーにします", "Take a photo or video for your story")
                                     : L("この端末ではカメラを使えません", "This device has no camera"))
        .accessibilityIdentifier("story.library.camera")
    }

    // MARK: - 写真・動画のマス

    private func cell(_ item: StoryLibraryRules.Item) -> some View {
        let number = StoryLibraryRules.markNumber(marked, id: item.id)
        return Button { onTap(item) } label: {
            Color.clear
                .aspectRatio(StoryLibraryRules.cellAspect, contentMode: .fit)
                .overlay {
                    // 縮小は一辺 160pt ぶん（3列のマスの長い辺に近い）。管理役は使い回す（`LibraryThumbnails`）
                    LibraryThumbView(id: item.id, side: 160)
                }
                .clipped()
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
        .accessibilityIdentifier("story.library.item")
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
/// （「写真を増やす」で許す写真を足した・撮った写真が増えた）
@MainActor
final class StoryLibraryFeed: ObservableObject {

    @Published private(set) var access: StoryCameraRules.LibraryAccess
    @Published private(set) var items: [StoryLibraryRules.Item] = []
    @Published private(set) var loaded = false

    /// ライブラリの変化の受け手。**この箱が消えるときに外す**（作る画面を閉じたら一緒に消える）
    private var watcher: ChangeWatcher?
    private var fetchTask: Task<Void, Never>?

    init() {
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
        fetchTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { Self.fetchItems() }.value
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
    nonisolated private static func fetchItems() -> [StoryLibraryRules.Item] {
        let options = PHFetchOptions()
        // 絞り込みと並べ替えは PhotoKit に任せる（Linux の Foundation ではキー文字列の並べ替えが作れない・`PhotoLibrary`）
        #if canImport(Darwin)
        options.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        #endif
        options.fetchLimit = StoryLibraryRules.maxItems
        let result = PHAsset.fetchAssets(with: options)
        var items: [StoryLibraryRules.Item] = []
        items.reserveCapacity(result.count)
        for index in 0..<result.count {
            let asset = result.object(at: index)
            let isVideo = asset.mediaType == .video
            guard isVideo || asset.mediaType == .image else { continue }
            items.append(StoryLibraryRules.Item(id: asset.localIdentifier, isVideo: isVideo,
                                                duration: isVideo ? asset.duration : 0,
                                                date: asset.creationDate))
        }
        return items
    }
}
