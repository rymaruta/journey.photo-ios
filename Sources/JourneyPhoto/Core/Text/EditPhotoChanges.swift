import Foundation

/// 写真の編集（`EditPhotoView`）の欄から、保存で送る差分を作る。
///
/// **送る差分と「未保存の変更があるか」を1つの判断にする。** 以前は差分を画面の
/// `save()` の中で組んでいて、閉じるとき（「閉じる」・下へ払う）は何も見ずに閉じていた
/// ——題や撮影地を直したあと払うと、確かめもなく消えた。閉じるときの判断を別に
/// 書くと「送る差分は空なのに確認が出る」「差分があるのに黙って閉じる」が割れるので、
/// 同じ関数の `isEmpty` で決める（`hasChanges`）。
///
/// 判定を画面の外に置くのは、Linux の模型では画面を動かせず試験できないため。
enum EditPhotoChanges {

    /// 欄に入っている姿
    struct Fields: Equatable {
        var title: String
        var caption: String
        var location: String
        var pickedCoords: Photo.Coords?
        var tagsText: String
        var category: String
        var date: String
        var published: Bool
        var audience: Audience

        init(title: String, caption: String, location: String, pickedCoords: Photo.Coords?,
             tagsText: String, category: String, date: String, published: Bool, audience: Audience) {
            self.title = title
            self.caption = caption
            self.location = location
            self.pickedCoords = pickedCoords
            self.tagsText = tagsText
            self.category = category
            self.date = date
            self.published = published
            self.audience = audience
        }

        /// 開いたときの欄（画面の初期値）。**知らない公開範囲は「全体」で置く**
        /// ——その段は出さず、送りもしない（`openedAudience` が nil）
        init(opening photo: Photo) {
            self.init(title: LocalizedEdit.titleField(photo.title),
                      caption: LocalizedEdit.descriptionField(photo.description),
                      location: photo.location ?? "",
                      pickedCoords: nil,
                      tagsText: (photo.tags ?? []).joined(separator: ", "),
                      category: photo.category ?? "",
                      date: EditDay.field(date: photo.date),
                      published: photo.published != false,
                      audience: EditPhotoChanges.openedAudience(photo) ?? .everyone)
        }
    }

    /// 開いたときの公開範囲。**知らない値なら nil**（触らせない・送らない）
    static func openedAudience(_ photo: Photo) -> Audience? {
        let raw = photo.audience ?? ""
        return raw.isEmpty ? Audience.everyone : Audience(rawValue: raw)
    }

    /// 保存で送るもの。**変えた項目だけ**（各項目の決まりは下の注記と、それぞれの型）。
    ///
    /// - Parameter openedAudience: 開いたときの公開範囲。知らない値なら nil（`EditVisibilityRules`）
    /// - Parameter spots: 撮影スポットの索引（座標を消すかの判断・`EditPlaceRules.clearsCoords`）。無ければ空。
    ///   **nil は読めなかった（時間切れ）**——書き換えた撮影地の座標を消さない
    static func patch(photo: Photo, openedAudience: Audience?, fields f: Fields,
                      spots: [OfficialSpot]? = []) -> PhotoPatch {
        var patch = PhotoPatch()
        // **触った欄だけ、英語側を残して送る**（`LocalizedEdit`）。
        // 表示用の1言語を平文で送っていたので、`{ja, en}` の写真を
        // 保存するたびに英語の題と説明が消えていた
        patch.title = LocalizedEdit.title(original: photo.title, field: f.title)
        patch.description = LocalizedEdit.description(original: photo.description, field: f.caption)
        // **変えた項目だけ送る**（Web の `/user/edit` の `changedFields` と同じ）。
        // 開いた時点の値を毎回全部送っていたので、古い写し（公開 JSON は
        // 建て直しまで古い）から開いてタグだけ直すと、Web で直した説明や
        // 撮影地が黙って巻き戻っていた
        if f.location != (photo.location ?? "") || f.pickedCoords != nil {
            patch.location = f.location
        }
        // **選んだ回だけ載せる。** nil は「触らない」なので、
        // 地名を手で直しただけの回に既存の座標を壊さない
        patch.coords = f.pickedCoords
        // **本人が撮影地を空にした・書き換えたら座標も消す。** nil だけでは「触らない」になり、
        // 地図とページにピンが残っていた。2026-10-07 判断で投稿・ストーリーと同じ決まり（`PlaceCoordsRule`）:
        // 変えていない撮影地（開いたときから空の写真を含む）と、写真の近くの撮影スポットを指す撮影地
        // （「, 香川」を足した）は座標を残す。それ以外に書き換えたら消す（`EditPlaceRules.clearsCoords`）
        patch.clearCoords = EditPlaceRules.clearsCoords(openedLocation: photo.location,
                                                        currentLocation: f.location,
                                                        pickedCoords: f.pickedCoords != nil,
                                                        photoCoords: photo.coords, spots: spots)
        // タグは欄と同じ割り方で比べる（区切りの文字を含む古いタグは欄に出した
        // 時点で割れて見えるので、元の配列と直に比べると毎回「変わった」になる）
        let tags = TagInput.parse(f.tagsText)
        if tags != TagInput.parse((photo.tags ?? []).joined(separator: ", ")) {
            patch.tags = tags
        }
        let trimmedCategory = f.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCategory != (photo.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
            patch.category = trimmedCategory
        }
        // 公開と公開範囲も**変えたときだけ**（`EditVisibilityRules`）。知らない値の写真では
        // 範囲を送らない——キーを外せばサーバーは既にある印を残す
        let visibility = EditVisibilityRules.patch(openedPublished: photo.published != false,
                                                   openedAudience: openedAudience,
                                                   published: f.published, audience: f.audience)
        patch.published = visibility.published
        patch.audience = visibility.audience
        // **触っていなければ送らない**（時刻付きの撮影日を日付だけに落とさない）。
        // 入っていた日付を消したら空文字を送る（サーバーが撮影日を消す）
        patch.date = EditDay.toSend(opened: EditDay.field(date: photo.date), field: f.date)
        return patch
    }

    /// 送っていない変更があるか（＝保存すれば何か送る）。
    ///
    /// **写真そのものの差し替えは数えない**——差し替えは選んだその場で送り終わっている
    /// （閉じても消えない）。2026-10-03 判断: 末尾に空白を打っただけの題など、
    /// 送る差分が出る打ち直しは「変更あり」として確かめる（送る差分と判断を割らないため）
    static func hasChanges(photo: Photo, openedAudience: Audience?, fields: Fields) -> Bool {
        !patch(photo: photo, openedAudience: openedAudience, fields: fields).isEmpty
    }

    /// 閉じるときの確認に「保存して閉じる」を出すか。**保存（`EditPhotoView.save`）と同じ関所**
    /// ——説明が上限を超えている間は保存しても断って開いたままになるので、出さない
    /// （「変更を捨てる」「キャンセル」だけ。戻って説明を縮めれば保存できる）
    static func canSaveAndClose(photo: Photo, fields: Fields) -> Bool {
        LocalizedEdit.descriptionOverLimit(original: photo.description, field: fields.caption) == nil
    }

    /// 閉じようとしたときの扱い（`UnsavedLeave`）。保存・差し替えの最中は閉じさせない
    static func leave(photo: Photo, openedAudience: Audience?, fields: Fields,
                      isSaving: Bool) -> UnsavedLeave {
        UnsavedLeave.decide(hasChanges: hasChanges(photo: photo, openedAudience: openedAudience, fields: fields),
                            isSaving: isSaving)
    }
}
