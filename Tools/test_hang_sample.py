#!/usr/bin/env python3
"""`hang-sample.sh`（UI テストで前のアプリを閉じられないときの見張り）の回帰テスト。macOS/Xcode 不要。

2026-11-21（run 1677・1683 の調べ）: 「Failed to terminate」で2回落ちたのに見張りが1行も出さず、
見張りが動いていなかったのか、アプリが先に消えていたのかを見分けられなかった。
見張りが「始めた」「閉じると言われた」「N 秒で残っている／消えていた」「積み」「XCTest が閉じられなかった pid」の行を
必ず出すことを、偽の `sample` と本物の待つだけのプロセスで確かめる。行の形は run 1683 のログの行そのもの。"""
import os
import pathlib
import subprocess
import tempfile
import time
import unittest

SCRIPT = pathlib.Path(__file__).with_name("hang-sample.sh")


class HangSampleTests(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        d = pathlib.Path(self.dir.name)
        self.log = d / "xcodebuild-full.log"
        self.log.write_text("")
        # 偽の sample: 引数の -file の先に、sample の形の主スレッドの積みを書く
        self.tool = d / "fake-sample"
        self.tool.write_text(
            "#!/bin/bash\n"
            'out=""; while [ $# -gt 0 ]; do [ "$1" = -file ] && out="$2"; shift; done\n'
            'printf "Call graph:\\n    2370 Thread_4385905   DispatchQueue_1: com.apple.main-thread  (serial)\\n'
            '    + 2370 start  (in dyld_sim)\\n    +   2370 VisitedMapModel.persist()  (in JourneyPhoto.debug.dylib)\\n" > "$out"\n')
        self.tool.chmod(0o755)
        self.app = subprocess.Popen(["sleep", "61.5"])
        self.gone_mark = d / "last-gone"
        env = dict(os.environ, HANG_SAMPLE_GONE_MARK=str(self.gone_mark), HANG_SAMPLE_TOOL=str(self.tool), HANG_SAMPLE_CHECKS="1 2", HANG_SAMPLE_AT="2",
                   HANG_SAMPLE_APP_PATTERN="sleep 61.5")
        self.watcher = subprocess.Popen(["bash", str(SCRIPT), str(self.log)], env=env,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                        start_new_session=True)
        self.wait_for("見張りを始めた")

    def tearDown(self):
        self.app.kill()
        try:
            os.killpg(self.watcher.pid, 9)
        except ProcessLookupError:
            pass
        self.watcher.wait()
        self.dir.cleanup()

    def append(self, line):
        with self.log.open("a") as f:
            f.write(line + "\n")

    def wait_for(self, text, timeout=10):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if text in self.log.read_text():
                return
            time.sleep(0.1)
        self.fail(f"見張りが「{text}」を出さない:\n{self.log.read_text()}")

    def test_stuck_app_gets_states_and_main_thread_stack(self):
        self.append(f"2026-11-21T19:56:13.6699790Z     t =     0.94s         Terminate com.journeyphoto.JourneyPhoto.staging:{self.app.pid}")
        self.wait_for(f"measured [hang-sample] pid={self.app.pid} 閉じると言われた")
        self.wait_for(f"pid={self.app.pid} 1s の時点で残っている")
        self.wait_for(f"pid={self.app.pid} 閉じると言われて 2 秒たっても残っている。積みを取る")
        self.wait_for("measured [hang-sample] main     + 2370 start")
        self.wait_for("VisitedMapModel.persist()")
        self.wait_for("measured [hang-sample] thread     2370 Thread_4385905")

    def test_app_that_already_exited_is_reported_as_gone(self):
        pid = self.app.pid
        self.app.kill()
        self.app.wait()
        self.append(f"    t =     0.26s         Terminate com.journeyphoto.JourneyPhoto.staging:{pid}")
        self.wait_for(f"pid={pid} 1s の時点で消えていた")
        self.wait_for("閉じると言われてから消えるまで ")
        # 次の起動まで（札 #681）
        self.append("    t =     1.47s     Launch com.journeyphoto.JourneyPhoto.staging")
        self.wait_for("measured [hang-sample] 次の起動: 前のアプリが消えてから ")
        log = self.log.read_text()
        self.assertNotIn(f"pid={pid} 閉じると言われて", log, "消えたアプリの積みを取りに行った")

    def test_failed_to_terminate_line_says_whether_the_pid_is_still_there(self):
        self.append("/Users/runner/work/journey.photo-ios/journey.photo-ios/UITests/JourneyPhotoUITests/SmokeTests.swift:109: "
                    "error: -[JourneyPhotoUITests.SmokeTests testHeaderIconHitAreaReachesBeyondTheDrawnBox] : "
                    f"Failed to terminate com.journeyphoto.JourneyPhoto.staging:{self.app.pid}: Failed to terminate "
                    "com.journeyphoto.JourneyPhoto.staging:0")
        self.wait_for(f"XCTest が閉じられなかった pid={self.app.pid} はまだ残っている")
        self.assertNotIn("閉じると言われた", self.log.read_text(), "「Failed to terminate」を閉じる合図と取り違えた")

    def test_idle_timeout_takes_the_stack_of_the_running_app(self):
        # run 1691 の行そのもの（グループの詳しい画面を開いたあと、主スレッドが返らなかった）
        self.append("    t =   127.43s         App event loop idle notification not received, will attempt to continue.")
        self.wait_for(f"pid={self.app.pid} 主スレッドが返らない（idle にならない）。積みを取る")
        self.wait_for("VisitedMapModel.persist()")
        # 同じアプリは1回だけ
        self.append("    t =   187.43s         App event loop idle notification not received, will attempt to continue.")
        time.sleep(1)
        self.assertEqual(self.log.read_text().count("主スレッドが返らない"), 1)


if __name__ == "__main__":
    unittest.main()
