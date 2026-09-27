# bugfix-1 の取り込み（保留の枝）— 2026-09-27

この枝 `claude/ios-bugfix-2-ports` は、枝 `claude/ios-bugfix-1` の修正のうち main に無いものを
今の main（2493def）の上に書き直したもの。**main には入れていない（PR も無い）。**

保留にした理由: 作業中に、ほかの8本の枝（`claude/ios-bugs-*`・`claude/design-current-state-comparison-q8w0zp`）が
同じ画面・同じ不具合（人の切り替え・確認コードの欄・ホームの読み込み・投稿の選択ほか）を
同時に直していると分かった。owner の判断で、試験基盤（d2843b5・07034dc）だけを先に PR にし、
ここは**それらの枝が main に入ったあと、そこに無いものだけを見直して取り込む**。

## コミット
- dcd345c 取り込み（1）8件: 投稿の一部失敗で選択に残る（D1）・アルバムの削除確認（C1）・再設定待ちのログイン・
  確認画面の「ログインに戻る」と aliasExists の文（A2）・いいねの控えと seed（C7）・ダブルタップで取り消さない・
  パスワード変更の invalidParameter（A8）・通報シートの案内と WishlistStore の注記（A9・B14）
- cc2da09・0e2e2e3 上のレビューの直し（選択の絞り直し・読み込み中は投稿しない・入口と読み上げ）
- d4bf7ca 取り込み（2）: 公開一覧の取り口の世代・ホームの switchViewer と世代・引き下げの待ち・
  起動時の同期の isStill・TokenFailure・AuthFailure の期限切れの判定順

## d4bf7ca・0e2e2e3 のレビューで出て、まだ直していないもの
- 中: AuthFailure で sessionExpired を先に notAuthorized に畳むと、抱えた種別が userNotFound
  （退会の押し直しで「消せた」扱い）・network（圏外）・limitExceeded の回まで期限切れに倒れる。
  種別が .other に落ちる回だけ期限切れと見る形に絞ること。コミット文の「.other に落ちる」の例
  （userNotFound）も誤り
- 中: TokenFailure は fetchAuthSession 自体が sessionExpired を投げた回を notAuthenticated に畳むだけで、
  main の「期限切れならログアウトに倒す」知らせ（announceSessionExpired）が出ない。idToken 側で拾うこと
- 中: GalleryView の reloadHidden（hidden.revision）が applyRestrictedFeed を通さずに読むので、人の
  切り替え直後に前の人の絞った写真の控えを読みうる（順番は SwiftUI 任せ・未確認）
- 中（試験）: 0e2e2e3 の「1枚も上がらなかった回も絞る」を守る試験が無い（done が空の形）
- 低: 注記が「探す」も差し替えると書くが、探すの移植（SearchView の .task(id:)）はしていない
- 低: setLoadingPickedForTesting が本番の型に公開で載る／いくつかの試験が 50ms の待ちに頼る（偽の合格の向き）

試験は Linux の模型で 951 件緑（d4bf7ca）。本物の Xcode では流していない。
