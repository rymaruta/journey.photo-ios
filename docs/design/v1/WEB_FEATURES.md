# photo-galleryから取り入れる機能

調査基準は d1fd52c7f9d0009877a7ecac577b6d1560e81d38。APIのソースと構成を確認した。本番へのデプロイ・認証付き疎通は未検証。

| 採用 | 体験 | 公開条件 |
|---|---|---|
| 行きたい場所の同期 | 写真の保存と分け、WebでもiOSでも同じ候補を見る。画像17 | 認証・既存slug規約・競合と移行を実装 |
| 非公開の旅行プラン | 場所を日ごとに並べ、短いメモを残す。画像18 | API接続と失敗時の入力保持 |
| 出典のある撮影ガイド | 投稿写真と公式情報を分ける。未登録時は画像19 | 公開用データ契約と審査済みガイド |

## 行きたい場所

[API](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/api-user/src/savedSpots.ts)、[クライアント](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/lib/hooks/useSavedSpots.ts)、[ルーティング](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/api-user/serverless.yml)。GET /user/spots は {slugs}、POST /user/spots は {slug}、DELETE /user/spots/{slug} は削除。書込結果は {saved,slugs}。

iOSのWishlistStoreはアカウント別UserDefaults。サーバー取得が成功してから既存ローカル値を一度だけマージする。失敗時に空一覧で上書きしない。サインアウト・別アカウントで混ぜない。spotIdと地名slugのWeb側の符号化を確認し、勝手に同一視しない。「同期済み」は応答成功後だけ表示する。

## 旅行プラン

[API](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/api-user/src/tripPlans.ts)、[Web画面](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/app/trips/TripsClient.tsx)、[フック](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/lib/hooks/useTripPlans.ts)。GET/POST /user/trips、PUT/DELETE /user/trips/{planId}。一覧は {plans}。

TripItemは {kind:'spot',spotId,note?} または {kind:'location',slug,note?}。daysは {date?,items[]}。プランにplanId、ownerId、title、startDate/endDate、days、visibility:'private'、createdAt、updatedAt。タイトル100文字、60日、1日20件、メモ200文字、50プラン、1プラン128KB・行350KBの制限を維持する。

既存のiOS TripsView/TripBookは過去の写真を振り返る機能。新しいTripPlanとはモデルも導線も分ける。共同編集・公開共有・AI自動行程・正確な移動時間はこのAPIが提供していないので本版に含めない。

## 撮影ガイド

[データ型](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/lib/data/spots.ts)、[検証規約](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/lib/utils/spotGuide.ts)、[表示](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/app/components/SpotGuideClient.tsx)、[登録データ](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/content/spots.json)。調査時点の登録データは空配列。画像19はその状態を正直に表す。

アクセス・駐車場・安全情報は項目別の出典URLとcheckedAtを要求する。公開判定はstatus、slug、verifiedAt、位置、地域、要約、見どころ、アクセスの出典等を既存の検証規約に合わせる。架空の営業時間・撮影許可・安全情報を埋めない。投稿写真は公式カバーとして扱わない。

iOSの写真由来DerivedSpotだけでは不足。公開APIまたは静的JSONの契約、ライセンス、更新方式を決めてから有効化する。現段階でガイドが利用可能と宣伝しない。

## 継続する機能

[色から探す](https://github.com/rymaruta/photo-gallery/blob/d1fd52c7f9d0009877a7ecac577b6d1560e81d38/app/components/ColorJourney.tsx) は参考になるが、iOSにもColorFamilies・検索導線がある。新機能として重複追加せず、分類品質を後で合わせる。アルバム・ストーリーも既存導線を維持する。サイトアイコンは変更しない。
