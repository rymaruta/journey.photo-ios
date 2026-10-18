import SwiftUI
import PhotosUI
import UIKit

/// アイコンを自分の写真から選び、丸く切り抜く（#304・板 50b AvatarCrop・2026-10-18）。プロフィールの編集から積む画面。
///
/// - 上: 写真の上に丸。丸の外は黒 60% で沈める。**丸の縁は写真の上なので白**。指で動かす・2本指で大きさ
/// - 中: 決めたあとの出方（マイページ 56・写真の詳細 32・コメント 28）
/// - 下: あなたの写真（最近の10枚・全体に公開しているものだけ）と「端末の写真から」（いままでの「アイコンを変える」と同じ）
/// - 右上の「決める」はヘッダーの文字の操作＝真鍮（黒地の上）。決めたら編集へ戻り、保存で反映される（編集の約束どおり）
struct AvatarCropView: View {
    /// 候補の元（自分の写真）。読めていなければ空
    let photos: [Photo]
    /// 決めた: 切り抜いた JPEG と見本の絵
    let onDone: (Data, UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: String?
    @State private var image: UIImage?
    @State private var loading = false
    @State private var failed = false
    @State private var deviceItem: PhotosPickerItem?
    @State private var zoom: Double = 1
    @State private var zoomBase: Double = 1
    @State private var offset: CGSize = .zero
    @State private var offsetBase: CGSize = .zero

    /// 丸の一辺（板 50b: 280）
    nonisolated static let circle: CGFloat = 280
    /// 写真の場所の高さ（板 50b: 340）
    nonisolated static let stageHeight: CGFloat = 340
    /// 丸の外を沈める輪の太さ（写真の場所の対角より大きければよい）
    nonisolated static let dimWidth: CGFloat = 1200

    private var candidates: [Photo] { CoverCandidates.avatar(photos) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                stage
                Text(L("指で動かす · 2本指で大きさを合わせる", "Drag to move · Pinch to resize"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.top, 8)
                previews
                    .padding(.top, 16)
                library
                    .padding(.top, 16)
            }
        }
        .webScreen()
        .navigationTitle(L("アイコンを選ぶ", "Choose avatar"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("決める", "Done")) { decide() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(image == nil ? WebTheme.muted2 : WebTheme.accent)
                    .disabled(image == nil || loading)
                    .accessibilityIdentifier("avatarCrop.done")
            }
        }
        .task {
            // 開いたときは最近の1枚目を丸に入れる（板 50b）
            if image == nil, let first = candidates.first { await select(first) }
        }
        .onChange(of: deviceItem) { _, item in
            Task { await loadDevice(item) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("avatarCrop")
    }

    // MARK: 丸

    private var stage: some View {
        // 写真・沈める輪は重ね（overlay）に置く——丸より大きい写真を並びに置くと、行の幅が画面より広くなる
        WebTheme.card
            .frame(maxWidth: .infinity)
            .frame(height: Self.stageHeight)
            .overlay {
                if let image {
                    let base = AvatarCropMath.fillSize(image: image.size, side: Self.circle)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: base.width * zoom, height: base.height * zoom)
                        .offset(x: offset.width, y: offset.height)
                } else if loading {
                    ProgressView()
                } else if failed {
                    Text(L("写真を読み込めませんでした", "Couldn't load the photo"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text3)
                }
            }
            .overlay {
                // 丸の外を沈める（黒 60%）: 丸の外側だけを塗る太い輪（内側の縁がちょうど丸の縁）
                Circle()
                    .stroke(Color.black.opacity(0.6), lineWidth: Self.dimWidth)
                    .frame(width: Self.circle + Self.dimWidth, height: Self.circle + Self.dimWidth)
                    .allowsHitTesting(false)
            }
            .overlay {
                // 丸の縁は写真の上なので白
                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                    .frame(width: Self.circle, height: Self.circle)
                    .allowsHitTesting(false)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(drag)
            .simultaneousGesture(pinch)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("丸く切り抜く範囲。指で動かし、2本指で大きさを合わせる",
                                  "The circle crop. Drag to move, pinch to resize."))
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard let image else { return }
                offset = AvatarCropMath.clamp(
                    offset: CGSize(width: offsetBase.width + value.translation.width,
                                   height: offsetBase.height + value.translation.height),
                    zoom: zoom, image: image.size, side: Self.circle)
            }
            .onEnded { _ in offsetBase = offset }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let image else { return }
                zoom = min(AvatarCropMath.maxZoom, max(1, zoomBase * value.magnification))
                offset = AvatarCropMath.clamp(offset: offset, zoom: zoom, image: image.size, side: Self.circle)
            }
            .onEnded { _ in
                zoomBase = zoom
                offsetBase = offset
            }
    }

    // MARK: 出方の見本

    private var previews: some View {
        HStack(alignment: .bottom, spacing: 28) {
            sample(56, L("マイページ", "Your page"))
            sample(32, L("写真の詳細", "Photo"))
            sample(28, L("コメント", "Comments"))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("決めたあとの出方", "How it will look"))
    }

    private func sample(_ side: CGFloat, _ label: String) -> some View {
        VStack(spacing: 6) {
            WebTheme.card
                .frame(width: side, height: side)
                .overlay {
                    if let image {
                        // 丸の中と同じ範囲を、小さな丸に描く
                        let scale = side / Self.circle
                        let base = AvatarCropMath.fillSize(image: image.size, side: Self.circle)
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: base.width * zoom * scale, height: base.height * zoom * scale)
                            .offset(x: offset.width * scale, y: offset.height * scale)
                    }
                }
                .clipShape(Circle())
            Text(label)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
        }
    }

    // MARK: あなたの写真

    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("あなたの写真", "Your photos"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Spacer()
                PhotosPicker(selection: $deviceItem, matching: .images) {
                    Label(L("端末の写真から", "From your library"), systemImage: "photo.on.rectangle")
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avatarCrop.device")
            }
            if candidates.isEmpty {
                Text(L("写真を投稿すると、ここから選べます。", "Post photos to pick from them here."))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text3)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, photo in
                        let on = selectedId == photo.id
                        Button { Task { await select(photo) } } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { RemoteImage(url: photo.gridImageURL) }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                // 選んでいる1枚は真鍮の輪（黒地の上・2pt の黒の隙間）
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(on ? WebTheme.accent : .clear, lineWidth: 2)
                                    .padding(-4))
                                .frame(minHeight: WebTheme.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("\(index + 1) 枚目の写真をアイコンにする", "Use photo \(index + 1) as your avatar"))
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("avatarCrop.photo.\(index)")
                    }
                }
                .padding(4)
            }
        }
        .padding(.horizontal, ProfileV2.gutter)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .overlay(alignment: .top) { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
    }

    // MARK: 読み込み・決める

    private func select(_ photo: Photo) async {
        guard let url = photo.detailImageURL else { return }
        selectedId = photo.id
        await load { try await ProfileImageFromPhoto.download(url) }
    }

    private func loadDevice(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { deviceItem = nil }
        selectedId = nil
        await load {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ProfileImageFromPhoto.Failure.unreadable }
            return data
        }
    }

    private func load(_ fetch: () async throws -> Data) async {
        loading = true
        failed = false
        defer { loading = false }
        do {
            let data = try await fetch()
            // 位置情報を落とした JPEG にしてから扱う（端末から選ぶいままでの流れと同じ・`ImagePreparer`）
            let prepared = try await Task.detached(priority: .userInitiated) {
                try ImagePreparer.prepare(data: data, fileName: "profile").data
            }.value
            guard let picked = UIImage(data: prepared) else { throw ProfileImageFromPhoto.Failure.unreadable }
            image = picked
            zoom = 1
            zoomBase = 1
            offset = .zero
            offsetBase = .zero
        } catch {
            failed = true
        }
    }

    private func decide() {
        guard let image else { return }
        let data = AvatarCropMath.render(image, side: Self.circle, zoom: zoom, offset: offset)
        guard let preview = UIImage(data: data) else { return }
        onDone(data, preview)
        dismiss()
    }
}
