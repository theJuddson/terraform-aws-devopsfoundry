"""modules/namecheap-gateway/lambda/handler.py, with Namecheap and SSM stubbed.

Run: python3 -m unittest discover -s tests/namecheap-gateway
No network and no AWS: urlopen and boto3 are replaced before each call.
"""

import io
import os
import sys
import types
import unittest
import urllib.parse
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "modules", "namecheap-gateway", "lambda"))

# boto3 isn't needed on the machine running the tests: the handler only makes an SSM client.
fake_boto3 = types.ModuleType("boto3")
fake_boto3.client = lambda *_a, **_k: None
sys.modules.setdefault("boto3", fake_boto3)

import handler  # noqa: E402

KEY = "sekrit-api-key-0123456789"
NS = "http://api.namecheap.com/xml.response"


def ok(body):
    return f'<?xml version="1.0"?><ApiResponse Status="OK" xmlns="{NS}"><Errors/><CommandResponse>{body}</CommandResponse></ApiResponse>'.encode()


def error(number, text):
    return f'<?xml version="1.0"?><ApiResponse Status="ERROR" xmlns="{NS}"><Errors><Error Number="{number}">{text}</Error></Errors></ApiResponse>'.encode()


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


class Base(unittest.TestCase):
    def setUp(self):
        self.env = mock.patch.dict(os.environ, {
            "API_KEY_PARAMETER": "/devopsfoundry/namecheap/api-key",
            "API_USER": "exampleuser",
            "USER_NAME": "exampleuser",
            "CLIENT_IP": "203.0.113.10",
            "SANDBOX": "false",
            "ALLOWED_DOMAINS": "",
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        handler._api_key = None
        ssm = mock.Mock()
        ssm.get_parameter.return_value = {"Parameter": {"Value": KEY}}
        self.ssm = ssm
        p = mock.patch.object(handler.boto3, "client", return_value=ssm)
        p.start()
        self.addCleanup(p.stop)
        self.requests = []
        self.reply = ok("")

        def urlopen(req, timeout=None):
            self.requests.append(req)
            return FakeResponse(self.reply)

        p = mock.patch.object(handler.urllib.request, "urlopen", side_effect=urlopen)
        p.start()
        self.addCleanup(p.stop)

    def sent(self, i=-1):
        req = self.requests[i]
        return req, dict(urllib.parse.parse_qsl(req.data.decode()))


class SetNameservers(Base):
    def test_sends_setcustom_with_split_domain_and_the_key_in_the_body_only(self):
        self.reply = ok('<DomainDNSSetCustomResult Domain="example.co.uk" Updated="true"/>')
        out = handler.handler({"action": "set_nameservers", "domain": "Example.co.uk.",
                               "nameservers": ["ns-2.awsdns-02.co.uk", "NS-1.awsdns-01.org."]}, None)
        req, body = self.sent()
        self.assertEqual(req.get_method(), "POST")
        self.assertEqual(req.full_url, handler.PRODUCTION_URL)
        self.assertNotIn(KEY, req.full_url)
        self.assertEqual(body["Command"], "namecheap.domains.dns.setCustom")
        self.assertEqual((body["SLD"], body["TLD"]), ("example", "co.uk"))
        self.assertEqual(body["Nameservers"], "ns-2.awsdns-02.co.uk,ns-1.awsdns-01.org")
        self.assertEqual(body["ApiKey"], KEY)
        self.assertEqual(body["ClientIp"], "203.0.113.10")
        self.assertEqual(out, {"domain": "example.co.uk", "nameservers": ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk"]})
        self.assertNotIn(KEY, repr(out))
        self.ssm.get_parameter.assert_called_once_with(Name="/devopsfoundry/namecheap/api-key", WithDecryption=True)

    def test_an_unconfirmed_change_fails(self):
        self.reply = ok('<DomainDNSSetCustomResult Domain="example.com" Updated="false"/>')
        with self.assertRaisesRegex(handler.GatewayError, "did not confirm"):
            handler.handler({"action": "set_nameservers", "domain": "example.com",
                             "nameservers": ["ns1.example.net", "ns2.example.net"]}, None)

    def test_refuses_bad_nameservers_without_calling_namecheap(self):
        for bad in (["ns1.example.net"], "ns1.example.net,ns2.example.net", ["ns1.example.net", "bad host"]):
            with self.assertRaises(handler.GatewayError):
                handler.handler({"action": "set_nameservers", "domain": "example.com", "nameservers": bad}, None)
        self.assertEqual(self.requests, [])


class Terraform(Base):
    def test_create_and_update_set_the_nameservers(self):
        self.reply = ok('<DomainDNSSetCustomResult Domain="example.com" Updated="true"/>')
        for action in ("create", "update"):
            handler.handler({"action": "set_nameservers", "domain": "example.com",
                             "nameservers": ["ns1.example.net", "ns2.example.net"], "tf": {"action": action}}, None)
            self.assertEqual(self.sent()[1]["Command"], "namecheap.domains.dns.setCustom")

    def test_delete_resets_to_namecheap_default_dns(self):
        self.reply = ok('<DomainDNSSetDefaultResult Domain="example.com" Updated="true"/>')
        out = handler.handler({"action": "set_nameservers", "domain": "example.com",
                               "nameservers": ["ns1.example.net", "ns2.example.net"], "tf": {"action": "delete"}}, None)
        body = self.sent()[1]
        self.assertEqual(body["Command"], "namecheap.domains.dns.setDefault")
        self.assertNotIn("Nameservers", body)
        self.assertEqual(out, {"domain": "example.com", "using_namecheap_dns": True})


class Reads(Base):
    def test_get_nameservers(self):
        self.reply = ok('<DomainDNSGetListResult Domain="example.com" IsUsingOurDNS="false">'
                        '<Nameserver>NS-2.AWSDNS-02.CO.UK</Nameserver><Nameserver>ns-1.awsdns-01.org</Nameserver>'
                        '</DomainDNSGetListResult>')
        out = handler.handler({"action": "get_nameservers", "domain": "example.com"}, None)
        self.assertEqual(self.sent()[1]["Command"], "namecheap.domains.dns.getList")
        self.assertEqual(out, {"domain": "example.com", "using_namecheap_dns": False,
                               "nameservers": ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk"]})

    def test_check_reports_the_client_ip(self):
        self.reply = ok('<UserGetBalancesResult Currency="USD" AvailableBalance="1.00"/>')
        out = handler.handler({"action": "check"}, None)
        self.assertEqual(self.sent()[1]["Command"], "namecheap.users.getBalances")
        self.assertEqual(out, {"ok": True, "client_ip": "203.0.113.10"})

    def test_sandbox_uses_the_sandbox_api(self):
        os.environ["SANDBOX"] = "true"
        handler.handler({"action": "check"}, None)
        self.assertEqual(self.sent()[0].full_url, handler.SANDBOX_URL)


class Errors(Base):
    def test_namecheap_errors_are_raised_with_their_text_and_never_the_key(self):
        self.reply = error("1011150", "Parameter RequestIP is invalid")
        with self.assertRaises(handler.GatewayError) as cm:
            handler.handler({"action": "check"}, None)
        self.assertIn("1011150: Parameter RequestIP is invalid", str(cm.exception))
        self.assertNotIn(KEY, str(cm.exception))

    def test_unreachable_namecheap_fails_without_the_key(self):
        handler.urllib.request.urlopen.side_effect = handler.urllib.error.URLError("timed out")
        with self.assertRaises(handler.GatewayError) as cm:
            handler.handler({"action": "check"}, None)
        self.assertIn("could not reach Namecheap", str(cm.exception))
        self.assertNotIn(KEY, str(cm.exception))

    def test_unknown_actions_and_bad_domains_are_refused_before_any_call(self):
        for event in ({"action": "domains.delete"}, {}, {"action": "get_nameservers", "domain": "not a domain"},
                      {"action": "get_nameservers", "domain": "localhost"}):
            with self.assertRaises(handler.GatewayError):
                handler.handler(event, None)
        with self.assertRaises(handler.GatewayError):
            handler.handler(["check"], None)
        self.assertEqual(self.requests, [])

    def test_allowed_domains_limit_what_can_be_touched(self):
        os.environ["ALLOWED_DOMAINS"] = "example.com, example.org"
        with self.assertRaisesRegex(handler.GatewayError, "allowed_domains"):
            handler.handler({"action": "reset_default", "domain": "example.net"}, None)
        self.assertEqual(self.requests, [])
        self.reply = ok('<DomainDNSSetDefaultResult Domain="example.org" Updated="true"/>')
        handler.handler({"action": "reset_default", "domain": "example.org"}, None)
        self.assertEqual(len(self.requests), 1)

    def test_the_log_lines_never_hold_the_key(self):
        self.reply = ok('<DomainDNSSetDefaultResult Domain="example.com" Updated="true"/>')
        with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            handler.handler({"action": "reset_default", "domain": "example.com"}, None)
        self.assertNotIn(KEY, out.getvalue())
        self.assertIn('"action": "reset_default"', out.getvalue())


if __name__ == "__main__":
    unittest.main()
