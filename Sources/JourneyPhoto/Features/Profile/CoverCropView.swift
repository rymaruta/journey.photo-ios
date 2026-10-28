import SwiftUI
import UIKit

/// カバーの位置を合わせる頼み（`fullScreenCover(item:)` に渡す）。開くたびに別の頼みにする
struct CoverCropRequest: Identifiable {
    let id = UUID()
    /// 選んだ写真のそのままの中身。**切り抜くとき（「完了」）だけ**読み直す（`CoverCropMath.render`）
    let sourceData: Data
    /// 画面に出す絵（長い辺 1500px・`CoverCropMath.display`）。合わせている間・選び直しのために持つのはこれだけ
    let display: UIImage
    /// 候補（自分の投稿）から選んだときの写真の ID。端末から選んだら nil
    let photoId: String?
    /// 前に合わせた位置（選び直しのとき）。初めては真ん中・等倍
    var position = CoverCropPosition()
}

/// 帯の中の写真の位置（倍率と、真ん中からのずれ・pt）
struct CoverCropPosition: Equatable {
    var zoom: Double = 1
    var offset: CGSize = .zero
}

/// カバーの写真を選んだ直後に挟む「帯に映る範囲」を合わせる画面（owner 2026-10-28「ユーザが任意で調整できたらいいよね」）。
///
/// - 枠は**決まった比（基準幅 390 × `ProfileCover.height`）**で、画面に収まるいちばん大きい大きさ（`CoverCropMath.frame`）。
///   iPhone では画面の幅いっぱい、iPad でも同じ比。写真は枠を覆う大きさから始め、
///   ドラッグで位置・ピンチで拡大（1〜3倍・枠に空きが出ない範囲）
/// - 枠には**マイページと同じ溶かし**（`ProfileCoverFade`）を重ね、出来上がりの見え方をそのまま見せる。枠の外は黒 60% で沈める（板 50b のアイコンの丸と同じ）
/// - 枠の縁は写真の上なので白。「完了」はヘッダーの文字の操作＝真鍮（黒地の上・板 50b の「決める」と同じ）、「キャンセル」は白
/// - 決めたら編集の見本に入り、ほかの人に見えるのは右上の「保存」のあと（編集の約束どおり）
struct CoverCropView: View {
    let request: CoverCropRequest
    /// 決めた: 切り抜いた JPEG・見本の絵・合わせた位置
    let onDone: (Data, UIImage, CoverCropPosition) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position = CoverCropPosition()
    @State private var zoomBase: Double = 1
    @State private var offsetBase: CGSize = .zero
    @State private var failed = false
    @State private var started = false
    /// 切り抜いている（「完了」を押せなくする・二度押しの門）
    @State private var rendering = false

    /// 枠の上下に見せる、帯の外の写真の高さ（沈めて出す）
    nonisolated static let margin: CGFloat = 96
    /// 読み上げの操作で動かす量（pt）・倍率の刻み
    nonisolated static let step: CGFloat = 24
    nonisolated static let zoomStep: Double = 0.25
    /// 帯の下の案内の文字と余白に取っておく高さ
    nonisolated static let captionRoom: CGFloat = 80

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // 枠の上下の沈め・案内の文字のぶんを除いた高さに収める
                let frame = CoverCropMath.frame(fitting: CGSize(width: geo.size.width,
                                                                height: geo.size.height - Self.margin * 2 - Self.captionRoom))
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    stage(frame)
                    Text(L("指で動かす · 2本指で大きさを合わせる", "Drag to move · Pinch to zoom"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .padding(.top, 12)
                    if failed {
                        Text(L("切り抜けませんでした。もう一度お試しください", "Couldn't crop the photo. Please try again."))
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.danger)
                            .padding(.top, 8)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                // 上のバーの文字ボタンは系統の部品（当たりは系統が決める）。幅を指定すると
                // 「キャンセル」が丸に押し込まれて切れた（2026-10-28 Mac の絵）ので、大きさは付けない
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("キャンセル", "Cancel")) { dismiss() }
                            .foregroundStyle(WebTheme.foreground)
                            // 切り抜いている間は閉じない（閉じたあとに決めた絵が入ってしまう）
                            .disabled(rendering)
                            .accessibilityIdentifier("coverCrop.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if rendering {
                            ProgressView()
                                .accessibilityLabel(L("切り抜いています", "Cropping"))
                                .accessibilityIdentifier("coverCrop.rendering")
                        } else {
                            Button(L("完了", "Done")) { Task { await decide(frame) } }
                                .font(.body.weight(.semibold))
                                .foregroundStyle(WebTheme.accent)
                                .accessibilityIdentifier("coverCrop.done")
                        }
                    }
                }
            }
            .webScreen()
            .navigationTitle(L("カバーの位置を調整", "Adjust cover"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // 選び直しは前の位置から（初めては真ん中・等倍）
            guard !started else { return }
            started = true
            position = request.position
            zoomBase = request.position.zoom
            offsetBase = request.position.offset
        }
        .accessibilityIdentifier("coverCrop")
    }

    // MARK: 帯

    private func stage(_ frame: CGSize) -> some View {
        let image = request.display
        let base = FrameCropMath.fillSize(image: image.size, frame: frame)
        // 写真・沈め・溶かしは重ね（overlay）に置く——枠より大きい写真を並びに置くと、行の幅が画面より広くなる
        return WebTheme.card
            .frame(width: frame.width, height: frame.height + Self.margin * 2)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: base.width * position.zoom, height: base.height * position.zoom)
                    .offset(x: position.offset.width, y: position.offset.height)
            }
            .overlay {
                VStack(spacing: 0) {
                    // 枠の外（上下）は沈める
                    Color.black.opacity(0.6).frame(height: Self.margin)
                    // マイページの帯と同じ溶かし（`ProfileCover.band` と同じ部品）
                    ProfileCoverFade()
                        .frame(height: frame.height)
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.9)).frame(height: 1) }
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.9)).frame(height: 1) }
                    Color.black.opacity(0.6).frame(height: Self.margin)
                }
                .allowsHitTesting(false)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(drag(frame))
            .simultaneousGesture(pinch(frame))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("カバーの位置を調整。ドラッグで移動、ピンチで拡大",
                                  "Adjust the cover. Drag to move, pinch to zoom."))
            .accessibilityAction(named: L("上へ動かす", "Move up")) { nudge(frame, dy: -Self.step) }
            .accessibilityAction(named: L("下へ動かす", "Move down")) { nudge(frame, dy: Self.step) }
            .accessibilityAction(named: L("左へ動かす", "Move left")) { nudge(frame, dx: -Self.step) }
            .accessibilityAction(named: L("右へ動かす", "Move right")) { nudge(frame, dx: Self.step) }
            .accessibilityAction(named: L("拡大", "Zoom in")) { setZoom(frame, position.zoom + Self.zoomStep) }
            .accessibilityAction(named: L("縮小", "Zoom out")) { setZoom(frame, position.zoom - Self.zoomStep) }
            .accessibilityIdentifier("coverCrop.stage")
    }

    private func drag(_ frame: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                position.offset = FrameCropMath.clamp(
                    offset: CGSize(width: offsetBase.width + value.translation.width,
                                   height: offsetBase.height + value.translation.height),
                    zoom: position.zoom, image: request.display.size, frame: frame)
            }
            .onEnded { _ in offsetBase = position.offset }
    }

    private func pinch(_ frame: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                position.zoom = FrameCropMath.clampZoom(zoomBase * value.magnification, maxZoom: CoverCropMath.maxZoom)
                position.offset = FrameCropMath.clamp(offset: position.offset, zoom: position.zoom,
                                                      image: request.display.size, frame: frame)
            }
            .onEnded { _ in
                zoomBase = position.zoom
                offsetBase = position.offset
            }
    }

    private func nudge(_ frame: CGSize, dx: CGFloat = 0, dy: CGFloat = 0) {
        position.offset = FrameCropMath.clamp(offset: CGSize(width: position.offset.width + dx,
                                                             height: position.offset.height + dy),
                                              zoom: position.zoom, image: request.display.size, frame: frame)
        offsetBase = position.offset
    }

    private func setZoom(_ frame: CGSize, _ zoom: Double) {
        position.zoom = FrameCropMath.clampZoom(zoom, maxZoom: CoverCropMath.maxZoom)
        position.offset = FrameCropMath.clamp(offset: position.offset, zoom: position.zoom,
                                              image: request.display.size, frame: frame)
        zoomBase = position.zoom
        offsetBase = position.offset
    }

    // MARK: 決める

    private func decide(_ frame: CGSize) async {
        guard !rendering else { return }
        rendering = true
        failed = false
        defer { rendering = false }
        let data = request.sourceData, at = position
        do {
            // 4096px の読み直しと焼き直しは重いので、画面の処理の外で
            let jpeg = try await Task.detached(priority: .userInitiated) {
                try CoverCropMath.render(data, frame: frame, zoom: at.zoom, offset: at.offset)
            }.value
            guard let preview = UIImage(data: jpeg) else { throw ImagePreparer.PrepareError.unreadable }
            onDone(jpeg, preview, at)
            dismiss()
        } catch {
            failed = true
        }
    }
}
