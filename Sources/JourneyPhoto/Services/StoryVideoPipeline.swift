import Foundation
import SwiftUI
import PhotosUI
import UIKit

/// ストーリーの動画の取り込みと書き出し（札 #500・owner 2026-11-08）。
///
/// **画面（`StoryComposerView`）が呼ぶ口はここだけ。** AVFoundation に触る本体は Darwin の枝に置き、
/// Linux（`Shims/`）では「動画は扱えない」を返す——Linux の `swift test` は決まり（`StoryVideoRules`）と
/// 送る形（`StoryService`・`StoryUploadCenter`）を確かめ、書き出しの本物は Mac の CI と実機で確かめる。
enum StoryVideoPipeline {

    /// 取り込んだ動画と、作る画面の絵になる表紙の1コマ（JPEG）
    struct Imported {
        let clip: StoryVideoClip
        let posterJPEG: Data
    }

    /// 写真選びの1件が動画か
    static func isVideo(_ item: PhotosPickerItem) -> Bool {
        #if canImport(Darwin)
        return item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        #else
        return false
        #endif
    }

    /// 写真選びの1件の動画を端末の一時フォルダに写して確かめる。**長さが 60 秒を超えたらここで断る**
    static func importClip(from item: PhotosPickerItem) async throws -> Imported {
        #if canImport(Darwin)
        let movie: StoryMovieFile?
        do {
            movie = try await item.loadTransferable(type: StoryMovieFile.self)
        } catch {
            throw StoryVideoRules.Problem.importFailed
        }
        guard let movie else { throw StoryVideoRules.Problem.importFailed }
        return try await prepare(fileAt: movie.url)
        #else
        throw StoryVideoRules.Problem.importFailed
        #endif
    }

    /// カメラで撮った動画（`CameraPicker` が自分の一時フォルダに写したファイル）を確かめる
    static func importRecorded(at url: URL) async throws -> Imported {
        #if canImport(Darwin)
        return try await prepare(fileAt: url)
        #else
        throw StoryVideoRules.Problem.importFailed
        #endif
    }

    /// 重ね（文字・札・曲）を焼き込み、50MB に収まる mp4 に書き出す。**位置情報は残さない**。
    /// 返すのは一時フォルダのファイル（`StoryUploadCenter` が並びの置き場へ移す）
    static func export(_ clip: StoryVideoClip, overlays: [TextOverlay],
                       song: SongStickerPainter.Art?) async throws -> URL {
        #if canImport(Darwin)
        return try await exportDarwin(clip, overlays: overlays, song: song)
        #else
        throw StoryVideoRules.Problem.exportFailed
        #endif
    }

    /// 取り込んだ一時ファイルを片づける（外した・閉じた）
    static func discard(_ clip: StoryVideoClip?) {
        guard let clip else { return }
        try? FileManager.default.removeItem(at: clip.url)
    }

    static func temporaryURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("story-video-\(UUID().uuidString).\(ext)")
    }
}

#if canImport(Darwin)
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

/// 写真選びの動画を、ファイルのまま（メモリに載せずに）受け取る
struct StoryMovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // 受け取ったファイルは関数を出ると消えるので、自分の一時フォルダへ写す
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = StoryVideoPipeline.temporaryURL(ext: ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return StoryMovieFile(url: copy)
        }
    }
}

extension StoryVideoPipeline {

    /// 長さ・向き・大きさを読み、表紙の1コマを作る。断るときは写したファイルも消す
    fileprivate static func prepare(fileAt url: URL) async throws -> Imported {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            if let problem = StoryVideoRules.problem(durationSec: duration) {
                try? FileManager.default.removeItem(at: url)
                throw problem
            }
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                try? FileManager.default.removeItem(at: url)
                throw StoryVideoRules.Problem.unreadable
            }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            let size = CGSize(width: abs(rect.width), height: abs(rect.height))
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1920, height: 1920)
            // 先頭の黒い1コマを避け、短い動画でも範囲に収める
            let at = CMTime(seconds: min(0.2, duration / 2), preferredTimescale: 600)
            let image = try await generator.image(at: at).image
            guard let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.9) else {
                try? FileManager.default.removeItem(at: url)
                throw StoryVideoRules.Problem.unreadable
            }
            return Imported(clip: StoryVideoClip(url: url, durationSec: duration, size: size, bytes: bytes),
                            posterJPEG: jpeg)
        } catch let problem as StoryVideoRules.Problem {
            throw problem
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw StoryVideoRules.Problem.unreadable
        }
    }

    fileprivate static func exportDarwin(_ clip: StoryVideoClip, overlays: [TextOverlay],
                                         song: SongStickerPainter.Art?) async throws -> URL {
        let asset = AVURLAsset(url: clip.url)
        let visible = overlays.filter { !$0.isEmpty }
        var source: AVAsset = asset
        var videoComposition: AVVideoComposition?
        if !visible.isEmpty {
            let built = try await composition(for: asset, overlays: visible, song: song)
            source = built.asset
            videoComposition = built.video
        }

        // 画質の高い段から順に試し、50MB に収まった最初の1本を返す（収まらなければ次の段へ）
        var lastProblem = StoryVideoRules.Problem.exportFailed
        for step in StoryVideoRules.ladder(durationSec: clip.durationSec) {
            guard let session = AVAssetExportSession(asset: source, presetName: step.preset) else { continue }
            let out = StoryVideoPipeline.temporaryURL(ext: StoryVideoRules.exportExtension)
            session.outputURL = out
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            session.videoComposition = videoComposition
            // 位置情報（`com.apple.quicktime.location.ISO6709`）を含む付帯情報を書かない。
            // 書き出したあとにもう一度確かめる（下）——消せたつもりで上げない
            session.metadata = []
            session.metadataItemFilter = AVMetadataItemFilter.forSharing()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else {
                try? FileManager.default.removeItem(at: out)
                lastProblem = .exportFailed
                continue
            }
            let bytes = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if let problem = StoryVideoRules.problem(exportedBytes: bytes) {
                try? FileManager.default.removeItem(at: out)
                lastProblem = problem
                continue
            }
            if await hasLocationMetadata(out) {
                try? FileManager.default.removeItem(at: out)
                throw StoryVideoRules.Problem.locationRemains
            }
            return out
        }
        throw lastProblem
    }

    /// 重ねの層を載せた合成（向きを直し、重ねを 1 枚の画像として全コマの上に置く）
    private static func composition(for asset: AVURLAsset, overlays: [TextOverlay],
                                    song: SongStickerPainter.Art?) async throws
        -> (asset: AVAsset, video: AVVideoComposition) {
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw StoryVideoRules.Problem.unreadable
        }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw StoryVideoRules.Problem.exportFailed
        }
        let duration = try await asset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        do {
            try video.insertTimeRange(range, of: sourceVideo, at: .zero)
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
               let audio = composition.addMutableTrack(withMediaType: .audio,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid) {
                try audio.insertTimeRange(range, of: sourceAudio, at: .zero)
            }
        } catch {
            throw StoryVideoRules.Problem.exportFailed
        }

        let natural = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        let frameRate = try await sourceVideo.load(.nominalFrameRate)
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        // H.264 は偶数の画素を好む
        let renderSize = CGSize(width: (abs(rect.width) / 2).rounded() * 2, height: (abs(rect.height) / 2).rounded() * 2)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
        layerInstruction.setTransform(
            transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY)), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let fps = frameRate > 1 ? Int32(min(60, frameRate.rounded())) : 30
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        videoComposition.instructions = [instruction]

        // 写真と同じ描き方（`TextOverlayRenderer.draw`）で透明な画像に重ねだけを描き、全コマの上に置く
        if let cgImage = TextOverlayRenderer.overlayImage(overlays, size: renderSize, song: song)?.cgImage {
            let frame = CGRect(origin: .zero, size: renderSize)
            let parent = CALayer()
            parent.frame = frame
            let videoLayer = CALayer()
            videoLayer.frame = frame
            let overlayLayer = CALayer()
            overlayLayer.frame = frame
            overlayLayer.contents = cgImage
            parent.addSublayer(videoLayer)
            parent.addSublayer(overlayLayer)
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer, in: parent)
        }
        return (composition, videoComposition)
    }

    /// 書き出した動画に位置情報の付帯情報が残っているか
    private static func hasLocationMetadata(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        var items: [AVMetadataItem] = []
        items += (try? await asset.load(.metadata)) ?? []
        items += (try? await asset.load(.commonMetadata)) ?? []
        for format in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            items += (try? await asset.loadMetadata(for: format)) ?? []
        }
        return items.contains { item in
            StoryVideoRules.isLocationIdentifier(item.identifier?.rawValue ?? "")
                || StoryVideoRules.isLocationIdentifier(item.commonKey?.rawValue ?? "")
        }
    }
}

extension TextOverlayRenderer {
    /// 重ねだけを透明な画像に描く（動画の全コマの上に置く・札 #500）。`size` は動画の向きを直した後の画素数。
    /// 大きさの基準・字・札の描き方は写真の焼き込み（`burn`）と同じ関数
    static func overlayImage(_ overlays: [TextOverlay], size: CGSize, song: SongStickerPainter.Art?) -> UIImage? {
        let visible = overlays.filter { !$0.isEmpty }
        guard !visible.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            for overlay in visible {
                draw(overlay, on: size, context: context.cgContext, song: song)
            }
        }
    }
}
#endif
