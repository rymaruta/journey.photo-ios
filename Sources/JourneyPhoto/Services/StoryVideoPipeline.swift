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

    /// 写真選びの1件の動画を端末の一時フォルダに写して確かめる。**60 秒を超えても断らない**
    /// （2026-11-09 から・作る画面で範囲を選んで切る）。断るのは読めない動画と、長すぎる動画（`StoryVideoRules.maxSourceSeconds`）だけ
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

    /// カメラで撮った動画（`StoryCameraView` が撮った一時ファイル）を確かめる
    static func importRecorded(at url: URL) async throws -> Imported {
        #if canImport(Darwin)
        return try await prepare(fileAt: url)
        #else
        throw StoryVideoRules.Problem.importFailed
        #endif
    }

    /// 切り取りの帯に敷くサムネイル（`count` 枚）。動画全体を等分した各区間の真ん中の1コマ（`StoryVideoTrim.thumbnailTimes`）。
    /// 取れなかったコマは nil。**小さな絵（長い辺 240px）を近いキーフレームで取る**——数十分の動画でも重くしない。
    /// 取り消されたら取れたぶんだけ返す
    static func filmstrip(of clip: StoryVideoClip, count: Int) async -> [UIImage?] {
        #if canImport(Darwin)
        return await filmstripDarwin(url: clip.url, total: clip.durationSec, count: count)
        #else
        return []
        #endif
    }

    /// 作る画面の絵になる表紙の1コマ（JPEG）を、`seconds` の所から取り直す（切り取りで始点を変えたとき）
    static func poster(of clip: StoryVideoClip, at seconds: Double) async -> Data? {
        #if canImport(Darwin)
        return await posterDarwin(url: clip.url, at: seconds)
        #else
        return nil
        #endif
    }

    /// 重ね（文字・札・曲）を焼き込み、50MB に収まる mp4 に書き出す。**位置情報は残さない**。
    /// **切り取り（`clip.trim`）の範囲だけ**を書き出す（2026-11-09）。
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

/// 取り込んだ動画の一時ファイルの持ち主(札 #500)。作る画面の `@StateObject` に置き、**画面が本当に無くなった
/// とき(閉じた・やめた・どの経路でも)に残りを消す**。`onDisappear` は別の画面を重ねただけでも走るので使わない
final class StoryVideoTempHolder: ObservableObject {
    private var urls: Set<URL> = []
    func add(_ url: URL) { urls.insert(url) }
    func forget(_ url: URL) { urls.remove(url) }
    deinit {
        for url in urls { try? FileManager.default.removeItem(at: url) }
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
            // 2026-11-09: 60 秒を超えても断らない（作る画面で切る）。読めない・長すぎる動画だけ断る
            if let problem = StoryVideoRules.importProblem(durationSec: duration) {
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

    /// 取り消しを渡すための入れ物(`AVAssetExportSession` は Sendable ではない)
    private final class ExportBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) { self.session = session }
    }

    fileprivate static func exportDarwin(_ clip: StoryVideoClip, overlays: [TextOverlay],
                                         song: SongStickerPainter.Art?) async throws -> URL {
        let asset = AVURLAsset(url: clip.url)
        let visible = overlays.filter { !$0.isEmpty }

        // 画質の高い段から順に試し、50MB に収まった最初の1本を返す(収まらなければ次の段へ)。
        // **重ねの有無に関わらず `AVMutableComposition` を通す**——元のファイルの付帯情報(撮影地など)を
        // 書き出しに持ち込まない。位置情報は書き出したあとにもう一度確かめる(下)
        var lastProblem = StoryVideoRules.Problem.exportFailed
        // 段は**切ったあとの長さ**で選ぶ（元が長くても、残す範囲が短ければ高い画質から試せる）
        for step in StoryVideoRules.ladder(durationSec: clip.outputSeconds) {
            try Task.checkCancellation()
            let built = try await composition(for: asset, trim: clip.trim, overlays: visible, song: song, step: step)
            // 位置情報が残ったときは1回だけ自動でやり直す(それでも残るなら上げない)
            for _ in 0..<2 {
                try Task.checkCancellation()
                guard let session = AVAssetExportSession(asset: built.asset, presetName: step.preset) else { break }
                let out = StoryVideoPipeline.temporaryURL(ext: StoryVideoRules.exportExtension)
                session.outputURL = out
                session.outputFileType = .mp4
                session.shouldOptimizeForNetworkUse = true
                session.videoComposition = built.video
                session.metadata = []
                session.metadataItemFilter = AVMetadataItemFilter.forSharing()
                let box = ExportBox(session)
                // 画面を閉じた・やめるで取り消されたら書き出しも止める
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        box.session.exportAsynchronously { continuation.resume() }
                    }
                } onCancel: {
                    box.session.cancelExport()
                }
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: out)
                    throw CancellationError()
                }
                guard session.status == .completed else {
                    try? FileManager.default.removeItem(at: out)
                    lastProblem = .exportFailed
                    break
                }
                let bytes = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if let problem = StoryVideoRules.problem(exportedBytes: bytes) {
                    try? FileManager.default.removeItem(at: out)
                    lastProblem = problem
                    break
                }
                if await hasLocationMetadata(out) {
                    try? FileManager.default.removeItem(at: out)
                    lastProblem = .locationRemains
                    continue
                }
                return out
            }
        }
        throw lastProblem
    }

    /// 書き出す元の合成。向きを直し、重ねがあれば**段の大きさまで縮めて**全コマの上に置く
    private static func composition(for asset: AVURLAsset, trim: StoryVideoTrim, overlays: [TextOverlay],
                                    song: SongStickerPainter.Art?, step: StoryVideoRules.Step) async throws
        -> (asset: AVAsset, video: AVVideoComposition?) {
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw StoryVideoRules.Problem.unreadable
        }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw StoryVideoRules.Problem.exportFailed
        }
        let duration = try await asset.load(.duration)
        // 切り取り（2026-11-09）: 元の動画の `start` から `length` 秒だけを、合成の 0 秒へ置く。
        // 切っていない動画は今までどおり全体（端の丸めで範囲が動画の外へ出ない）。
        // `range` は**書き出す動画の側の時間**（0 から。重ねの指示の範囲）、`sourceRange` は元の動画の側
        let sourceRange: CMTimeRange
        if trim.isFull {
            sourceRange = CMTimeRange(start: .zero, duration: duration)
        } else {
            let from = min(trim.start, max(duration.seconds - trim.minimumLength, 0))
            let length = min(trim.length, max(duration.seconds - from, trim.minimumLength))
            sourceRange = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600),
                                      duration: CMTime(seconds: length, preferredTimescale: 600))
        }
        let range = CMTimeRange(start: .zero, duration: sourceRange.duration)
        do {
            try video.insertTimeRange(sourceRange, of: sourceVideo, at: .zero)
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
               let audio = composition.addMutableTrack(withMediaType: .audio,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid) {
                try audio.insertTimeRange(sourceRange, of: sourceAudio, at: .zero)
            }
        } catch {
            throw StoryVideoRules.Problem.exportFailed
        }

        let natural = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        guard !overlays.isEmpty else {
            // 重ねなし: 向きだけ写す(付帯情報は写さない)。大きさは書き出しの段が決める
            video.preferredTransform = transform
            return (composition, nil)
        }

        let frameRate = try await sourceVideo.load(.nominalFrameRate)
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        let oriented = CGSize(width: abs(rect.width), height: abs(rect.height))
        let renderSize = StoryVideoRules.renderSize(for: oriented, step: step)
        let sx = renderSize.width / max(oriented.width, 1)
        let sy = renderSize.height / max(oriented.height, 1)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
        layerInstruction.setTransform(
            transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                .concatenating(CGAffineTransform(scaleX: sx, y: sy)), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: StoryVideoRules.overlayFrameRate(source: frameRate))
        videoComposition.instructions = [instruction]

        // 写真と同じ描き方(`TextOverlayRenderer.draw`)で透明な画像に重ねだけを描き、全コマの上に置く
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

    /// 切り取りの帯のサムネイル（`filmstrip(of:count:)` の本体）
    fileprivate static func filmstripDarwin(url: URL, total: Double, count: Int) async -> [UIImage?] {
        let times = StoryVideoTrim.thumbnailTimes(total: total, count: count)
        guard !times.isEmpty else { return [] }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        // 帯の1コマは 44pt 前後。小さく・近いキーフレームで済ませる（数十分の動画でも1コマ数十ミリ秒）
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        var images: [UIImage?] = []
        for seconds in times {
            if Task.isCancelled { break }
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let cgImage = try? await generator.image(at: time).image
            images.append(cgImage.map { UIImage(cgImage: $0) })
        }
        return images
    }

    /// 表紙の1コマ（`poster(of:at:)` の本体）
    fileprivate static func posterDarwin(url: URL, at seconds: Double) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9)
    }

    /// 書き出した動画に位置情報の付帯情報が残っているか。**読めないときは残っているものとして扱う**。
    /// 全体・トラックごとの付帯情報に加え、時刻つきの付帯情報のトラック(撮影地が毎秒入る形)の識別子も見る
    private static func hasLocationMetadata(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        var identifiers: [String] = []
        func collect(_ items: [AVMetadataItem]) {
            for item in items {
                identifiers.append(item.identifier?.rawValue ?? "")
                identifiers.append(item.commonKey?.rawValue ?? "")
            }
        }
        collect((try? await asset.load(.metadata)) ?? [])
        collect((try? await asset.load(.commonMetadata)) ?? [])
        for format in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            collect((try? await asset.loadMetadata(for: format)) ?? [])
        }
        guard let tracks = try? await asset.load(.tracks) else { return true }
        for track in tracks {
            collect((try? await track.load(.metadata)) ?? [])
            for format in (try? await track.load(.availableMetadataFormats)) ?? [] {
                collect((try? await track.loadMetadata(for: format)) ?? [])
            }
            for description in (try? await track.load(.formatDescriptions)) ?? []
            where CMFormatDescriptionGetMediaType(description) == kCMMediaType_Metadata {
                identifiers += (CMMetadataFormatDescriptionGetIdentifiers(description) as? [String]) ?? []
            }
        }
        return identifiers.contains { StoryVideoRules.isLocationIdentifier($0) }
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
