#!/usr/bin/env python3
"""API の突き合わせ（check-api-parity.py）の回帰テスト。macOS/Xcode 不要。

札 #569: Web 版は機能ごとの口を `api-user/serverless.<機能>.yml` に分けた。
分けたファイルにだけある口も「在る」と読むこと、分けていない形（本番 main）でも読めることを確かめる。
"""
import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "parity", pathlib.Path(__file__).with_name("check-api-parity.py"))
parity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parity)

MAIN = """service: photo-gallery-user-api
functions:
  getProfile:
    handler: src/profile.get
    events:
      - httpApi:
          path: /user/profile
          method: GET
          authorizer:
            name: cognitoAuthorizer
  listPhotos:
    handler: src/photos.list
    events:
      - httpApi:
          path: /photos
          method: GET
"""

TRIPS = """service: photo-gallery-trips
provider:
  httpApi:
    id:
      Fn::ImportValue: sls-photo-gallery-user-api-${sls:stage}-HttpApiId
functions:
  updateTrip:
    handler: src/tripPlans.updateTrip
    events:
      - httpApi:
          path: /user/trips/{planId}
          method: PUT
          authorizer:
            type: jwt
            id:
              Fn::ImportValue: sls-photo-gallery-user-api-${sls:stage}-CognitoAuthorizerId
"""

WANTS = """service: photo-gallery-spot-wants
functions:
  recordSpotWants:
    handler: src/spotWants.recordSpotWants
    events:
      - httpApi:
          path: /spots/wants
          method: POST
"""


def make_root(d, files):
    api = pathlib.Path(d) / "api-user"
    api.mkdir()
    for name, text in files.items():
        (api / name).write_text(text, encoding="utf-8")
    return pathlib.Path(d)


class ServerEndpointsTests(unittest.TestCase):
    def test_reads_routes_only_in_split_files(self):
        with tempfile.TemporaryDirectory() as d:
            root = make_root(d, {"serverless.yml": MAIN,
                                 "serverless.trips.yml": TRIPS,
                                 "serverless.spot-wants.yml": WANTS})
            got = parity.server_endpoints(root)
        # 分けたファイルにだけある口が「在る」と読める
        self.assertIn(("PUT", "/user/trips/{}"), got)
        self.assertIn(("POST", "/spots/wants"), got)
        # 認証の有無も分けたファイルから読む
        self.assertTrue(got[("PUT", "/user/trips/{}")])
        self.assertFalse(got[("POST", "/spots/wants")])
        # 元のファイルの口もそのまま
        self.assertTrue(got[("GET", "/user/profile")])
        self.assertFalse(got[("GET", "/photos")])
        self.assertEqual(len(got), 4)

    def test_reads_unsplit_layout(self):
        # 本番（main）のように、まだ分けていない形
        with tempfile.TemporaryDirectory() as d:
            root = make_root(d, {"serverless.yml": MAIN})
            got = parity.server_endpoints(root)
        self.assertEqual(got, {("GET", "/user/profile"): True, ("GET", "/photos"): False})


if __name__ == "__main__":
    unittest.main()
