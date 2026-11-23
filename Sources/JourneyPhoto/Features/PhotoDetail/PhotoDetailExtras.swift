import SwiftUI

/// 写真の詳細の「行き先」の段の下に足す行（札 #710）。`PhotoDetailView` には、これを差し込む1行だけを足す
/// （同じ画面を別の担当も触っているので、中身はこのファイルに置く）。
///
/// - 案9: 人の写真が自分の行きたい場所なら「あなたの行きたい場所です　話す ›」（`FriendWishPhotoLine`）
struct PhotoDetailExtras: View {
    let photo: Photo

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            FriendWishPhotoLine(photo: photo)
        }
        // 写真ごとに作り直す（束を送ったとき、前の写真の行を残さない）
        .id(photo.id)
    }
}
