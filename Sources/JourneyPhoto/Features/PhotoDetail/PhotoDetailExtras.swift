import SwiftUI

/// 写真の詳細の「行き先」の段の下に足す行（札 #710）。`PhotoDetailView` には、これを差し込む1行だけを足す
/// （同じ画面を別の担当も触っているので、中身はこのファイルに置く）。
///
/// - 案9: 人の写真が自分の行きたい場所なら「あなたの行きたい場所です　話す ›」（`FriendWishPhotoLine`）
/// - 案10: 写真の色の日本の色の名前と由来の1行、「この色の写真 ›」（`JapaneseColorLine`）。投稿の前のプレビューの「詳細」も
///   同じ写真の詳細の部品なので、そこにも出る
struct PhotoDetailExtras: View {
    let photo: Photo

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            FriendWishPhotoLine(photo: photo)
            JapaneseColorLine(photo: photo)
        }
        // 写真ごとに作り直す（束を送ったとき、前の写真の行を残さない）
        .id(photo.id)
    }
}
