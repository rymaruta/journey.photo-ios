#!/usr/bin/env python3
"""Web 版との突き合わせ（check-api-parity.py）がサーバーの口を読む形の回帰テスト。macOS/Xcode不要。

2026-11-12 確かめ役: user API の HTTP API に経路を足す別のスタック（serverless.<名前>.yml）を読むとき、
(1) user API の HttpApiId を取り込む設定だけを読む、(2) 正規表現はファイルごと・関数の並びの中だけにかける。
"""
import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("parity", pathlib.Path(__file__).with_name("check-api-parity.py"))
parity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parity)

USER = """service: photo-gallery-user-api
functions:
  getMyProfile:
    handler: src/a.b
    events:
      - httpApi:
          path: /user/profile
          method: GET
          authorizer:
            name: cognitoAuthorizer
"""

# user API の HTTP API に足す別スタック。最後の口はログイン不要で、その下の resources に authorizer の字がある
QR = """service: photo-gallery-profile-qr
provider:
  httpApi:
    id:
      Fn::ImportValue: sls-photo-gallery-user-api-${sls:stage}-HttpApiId
functions:
  getMyQr:
    handler: src/q.a
    events:
      - httpApi:
          path: /user/qr
          method: GET
          authorizer:
            type: jwt
            id:
              Ref: QrCognitoAuthorizer
  resolveQr:
    handler: src/q.c
    events:
      - httpApi:
          path: /qr/{token}
          method: GET
resources:
  Resources:
    QrCognitoAuthorizer:
      Type: AWS::ApiGatewayV2::Authorizer
      # authorizer の字（小文字）が口の続きに見えてはいけない
"""

# 別の API（user API ではない）に経路を足す設定。口として読まない
OTHER = """service: photo-gallery-other
provider:
  httpApi:
    id: abc123
functions:
  ping:
    handler: src/o.p
    events:
      - httpApi:
          path: /ping
          method: GET
"""


class ServerEndpointsTest(unittest.TestCase):
    def endpoints(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            (root / "api-user").mkdir()
            (root / "api-user" / "serverless.yml").write_text(USER, encoding="utf-8")
            (root / "api-user" / "serverless.profile-qr.yml").write_text(QR, encoding="utf-8")
            (root / "api-user" / "serverless.other.yml").write_text(OTHER, encoding="utf-8")
            return parity.server_endpoints(root)

    def test_reads_user_api_and_stacks_that_import_its_http_api(self):
        eps = self.endpoints()
        self.assertTrue(eps[("GET", "/user/profile")])
        self.assertTrue(eps[("GET", "/user/qr")])

    def test_public_route_at_the_end_is_not_read_as_authed(self):
        self.assertFalse(self.endpoints()[("GET", "/qr/{}")])

    def test_ignores_stacks_for_other_apis(self):
        self.assertNotIn(("GET", "/ping"), self.endpoints())


if __name__ == "__main__":
    unittest.main()
