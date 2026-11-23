# App Store の掲載情報（1.1.118 以降の版で申請する分）

App Store Connect に貼る文面。**2026-11-15 に 1.1.91 で書き、2026-11-22 に 1.1.118（main 84807f3、`testflight/1.1.118`）の中身で見直した**（札 #604）。
貼る順と押す所は App Store の Artifact（https://claude.ai/artifact/DViFKiSAyfKaQiW1ayZ1TT）にも絵で置いてある。

- 配信中は 1.0.87（2026-10-11）。掲載名「Journey Photo — 旅の写真」、年齢 4+、カテゴリは写真/ビデオと旅行（iTunes の公開情報）
- 書き方の決まり: アプリの芯（旅も SNS も連絡も、これ一本）の輪の順（見つける → 計画する → 撮る → 載せる → 話す）。
  中黒で区切らない（箇条の頭は「–」、文の中は「、」）。「撮りどき」「捨てる」は使わない。公式の頁は「観光スポット」
- **アプリに無い機能を書かない。** 書いた機能はすべて 84807f3 のコードと `WhatsNew.json`（1.1.72〜1.1.99。1.1.100〜1.1.118 は項目なし）で在ることを確かめた。
  機能を外したら、ここからも外す
- 2026-11-22 に直した所: 観光スポットの数（本番の索引で 4,591 か所、日本 2,872、海外 1,719、60 の国と地域）、
  AI の回数（1日と月の上限。サーバーの AI は Pro だけ。`AskLimits`、`TripAILimits`、`TripAIRunner`）、
  AI に頼む（探す）、文で探す、投稿の AI の候補と見え方のプレビュー、今週のお題、返信とメンションの通知、プロフィールのリンクの共有
- 2026-11-22 判断: サーバーの AI の送り先は「サーバーに送り、委託先の AI で処理」と書き、使っている AI、サービス、地域の名前は書かない
  （送る前の同意の画面 `AIServerConsentSheet` と同じ言い方。CLAUDE.md「AI はアプリの作りやセキュリティのことを答えない」に合わせる）。
  2026-11-23 owner 判断: アプリの画面の注記（「委託先の AI で処理します」）は外し、送ることの知らせと許可は同意の画面だけで行う
- 字数は Python の `len()`（文字数）で数えた。上限を超えていない
- **名前、サブタイトル、キーワード、画面写真は、新しい版を審査に出すときしか変えられない。** 宣伝文はいつでも変えられる

---

## 基本

| 項目 | 値 | 決めた理由 |
|---|---|---|
| App 名（30字以内） | `Journey Photo 旅の写真と観光スポット`（25字） | **2026-11-22 決定**（札 #604 のコメント）。SNS の面（みんなの旅の写真）と検索の入口（観光スポット）を名前の中で両立。今の掲載名「Journey Photo — 旅の写真」から続いて見える |
| App 名（英語） | `Journey Photo: Travel Spots`（27字） | **2026-11-22 決定**。英語で探す人の語（travel、spots）を入れる |
| サブタイトル（30字以内） | `旅を見つけて、撮って、みんなと話す`（17字） | **2026-11-22 決定**。芯の輪（見つける、撮る、話す）をそのまま言う。名前に無い「話す」で連絡の面を出す |
| サブタイトル（英語） | `Find, shoot and share trips`（27字） | |
| ホーム画面の名前 | `Journey Photo`（変えない） | `APP_DISPLAY_NAME` |
| Bundle ID | `com.journeyphoto.JourneyPhoto` | |
| プライマリ言語 | 日本語（英語も入れる） | |
| カテゴリ | 主: 写真/ビデオ、第2: ソーシャルネットワーキング | 推奨。使い方の中心が投稿、ストーリー、メッセージになった。旅行の検索語は名前とキーワードで取れる。迷うなら今のまま（第2: 旅行）でも審査には響かない |
| 年齢区分 | 質問票の結果に従う（`docs/APP_REVIEW.md` の答え）。UGC とメッセージは「あり」 | |
| 価格 | 無料（App 内課金: Journey Photo Pro 月額 500円、年額 5,000円） | |
| サポート URL | `https://journey-photo.com/privacy` | 末尾の「お問い合わせ」にメールがある。`/support` と `/contact` は 404（2026-11-15 に確かめた） |
| マーケティング URL | `https://journey-photo.com` | |
| プライバシーポリシー URL | `https://journey-photo.com/privacy` | 2026-11-15 版でアプリ 1.1.91 の取り方に合わせた（journey.photo-web #650） |
| 利用規約（EULA の欄か説明文） | `https://journey-photo.com/terms` | 定期購入の審査 3.1.2 で要る。説明文の末尾にも入れた |
| 著作権 | `2026 Journey Photo` | |

**名前、サブタイトル、キーワードで同じ語を二度使わない。** App Store は3つを合わせて検索に使う。

## プロモーション用テキスト（170字以内、審査なしで変えられる）

2026-11-15（札 #621・owner「登録してもらう入口に」）: AI の旅行プランを先頭に置いた。

日本語（106字）:

```
「来月、金沢に1泊2日。紅葉」と書くだけで、AI が観光スポットから旅行プランを組みます。みんなの写真から次の行き先を見つけて、撮った写真を載せ、ストーリーやメッセージで話せます。観光スポットは約4,600か所。
```

英語（153字）:

```
Write one line like "Kanazawa, 2 days, autumn leaves" and AI plans your trip from real spots. Find places in everyone's photos, post your shots and chat.
```

## 説明（4000字以内）

日本語（約3,100字）:

```
旅先で出会った一瞬を載せて、みんなの写真から次の行き先を見つける。旅の計画も、写真の投稿も、仲間との連絡も、Journey Photo ひとつで。
見るだけなら、ログインは要りません。

■ AI で旅行プランを作る
– 「来月、金沢に1泊2日。紅葉」のように書くだけで、観光スポットから日ごとの日程ができます
– AI は台帳の観光スポットと行きたい場所から選んで並べ、並べた理由を1行添えます。無い場所は作りません
– 移動が無理な順は Apple のマップの目安で外し、「戻す」で戻せます
– 「直したいことを書く」で、日程をそのまま直せます
– 対応する iPhone では端末の中の AI（Apple Intelligence）で組み、文を送りません。それ以外の iPhone では、Pro なら頼みの内容と日程をサーバーに送り、委託先の AI で組みます
– 回数はログインして1日5回、月30回まで。Pro なら1日20回、月300回

■ みんなの写真から見つける
– ホームは1本の並び。フォロー中の人の新しい写真、選ばれた写真、いいねの多い写真が続き、3日以内の新しい投稿も混ざります
– ホームの上の札に、週ごとに替わる「今週のお題」。「参加する」でお題のタグを入れて投稿できます
– 観光スポットは約4,600か所。日本の47都道府県で約2,900か所、海外60の国と地域で約1,700か所
– 探すで「京都 紅葉 夜」のように打つと、季節や時間帯で絞り込みます
– 探すの「AI に頼む」で、旅のことを文で頼めます（ログインして1日3回、月10回まで。Pro なら1日20回、月300回）
– 地方と県から一覧に。日本地図から地方を選ぶことも、名前で絞ることもできます
– 作例写真には、作者と出典を表示しています
– 日の出と日の入り、ゴールデンアワーとブルーアワーの時刻、太陽の方角
– ホームの札で観光スポットを1枚ずつ払って、行きたい場所へ。頁には今月の「行きたい」の数が出ます
– 撮影地マップで、旅先の近くの写真を探せます
– 毎日の今日の一問「この写真はどこ？」

■ 旅行プランを立てる
– 観光スポットや行きたい場所から、日付を選んでそのまま入れられます
– 場所を足す画面で探して、押すだけで日程へ
– ≡ を持って運ぶと、順番や日を入れ替えられます
– 場所と場所の間に移動の目安。押すと Apple のマップで経路が開きます
– 招待リンクで仲間を誘って、日程を一緒に直し、プランの中で話せます
– メッセージで送り合った写真や観光スポットから、プランの下書きも作れます

■ 撮る、載せる
– 旅の写真も、日常の好きな一枚も、気軽に投稿できます
– 作例を重ねて撮るカメラと、作例つきの構図の一覧
– 対応する iPhone では、題や説明やタグの候補を端末の AI が出します。写真は外に送りません
– 投稿する前に、写真の詳細、ホーム、マイページでの見え方をプレビューできます
– 投稿したあとも色を編集でき、編集中は元の写真と見比べられます。下書きはいくつでも残せます
– 投稿したら、すぐ SNS に載せられるカード。額装、フィルム、縦書きなどの形から選べます
– 見せたい写真は、プロフィールの先頭にピン留め
– 写真ファイルに埋め込まれた位置情報は端末の中で取り除いてから送り、撮影地は約1kmに丸めて保存します

■ ストーリー
– 写真と、60秒までの動画。ストーリーの「＋」で最近の写真と動画が並び、最初のマスがカメラです
– ズーム、フラッシュ、タイマー、動画の切り取り、フィルター、手描き
– 曲の札（30秒の試聴）、投票、場所の札
– 顔の輪から開いて、絵文字ですぐ反応。返信はメッセージに残ります
– ハイライトで残したり、親しい友達だけに見せたりできます

■ 話す
– いいね、コメント（返信もできます）、フォロー、保存。返信やメンションは通知で届きます
– フォローしている人と、1対1のメッセージ
– 写真や観光スポットを送れます。届いた観光スポットは、すぐ行きたい場所に
– 相手が承認するまでは文字3通までで、リンクは送れません
– 送ったメッセージは取り消せます。会話からその場で通報、ブロックもできます
– プロフィールの QR コードとリンクで、会った人とすぐつながれます

■ 旅を残す
– 写真へのアクセスを許可すると、過去の旅が一冊ずつマイページの棚に並びます。調べるのは端末の中だけで、写真も位置もどこにも送りません
– ホームの「まだ載せていない旅」から、旅の写真を1枚ずつ払って選べます
– 旅の一冊と、招待リンクで仲間と写真を集める共同アルバム
– 行った県を日本地図に塗って、回数を記録（あなただけの記録です）
– 自分の旅の1枚を、搭乗券や切手の形にしてストーリーへ

■ 旅のトランクと、とおまわり号
– 公開で投稿すると硬貨がもらえ、カプセルの機械に入れるとトランクの部品が出てきます。硬貨と部品は購入できません
– キャンピングカー「とおまわり号」に家具を置いて、額に自分の写真を飾れます

■ すれちがい乗車券（任意、初期設定はオフ）
– オンにした人だけ、近くにいる Journey Photo の利用者と、選んだ公開写真1枚とひとことを Bluetooth で交換します。位置や連絡先は送りません
– カードはその場で届きます。夕方にまとめて受け取ることもできます

■ Journey Photo Pro（任意、自動更新の定期購入）
– AI に頼む、旅行プランを作る：それぞれ1日20回、月300回まで（無料は、AI に頼むが1日3回と月10回、旅行プランが1日5回と月30回）。端末の AI が使えない iPhone でも、サーバーの AI で答えます
– 光と天気の知らせ：行きたい場所が「明日の朝、晴れて朝焼け」なら前の晩に
– 電波なしで使える旅：地図、作例、光の時刻を端末に
– Pro マークと Pro 限定の章
– 特別な乗車券：真鍮、漆、革などの券面
– 旅のトランクをもっと：特別なトランク6型、ラベルの図柄の作り直し月3回、手持ち150枚（無料は30枚）
– 月額500円、年額5,000円。無料の試用はありません
– お支払いは購入の確定時に Apple ID に請求されます。期間が終わる24時間前までに解約しない限り、自動で更新されます。解約と管理は App Store のアカウント設定から行えます。ファミリー共有には対応していません
– 作例を重ねて撮るカメラは、Pro でなくても使えます
利用規約: https://journey-photo.com/terms
プライバシーポリシー: https://journey-photo.com/privacy

■ 安心して使うために
– アカウントが無くても、写真、検索、地図、観光スポットを見られます。投稿、いいね、コメント、フォロー、メッセージには、メールアドレスでの登録が必要です
– 写真、コメント、ストーリー、メッセージ、旅行プランの会話、プロフィールは通報でき、相手をブロックできます。ブロックは設定からいつでも解除できます
– 検索エンジンにプロフィールを出さない設定があります
– アカウントはアプリ内から削除できます
– 設定の「意見を送る」から、運営に声を届けられます
```

英語（約3,990字。2026-11-15 に AI の節を足し、細かい5行を外して4000字に収めた。2026-11-22 に AI に頼むと文で探すを足し、県の地図と地方からの一覧の2行を外した）:

```
Share moments from your trips and find your next destination in everyone's photos. Plan trips, post and keep in touch with travel friends, all in one app. No account is needed to browse.

PLAN TRIPS WITH AI
- Write one line like "Kanazawa, 2 days, autumn" and get a day-by-day plan from real spots. AI never makes places up
- Runs on device with Apple Intelligence where supported; otherwise, with Pro, on our servers via an AI provider
- With an account, 5 plans a day and 30 a month; with Pro, 20 a day and 300 a month

FIND IDEAS IN EVERYONE'S PHOTOS
- Home is one feed: new photos from people you follow, then featured and popular photos
- About 4,600 sightseeing spots: about 2,900 across all 47 prefectures of Japan and about 1,700 in 60 other countries and regions
- Search with a sentence like "Kyoto autumn night", or Ask AI in Search
- Sample photos credit the photographer and source
- Swipe through spots on Home and save them to "Want to go"

PLAN TRIPS
- Add spots on the day you choose, or search and add places
- Drag the ≡ handle to reorder places or move them to another day
- Travel times between places; tap to open the route in Apple Maps
- Invite friends with a link to edit the plan together and chat inside it

SHOOT AND POST
- Post travel shots or any everyday photo you love
- A camera that overlays sample compositions, plus a guide to compositions
- On-device AI suggests a title and tags where supported. Preview your post before you share it
- Edit colors after posting and compare with the original. Keep as many drafts as you like
- Share cards right after you post, with Mat, Film, Vertical and more
- Location data in the photo file is removed on your device before upload; a photo's place is stored rounded to about 1 km

STORIES
- Photos and videos up to 60 seconds, from your recent photos or the camera
- Song stickers (30-second previews), polls and place stickers
- React with an emoji; replies stay in Messages
- Highlights and Close friends

TALK
- Likes, comments with replies, follows and saves
- Chat one to one with people you follow
- Send photos and spots, and save a spot you receive to "Want to go"
- Until someone accepts, you can send up to 3 text messages, without links
- Unsend messages. Report or block from a conversation

KEEP YOUR TRIPS
- Allow photo access and your past trips line up as books on My Page. Photos are checked only on your device
- Trip books and shared albums

TRAVEL TRUNK AND DETOUR
- Earn coins by posting publicly and get trunk parts from the capsule machine. Coins and parts cannot be bought
- Decorate Detour, your camper, with furniture and your own photos

PASS (OPTIONAL, OFF BY DEFAULT)
- Only if you turn it on, your phone swaps a ticket card with nearby Journey Photo users over Bluetooth: one public photo you chose and a short note. No location or contacts are sent

JOURNEY PHOTO PRO (OPTIONAL, AUTO-RENEWABLE SUBSCRIPTION)
- Ask AI and AI trip plans: 20 a day and 300 a month each, on any iPhone
- Light and weather alerts for places you want to go
- Offline trips
- A Pro mark and Pro-only chapters
- Special Pass ticket designs
- More from your Travel trunk: 6 special trunks, 3 label redesigns a month, room for 150 labels (30 for free)
- 500 yen per month or 5,000 yen per year. No free trial. Payment is charged to your Apple ID at confirmation of purchase and renews automatically unless canceled at least 24 hours before the end of the period. Manage or cancel in your App Store account settings. Family Sharing is not supported
- The composition-overlay camera is free for everyone
Terms of Use: https://journey-photo.com/terms
Privacy Policy: https://journey-photo.com/privacy

FEEL SAFE
- Browse without an account. Posting, likes, comments, follows and messages need an email sign-up
- Report photos, comments, stories, messages, trip plan chats and profiles, and block people. Unblock anytime in Settings
- Hide your profile from search engines
- Delete your account in the app
```

## キーワード（100字以内、カンマ区切り、空白なし）

名前とサブタイトルにある語（Journey、Photo、旅、写真、観光、スポット、見つけ、撮って、みんな、話す）は入れない。
他社のアプリ名や商標（インスタなど）は入れない（審査 2.3.7）。

日本語（99字）:

```
旅行,旅行プラン,しおり,絶景,撮影,撮影地,フォトスポット,桜,紅葉,夜景,星空,夕日,ゴールデンアワー,カメラ,風景,映え,地図,共有,ストーリー,メッセージ,DM,行った県,おでかけ,海外旅行
```

英語（98字。journey、photo、travel、spots、find、shoot、share、trips は名前とサブタイトルにある）:

```
japan,sightseeing,golden hour,sunrise,sunset,sakura,autumn,landscape,camera,map,itinerary,story,dm
```

## このバージョンの最新情報（1.0.87 の人が読む）

日本語:

```
秋からの大きな更新です。旅の写真の SNS として、たくさんの機能が加わりました。

– 画面のデザインを新しくしました。黒と白に真鍮の差し色で、写真がいちばん引き立ちます
– ホームは1本の並びに。フォロー中の人の新しい写真から順に続きます
– 観光スポットは約4,600か所に。日本の47都道府県と、海外60の国と地域。地方と県から一覧に、日本地図からも探せます
– AI で旅行プラン：行き先を書くか札を押すだけで、観光スポットから日程を組みます
– 探すで「京都 紅葉 夜」のように文で探せます。「AI に頼む」で旅のことを聞くこともできます
– 投稿の前に見え方をプレビュー。対応する iPhone では、題やタグの候補を端末の AI が出します
– ホームに「今週のお題」。返信やメンションも通知で届きます
– メッセージ：フォローしている人と1対1でやりとりできます。写真や観光スポットも送れて、送信の取り消しもできます
– ストーリー：60秒までの動画、ズーム、フラッシュ、タイマー、切り取り、フィルター、手描き、曲の札、投票。顔の輪から開いて、絵文字ですぐ反応
– 旅行プラン：観光スポットから日付を選んで入れる、探して足す、≡ で並べ替え。場所の間の移動の目安を押すと Apple のマップで経路が開きます。招待リンクで仲間と一緒に直して、プランの中で話せます
– 写真へのアクセスを許可すると、過去の旅が一冊ずつマイページの棚に並びます。写真は端末の中で調べるだけで、どこにも送りません
– 行った県を日本地図に塗って、回数を記録できます
– 投稿したらすぐ SNS に載せられるカード。額装、フィルム、縦書きなどの形から選べます
– コメントへの返信、プロフィールのピン留め、QR コード、おすすめの人
– 旅のトランクと、キャンピングカー「とおまわり号」の中に入れるように
– すれちがい乗車券（初期設定はオフ）：オンにした人だけ、近くの人と公開写真1枚を交換。カードはその場で届きます
– Pro に、特別な乗車券と旅のトランクの特典が加わりました。作例を重ねて撮るカメラは、Pro でなくても使えます
– 設定に「意見を送る」と「検索エンジンにプロフィールを表示しない」
– 電波が無いときも見やすく、大きい文字でも読みやすく、動きを軽くしました。細かな使いやすさも見直しています
```

英語:

```
A big update since the fall, with many new ways to share travel photos.

- A refreshed look: black and white with a brass accent, so your photos stand out
- Home is now one feed, starting with new photos from people you follow
- About 4,600 sightseeing spots, across all 47 prefectures of Japan and 60 other countries and regions
- AI trip plans: write a destination or tap a card, and get days planned from real spots
- Search with a sentence like "Kyoto autumn night", or Ask AI about your trip
- Preview your post before you share it. On-device AI suggests a title and tags where supported
- This week's theme on Home, and notifications for replies and mentions
- Messages: chat one to one with people you follow. Send photos and spots, and unsend messages
- Stories: videos up to 60 seconds, zoom, flash, timer, trimming, filters, drawing, song stickers and polls
- Trip plans: add spots on the day you choose, search and add places, and reorder with the ≡ handle. Tap the travel time to open the route in Apple Maps. Invite friends with a link to edit together and chat inside the plan
- Allow photo access and your past trips line up as books on My Page. Photos are checked only on your device
- Color in the prefectures you have visited on a map of Japan
- Share cards right after you post, with Mat, Film, Vertical and more
- Replies to comments, pinned photos, a profile QR code and suggested people
- Your Travel trunk, and you can step inside Detour, your camper
- Pass (off by default): swap one public photo with people nearby, only if you turn it on
- Pro now includes special Pass tickets and Travel trunk extras. The composition-overlay camera is free for everyone
- "Send feedback" and "Hide my profile from search engines" in Settings
- Better offline screens, easier reading with larger text, a lighter app, and many small fixes
```

## 画面写真

**今の Apple の決まり（2026-11-15 に developer.apple.com の「Screenshot specifications」で確かめた）:**
iPhone だけのアプリ（`TARGETED_DEVICE_FAMILY: "1"`）は、**6.9インチ**（iPhone with Dynamic Island の大きい画面）の1組を出せば足りる。
出さないときだけ 6.5インチが要る。1枚から10枚、PNG か JPEG（透過なし）。

| 枠 | 受け付ける寸法（縦） | 機種 |
|---|---|---|
| 6.9インチ | **1320×2868**、1290×2796、1260×2736 | 17 Pro Max、16 Pro Max、Air など |
| 6.5インチ | 1284×2778、1242×2688 | 6.9 を出せば要らない |

出す絵は `Tools/store-screenshots.py` が、撮った画面を黒地に置き、真鍮の眉ラベルと明朝の見出しを足して**必ず 1320×2868** で作る
（材料の画面の寸法がシミュレータの機種で変わっても、出す絵の寸法は変わらない）。

### 並び（2026-11-15 に決めた。芯の輪の順。検索結果に出るのは最初の3枚）

| 順 | 画面 | 材料（`ScreenshotTests` の絵の名前） | 上に置く見出し |
|---|---|---|---|
| 1 | ホーム（みんなの写真の1本の並び） | `10-ホーム` | みんなの写真から、次の旅へ |
| 2 | 観光スポットの頁（作例と光の時刻） | `70-ストア・撮影スポット（鍋ヶ滝）` | 行きたい場所が、きっと見つかる |
| 3 | 旅行プラン（日程と移動の目安） | `66c-旅行プラン（仲間と共有・日程）` | 仲間と一緒に、旅を組み立てる |
| 4 | 投稿（写真の編集の入口） | `42-投稿（写真の編集の入口）` | 撮った一枚を、すぐ載せる |
| 5 | ストーリー（曲の札） | `62a-ストーリーの曲の札` | 24時間のストーリーで、旅の今を |
| 6 | メッセージ（会話） | `86m4-メッセージ（会話）` | 旅の仲間と、そのまま話せる |
| 7 | 写真の詳細 | `20-写真の詳細` | 一枚の向こうの場所まで |
| 審査用 | Pro の案内 | `81-Pro の案内` | （課金の審査に出す。並びには入れない） |

**写真の権利（CLAUDE.md「他人の写真は、その人のもの」・絶対）。** ストア用の絵には、**本番の他の利用者の写真を1枚も入れない**。
目で見て選ぶ形にはしない。絵に出してよいのは、アプリ内の見本のデータか、運営が権利を持つ写真だけ。人の顔、他社のロゴも入れない。

> 🔴 **2026-11-22 時点で、いまの `storeShots` の絵はストアに使えない。** 材料を撮る UI テストは、`-JPSiteBaseURL https://journey-photo.com` で
> 本番の公開写真（ホーム、写真の詳細）、本番の観光スポットの作例（Commons などの他の作者）、実在の利用者（`ScreenshotTests.previewUserId`）の写真で描く。
> 見本のデータだけで描く仕組み（ストア用の回だけ）はまだ無い。要るものは札 #604 に書いた。できるまで、出た絵はストアに上げない

### 作り方（2026-11-22 から CI で作る。札 #604）

Mac の CI（`ios-testflight.yml`）を `storeShots: true`、`submit: false` で流す:

```
gh api -X POST repos/rymaruta/journey.photo-ios/actions/workflows/ios-testflight.yml/dispatches \
  -f ref=main -f 'inputs[submit]=false' -f 'inputs[storeShots]=true' -f 'inputs[screens]=none'
```

- 流すのは材料を撮る UI テスト6本と起動の見張りだけ（`Tools/store-screenshots.py` の `STORE_TESTS`）。単体テスト、Archive、署名は流さない。
  `screens` の値は使わない（`none` でよい）。`submit: true` と一緒にすると最初の段で止まる
- 出来た絵は**非公開の S3** の `<run 番号>/store.tar`（画面写真と同じ置き場、**3日で自動で消える**）。公開の枝、成果物、ログには置かない
- 取り出し: `bash Tools/fetch-shots.sh <run 番号>` → scratchpad の `shots/<run 番号>/store/` に、上の7枚（`01-ホーム.png` 〜 `07-写真の詳細.png`）、
  審査用の `review-Pro の案内.png`（原寸）、寸法の控えの `README.md`
- App Store Connect に上げ終わったら `bash Tools/fetch-shots.sh <run 番号> --delete`（手元と S3 からすぐ消す）
- 材料が1枚でも足りないと、その回は赤になる（足りない絵の名前が job のログに出る）

**見本のデータだけで描く仕組みができるまで、`storeShots` の回は最初の段で赤になって止まる**（上の「写真の権利」。`ios-testflight.yml` の「App Store 用の絵は見本で描けるまで止める」）。

## レビュー用の追記

`docs/APP_REVIEW.md` を見ること。審査メモの文面、審査用アカウントの作り方、ガイドライン別の対応、
App のプライバシーの答え、年齢区分の答えが書いてある。
