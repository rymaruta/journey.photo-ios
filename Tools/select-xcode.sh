#!/usr/bin/env bash
#
# Mac の CI で使う Xcode を選ぶ（2026-10-31・#429。UI テストを分けて流す台で使う）。
#
#     bash Tools/select-xcode.sh            # 入っている中でいちばん新しい Xcode
#     bash Tools/select-xcode.sh 26.3.0     # この版（組んだ台と同じ版）。無ければ、いちばん新しいものにして警告
#
# 選び方は `ios-testflight.yml` の「Xcode を選ぶ（iOS 26 SDK が要る）」と同じ——版は `Xcode_26.3.0.app` の
# 名前から読む（`xcodebuild -version` を20回叩くと1つが落ちて段ごと死んだ・run 69）。
# 組んだ台と流す台で Xcode が違うと、組んだ品が動かないことがある（ランナーの像の入れ替わりの間に起こりうる）。
# だから組んだ台の版を受け取り、同じ版を選ぶ。
# 選んだ版を `DEVELOPER_DIR`（GITHUB_ENV）と `version`（GITHUB_OUTPUT）に書き、標準出力にも出す
set -u

want="${1:-}"
newest="$(ls -d /Applications/Xcode_*.app 2>/dev/null \
          | sed 's#.*/Xcode_##; s#\.app$##' \
          | grep -E '^[0-9]+(\.[0-9]+)*$' \
          | sort -V | tail -1)"
ver="$newest"
if [ -n "$want" ]; then
    if [ -d "/Applications/Xcode_$want.app/Contents/Developer" ]; then
        ver="$want"
    else
        echo "::warning::組んだ台の Xcode $want がこの台にありません。いちばん新しい ${newest:-（不明）} で流します（組んだ品が動かなければ、これが理由）"
    fi
fi
if [ -n "$ver" ] && [ -d "/Applications/Xcode_$ver.app/Contents/Developer" ]; then
    [ -n "${GITHUB_ENV:-}" ] && echo "DEVELOPER_DIR=/Applications/Xcode_$ver.app/Contents/Developer" >> "$GITHUB_ENV"
    [ -n "${GITHUB_OUTPUT:-}" ] && echo "version=$ver" >> "$GITHUB_OUTPUT"
    echo "$ver"
else
    echo "::warning::版の読める Xcode が見つかりません。既定のまま進みます"
fi
exit 0
