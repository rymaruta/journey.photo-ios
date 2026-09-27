import Foundation

/// プロフィールの編集画面が持つ欄の姿（`ProfileEditView`）。
///
/// 🔴 **保存では「読み込んだ時点から変えた欄」だけを送る**（`patch(from:to:)`）。
///
/// 以前は開いた時点の値を**全部の欄**送っていた。サーバーは「キーがある＝指定した」
/// で読む部分更新（`api-user/src/userProfile.ts` の `apply`）なので、全部送れば
/// 全置換と同じになる——iOS で編集画面を開いたまま Web で表示名や BGM を直し、
/// そのあと iOS で自己紹介だけ直して保存すると、**Web の変更が開いた時点の値に
/// 巻き戻った**。サーバーの rev は「同じ項目を送ってきた側が勝つ」ので守れない。
/// Web の `/user/profile` も同じ理由で変えた項目だけを送っている
/// （`app/user/profile/page.tsx` の `changedFields`・`page.partialSave.test.tsx`）。
///
/// **`@MainActor` の型に置かない**（`InviteLink` と同じ理由。テストから呼べなくなる）。
struct ProfileDraft: Equatable {
    var username = ""
    var displayName = ""
    var bio = ""
    var website = ""
    var instagram = ""
    var statusText = ""
    var homeLocation = ""
    var themeColor = ""
    /// 持っている曲を**丸ごと**（Web は5曲まで持てる。`ProfilePatch.songs` の注記）
    var songs: [Photo.Song] = []

    init(username: String = "", displayName: String = "", bio: String = "",
         website: String = "", instagram: String = "", statusText: String = "",
         homeLocation: String = "", themeColor: String = "", songs: [Photo.Song] = []) {
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.website = website
        self.instagram = instagram
        self.statusText = statusText
        self.homeLocation = homeLocation
        self.themeColor = themeColor
        self.songs = songs
    }

    /// 読み込んだプロフィールを欄に入れる姿（無い項目は空文字・空の一覧）
    init(profile: UserProfile) {
        self.init(username: profile.username ?? "",
                  displayName: profile.displayName ?? "",
                  bio: profile.bio ?? "",
                  website: profile.website ?? "",
                  instagram: profile.instagram ?? "",
                  statusText: profile.statusText ?? "",
                  homeLocation: profile.homeLocation ?? "",
                  themeColor: profile.themeColor ?? "",
                  songs: profile.songs ?? [])
    }

    /// 保存で送るもの。**何も変えていなければ `nil`**（送らない）。
    ///
    /// - 文字の欄は**両側を trim して比べる**。サーバーは保存時に trim するので、
    ///   末尾に空白を打っただけの欄は「変えた」ことにしない（Web の `hasUnsavedWork` と同じ）。
    ///   送るときは打ったまま送る（trim はサーバーがする）
    /// - 🔴 **ユーザー名は変えたときだけ送る。** サーバーは `username` のキーが
    ///   あるときだけ形式・予約語を検証する（`userProfile.ts` の `hasUsernameKey`）。
    ///   いまの規則より前に取った名前の人は、毎回送ると**自己紹介を直すだけの
    ///   保存まで 400 で全部断られる**。比べるのはサーバーと同じ正規化
    ///   （trim・小文字・先頭の @ を外す）で、送るのもその形（Web と同じ）
    /// - 曲は一覧ごと比べる。触っていなければ送らない——送ると、別の端末で
    ///   足した曲を開いた時点の一覧で消す
    /// - 空にした欄は空文字で送る（＝消す。`nil` は「触らない」）
    static func patch(from original: ProfileDraft, to edited: ProfileDraft) -> ProfilePatch? {
        var patch = ProfilePatch()
        var changed = false

        let username = normalizedUsername(edited.username)
        if username != normalizedUsername(original.username) {
            patch.username = username
            changed = true
        }
        func text(_ key: KeyPath<ProfileDraft, String>) -> String? {
            let value = edited[keyPath: key]
            guard trimmed(value) != trimmed(original[keyPath: key]) else { return nil }
            changed = true
            return value
        }
        patch.displayName = text(\.displayName)
        patch.bio = text(\.bio)
        patch.website = text(\.website)
        patch.instagram = text(\.instagram)
        patch.statusText = text(\.statusText)
        patch.homeLocation = text(\.homeLocation)
        patch.themeColor = text(\.themeColor)
        if edited.songs != original.songs {
            patch.songs = edited.songs
            changed = true
        }
        return changed ? patch : nil
    }

    /// サーバーの `normalizeUsername` と同じ形（trim・小文字・先頭の @ を外す）
    static func normalizedUsername(_ raw: String) -> String {
        let lowered = trimmed(raw).lowercased()
        return lowered.hasPrefix("@") ? String(lowered.dropFirst()) : lowered
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
