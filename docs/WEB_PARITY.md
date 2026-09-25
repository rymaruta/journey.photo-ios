# Web 版との機能の突き合わせ（2026-09-21）

`rymaruta/photo-gallery`（Web）と `rymaruta/journey.photo-ios`（アプリ）を
**両方 grep して**確かめた一覧。推測で「ある」と書かない。

API の口そのものは `Tools/check-api-parity.py` が毎回突き合わせている
（**52 / 52 で一致**）。ここに書くのは**画面と振る舞い**の差。

## 1. 揃っているもの

| 機能 | Web | アプリ |
|---|---|---|
| 写真の一覧・カテゴリ絞り込み | `GalleryGrid` / `FilterBar` | `GalleryView` |
| 写真の詳細（題・説明・撮影地・EXIF・曲） | `PhotoPageClient` | `PhotoDetailView` |
| 拡大表示・左右送り | `GalleryModal` | `PhotoViewerView` |
| いいね / コメント | `usePhotoLikes` / `CommentSection` | `PhotoDetailViewModel` |
| フォロー / フォロワー一覧 | `FollowButton` / `FollowingSheet` | `UserProfileView` / `FollowListView` |
| お知らせ（未読つき） | `NotificationsBell` | `NotificationsView` |
| ストーリー（投稿・閲覧・返信） | `stories/` | `Features/Stories/` |
| 撮影地マップ | `PhotoMap` | `PhotoMapView` |
| フォロー中の流れ | `TimelineFeed`（マイページのタブ） | ホームのフィード切り替え「フォロー中」 |
| 集約（タグ / 撮影地 / カテゴリ / 機材） | `/tag` `/location` `/category` `/camera` | `TagPhotosView` |
| 投稿（切り抜き・タグ・カテゴリ・撮影地・曲） | `/user/upload` | `UploadView` |
| 下書き | `/user/drafts` | マイページの一覧に「下書き」の印 |
| プロフィール編集（アバター・カバー・テーマ色） | `/user/edit` | `ProfileEditView` |
| アルバムと招待 | `/user/albums` `/j` | `AlbumsView` / `InviteView` |
| 通報・ブロック | `ReportDialog` | `ReportSheet` / `BlockedUsersView` |
| 退会・パスワード変更 | `DeleteAccountModal` | `DeleteAccountView` / `ChangePasswordView` |
| ユーザー検索・曲検索・地名検索 | `useUserSearch` ほか | `UserSearchService` / `DiscoveryService` |
| 撮影スポットのガイド（**下書き**） | `/spots` ＋ `/spots/<slug>`（`content/spots.json`・review 段階・noindex） | `OfficialSpotView`（**索引 `app/data/spots.json` だけを読む・v1**）。入口は地図のピン（寄せたとき・名前で絞ったとき）。見どころ・季節・アクセスの本文は出さない。「行きたい」は `SPOT-<slug>` で端末に保存（`SavedSpotKey`＝Web の `savedSpotKey.ts`）し、マイページの一覧にも並ぶ（`OfficialWishlist`） |

## 2. 今日その場で埋めたもの

| 機能 | Web での出どころ | コミット |
|---|---|---|
| 並び替え（新しい順 / 古い順 / 人気順） | `lib/hooks/useGallery.ts` の `sort` | `bd3dc57` |
| おすすめ（カテゴリ別の特集） | `lib/utils/featured.ts` / `FeaturedSections` | `bd3dc57` |
| 機材の集約 `/camera/*` | `lib/utils/collections.ts` | `819451f` |
| どの画面からも投稿できる「＋」 | `PostFab` | `819451f` |
| 写真を2回叩いていいね | `GalleryModal` の `handleImageTap` | `7356a26` |
| いいねした写真をサーバーからも引く | `GET /user/likes` / `useMyServerLikes` | `d49f4cd` |
| 見たストーリーの輪を分ける（アカウントごとの鍵） | `lib/stories.ts` | `87ae54f` |

> **年表（`PhotoTimelineView`）は消した。** 参照がどこからも無くなっていた
> ——マイページの札を 投稿／マップ／お気に入り に替えたときの取り残し。
> 同じ写真を日付で並べ直すだけの見せ方は、`TripBook`（旅の一冊）が
> より強く果たしている。

> `likes` と `featured` は**アプリの `Photo` に項目すら無かった**ので、
> owner が Web で設定してもアプリでは何も起きなかった。

## 3. まだ無いもの（優先度つき）

| # | 機能 | Web での出どころ | 無いと何が起きるか | 見立て |
|---|---|---|---|---|
| 5 | **トップでのタグ絞り込み・キーワード** | `FilterBar` のタグチップと検索欄 | 「さがす」タブに分かれている（機能としては届く） | 中 |
| 6 | **写真の上に文字を置く**（owner の要望） | Web にも無い（`caption` 1本のみ） | 新規。**実装中** | 大 |

### Web にあるがアプリに要らないもの（理由つき）

| 機能 | 要らない理由 |
|---|---|
| `AddToHomeScreenHint` | アプリは App Store から入れる |
| `AssetRecovery`（JS の取得失敗で再読込） | Web の配信の話。アプリの資産は本体に入っている |
| `ErrorBoundary` / `SmoothProgress` | React と画面遷移の作りに依存するもの |
| `DisableSave`（Ctrl+S 抑止） | キーボードの話 |
| `ModalKeyboardHelp` | 同上 |
| `Analytics` | アプリは未導入（入れるなら別途検討） |
| 管理画面 `/admin` | owner の道具。アプリからは触らない |

## 4. この表の作り方

```bash
# Web の画面
find app -name page.tsx | sed 's|^app/||; s|/page.tsx$||' | sort
ls app/components

# アプリ側にあるか（名前ではなく中身で見る）
grep -rli "<名前>" Sources/JourneyPhoto
```

**「あるはず」で書かない。** 実際、`likes` と `featured` は
「読んでいるつもり」で1つも読んでいなかった。
