import SwiftUI

/// 「機材から探す」の先（モック9 の「機材から探す状態」）。
///
/// **その焦点距離で撮られた写真**を並べる。分け方は画面の上に1行で出す
/// ——なぜこの写真が並んでいるのかを隠さない。
struct GearPhotosView: View {

    let section: GearGroups.Section

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.group.note)
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.muted)
                    Text(L("焦点距離 \(section.group.range)・\(section.count)枚",
                           "\(section.group.range) · \(section.count) photos"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
                .padding(.horizontal, 16)

                PhotoGrid(photos: section.photos) { photo in
                    PhotoDetailView(photo: photo, context: section.photos)
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(section.group.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}
