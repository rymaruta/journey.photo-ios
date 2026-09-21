import SwiftUI

/// 「この写真に近いもの」。同じ撮影地 → 同じタグ、の順に拾う。
struct RelatedPhotosRow: View {

    let photo: Photo
    /// 見出し「近い写真」を付けるか。**タブの中身として置くときは外す**
    /// ——タブの札が既に「関連写真」と言っているので二重になる
    var showsHeading = true

    @EnvironmentObject private var environment: AppEnvironment
    @State private var related: [Photo] = []
    /// 一度でも引き終えたか。**読み込み中と0件を分ける**ためのもの
    /// ——以前は空なら何も描かず、「まだ来ていない」のか「無い」のか
    /// 画面から分からなかった
    @State private var loaded = false

    var body: some View {
        Group {
            if !related.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if showsHeading {
                        Text(L("近い写真", "Similar photos")).font(.subheadline.weight(.semibold))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(related) { item in
                                NavigationLink {
                                    PhotoDetailView(photo: item)
                                } label: {
                                    RemoteImage(url: item.gridImageURL, alignment: item.gridAlignment)
                                        .frame(width: 96, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } else if !showsHeading {
                // 見出し付き（縦並び）のときは空を隠したままでよいが、
                // タブの中身が真っ白だと壊れて見える。無いなら「無い」と出す
                if loaded {
                    Text(L("近い写真はまだありません", "No similar photos yet"))
                        .font(.callout)
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
        .task(id: photo.id) {
            let all = (try? await environment.gallery.fetchPhotos()) ?? []
            related = PhotoQuery.related(to: photo, from: all)
            loaded = true
        }
    }
}
