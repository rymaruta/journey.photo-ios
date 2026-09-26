import SwiftUI

/// 「いまの季節の写真」の先（板 11 の「すべて」）。いまの季節のタグが付いた写真を
/// 新しい順に全部（`DiscoverySections.seasonal`）
struct SeasonalPhotosView: View {

    let photos: [Photo]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("いまの季節のタグが付いた写真・\(photos.count)枚",
                       "Photos tagged for this season · \(photos.count)"))
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 16)

                PhotoGrid(photos: photos) { photo in
                    PhotoDetailView(photo: photo, context: photos)
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(L("いまの季節の写真", "This season"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
