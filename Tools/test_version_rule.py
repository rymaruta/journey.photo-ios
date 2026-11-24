#!/usr/bin/env python3
"""表に出る版の決め方（`next-marketing-version.sh`・`bump-build.sh`）の回帰テスト。macOS/Xcode 不要。

2026-11-23 owner 判断: TestFlight のたびに一番下 +1（1.2.0 → 1.2.1 …）、ビルド番号はいつも 1、
App Store に出したら人が真ん中を上げて一番下を 0 に戻す（`bash Tools/bump-build.sh 1.3.0`）。
1.1 のまま 1.1.119 まで来ていたので、1.2.0 に上げた直後の回が 1.2.0、その次が 1.2.1 になることを、
古い系の印（testflight/1.1.119）が残ったままの写しの git で確かめる。"""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class VersionRuleTests(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.repo = pathlib.Path(self.dir.name)
        tools = self.repo / "Tools"
        tools.mkdir()
        for name in ("next-marketing-version.sh", "bump-build.sh", "set-build-number.sh"):
            shutil.copy(ROOT / "Tools" / name, tools / name)
        # bump-build.sh が最後に呼ぶ設定の検査は、ここでは空にする
        (tools / "check-config.py").write_text("", encoding="utf-8")
        self.write_project("1.1.8", "4")
        self.git("init", "-q")
        self.git("-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q",
                 "--allow-empty", "-m", "init")
        # 古い系の印（1.1 のまま出していた分）
        for patch in (117, 118, 119):
            self.git("tag", f"testflight/1.1.{patch}")

    def tearDown(self):
        self.dir.cleanup()

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True)

    def write_project(self, version, build):
        (self.repo / "project.yml").write_text(
            f'    settings:\n      base:\n        MARKETING_VERSION: "{version}"\n'
            f'        CURRENT_PROJECT_VERSION: "{build}"\n', encoding="utf-8")

    def project(self):
        text = (self.repo / "project.yml").read_text(encoding="utf-8")
        return (re.search(r'MARKETING_VERSION: "([0-9.]+)"', text).group(1),
                re.search(r'CURRENT_PROJECT_VERSION: "([0-9]+)"', text).group(1))

    def run_script(self, name, *args):
        run = subprocess.run(["bash", str(self.repo / "Tools" / name), *args],
                             cwd=self.repo, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        return run.stdout.strip()

    def ship(self):
        """ワークフローの1回分: 版を決めて、上がったら印を付ける"""
        version = self.run_script("next-marketing-version.sh")
        self.git("tag", f"testflight/{version}")
        return version

    def test_without_bump_old_series_keeps_counting(self):
        # 上げないまま流すと、今までどおり 1.1.120（真ん中を上げないとこうなる、という比べ）
        self.assertEqual(self.run_script("next-marketing-version.sh"), "1.1.120")

    def test_bump_to_120_starts_at_120_then_counts_up(self):
        self.run_script("bump-build.sh", "1.2.0")
        self.assertEqual(self.project(), ("1.2.0", "1"))
        # 1.2.0 の印がまだ無い＝1.2.0 を使う。古い 1.1.119 の印があっても引きずられない
        self.assertEqual(self.ship(), "1.2.0")
        self.assertEqual(self.ship(), "1.2.1")
        self.assertEqual(self.ship(), "1.2.2")
        self.assertEqual(self.project()[0], "1.2.2")

    def test_build_number_stays_one_when_shipping(self):
        # 版を上げても、ワークフローが版を進めても、ビルド番号は版ごとに 1 から（ここではいつも 1）
        self.run_script("bump-build.sh", "1.2.0")
        self.ship()
        self.ship()
        self.assertEqual(self.project()[1], "1")

    def test_app_store_bump_to_middle_resets_patch(self):
        # 1.2.x を App Store に出した → 人が 1.3.0 にする → 次の回は 1.3.0、その次は 1.3.1
        self.run_script("bump-build.sh", "1.2.0")
        for _ in range(3):
            self.ship()
        self.run_script("bump-build.sh", "1.3.0")
        self.assertEqual(self.project(), ("1.3.0", "1"))
        self.assertEqual(self.ship(), "1.3.0")
        self.assertEqual(self.ship(), "1.3.1")

    def test_failed_upload_reuses_same_version(self):
        # 上げるのに失敗した回は印が無い＝同じ版がもう一度使われる（版は飛ばない）
        self.run_script("bump-build.sh", "1.2.0")
        self.assertEqual(self.run_script("next-marketing-version.sh"), "1.2.0")
        self.assertEqual(self.run_script("next-marketing-version.sh"), "1.2.0")

    def test_latest_tag_sort_used_by_release_skill(self):
        # release の手順「git tag -l 'testflight/*' --sort=-v:refname | head -1」が最新の版を返す
        self.run_script("bump-build.sh", "1.2.0")
        for _ in range(11):
            self.ship()
        out = subprocess.run(["git", "tag", "-l", "testflight/*", "--sort=-v:refname"],
                             cwd=self.repo, capture_output=True, text=True, check=True).stdout.split()
        self.assertEqual(out[0], "testflight/1.2.10")


if __name__ == "__main__":
    unittest.main()
