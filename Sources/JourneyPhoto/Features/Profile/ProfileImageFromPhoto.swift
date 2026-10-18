import Foundation
import UIKit

// Linux では URLSession が別モジュールに居る（`ProfileService` と同じ理由）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 自分の投稿の写真を、アイコン・カバーに使う（#304・2026-10-18）。
///
/// 写真の中身を取り直し、端末から選ぶときと同じ `ImagePreparer` で JPEG にする（位置情報は落ちる）。
/// 上げるのは `ProfileService.uploadProfileImage`（プロフィールの編集の保存と同じ口）
enum ProfileImageFromPhoto {

    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? { L("写真を読み込めませんでした", "Couldn't load the photo") }
    }

    /// 写真の中身（いちばん大きい `src`）を取る
    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
            throw Failure.unreadable
        }
        return data
    }

    /// 取って、上げられる JPEG にする（重いので画面の処理の外で）
    static func preparedJPEG(_ url: URL) async throws -> Data {
        let data = try await download(url)
        return try await Task.detached(priority: .userInitiated) {
            try ImagePreparer.prepare(data: data, fileName: "profile").data
        }.value
    }

    /// 自分の写真（候補の元）。見本の入り方（`PreviewSession`・鍵が無い）では、マイページと同じく
    /// 公開一覧から自分のぶんを選り分ける（`MyPageViewModel.loadPublicly`）
    @MainActor
    static func myPhotos(environment: AppEnvironment) async -> [Photo]? {
        if let previewId = PreviewSession.userId {
            return (try? await environment.gallery.fetchPhotos())?.filter { ($0.userId ?? $0.uploadedBy) == previewId }
        }
        return try? await environment.photos.myPhotos()
    }

    /// その人のアイコン／カバーが置かれているか（HEAD）。**分からない（圏外など）ときは nil**
    static func exists(userId: String, kind: ProfileService.ImageKind) async -> Bool? {
        guard let url = UserProfile.profileAssetURL(userId: userId, suffix: kind == .cover ? "cover" : nil,
                                                    cacheBust: UUID().uuidString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if (200..<300).contains(http.statusCode) { return true }
        // 無いキーは 403（一覧の権限を持たない配り方）か 404
        if http.statusCode == 403 || http.statusCode == 404 { return false }
        return nil
    }

    /// 差し出し（板 51・51b）の「カバーにする」: 取って・上げて・版を替えて・お礼を頼む。成功したら true
    @MainActor
    static func applyCover(photoId: String, url: URL, environment: AppEnvironment, auth: AuthStore) async -> Bool {
        guard let userId = auth.userId else { return false }
        do {
            let jpeg = try await preparedJPEG(url)
            try await environment.profiles.uploadProfileImage(kind: .cover, jpeg: jpeg)
        } catch {
            return false
        }
        ProfileImageVersions.shared.bump(userId)
        CoverOfferStore.shared.noteCoverSet(photoId: photoId, userId: userId)
        auth.noteProfileChanged()
        let trunk = environment.trunk
        await ProfileReward.shared.claim([.cover], userId: userId,
                                         available: TrunkAvailability.shared.isAvailable) { try await trunk.reward($0) }
        return true
    }
}

/// アイコンを丸く切り抜く（板 50b AvatarCrop）。**切り抜きの計算だけ**（画面と分けて試せるように）
enum AvatarCropMath {

    /// 出来上がりの一辺（px）。アイコンは最大 88pt で出る（3x で 264px）ので、余裕をみて 640
    static let outputSide: Double = 640
    /// 拡大の上限（丸に対して）
    static let maxZoom: Double = 4

    /// 丸（一辺 `side`）を埋める最小の倍率で写真を置いたときの、写真の表示の大きさ
    static func fillSize(image: CGSize, side: Double) -> CGSize {
        guard image.width > 0, image.height > 0 else { return CGSize(width: side, height: side) }
        let scale = max(side / image.width, side / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    /// 動かした量を、丸から写真がはみ出さない（丸の中に空きができない）範囲に収める
    static func clamp(offset: CGSize, zoom: Double, image: CGSize, side: Double) -> CGSize {
        let base = fillSize(image: image, side: side)
        let w = base.width * zoom, h = base.height * zoom
        let maxX = max(0, (w - side) / 2), maxY = max(0, (h - side) / 2)
        return CGSize(width: min(maxX, max(-maxX, offset.width)), height: min(maxY, max(-maxY, offset.height)))
    }

    /// 丸に入っている写真の範囲（写真の画素の座標）。丸の一辺は `side`（画面の pt）
    static func cropRect(image: CGSize, side: Double, zoom: Double, offset: CGSize) -> CGRect {
        let base = fillSize(image: image, side: side)
        let z = min(maxZoom, max(1, zoom))
        let o = clamp(offset: offset, zoom: z, image: image, side: side)
        // 画面の 1pt が写真の何画素か
        let perPoint = image.width / (base.width * z)
        let length = side * perPoint
        let centerX = image.width / 2 - o.width * perPoint
        let centerY = image.height / 2 - o.height * perPoint
        return CGRect(x: centerX - length / 2, y: centerY - length / 2, width: length, height: length)
    }

    /// 切り抜いて JPEG にする（EXIF は持たない・`UIGraphicsImageRenderer`）
    static func render(_ image: UIImage, side: Double, zoom: Double, offset: CGSize, quality: Double = 0.88) -> Data {
        let rect = cropRect(image: image.size, side: side, zoom: zoom, offset: offset)
        let out = outputSide
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format)
        return renderer.jpegData(withCompressionQuality: quality) { _ in
            let k = rect.width > 0 ? out / rect.width : 1
            image.draw(in: CGRect(x: -rect.minX * k, y: -rect.minY * k,
                                  width: image.size.width * k, height: image.size.height * k))
        }
    }
}
