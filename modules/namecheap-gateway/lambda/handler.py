"""Namecheap gateway: the few Namecheap API calls DevOpsFoundry needs, made from a
Lambda whose traffic leaves through a NAT with a fixed Elastic IP, so one entry on
Namecheap's API allowlist covers every caller.

The API key is read from an SSM SecureString at run time. It is sent to Namecheap
in a POST body over TLS and never logged, returned or put in an error message.

Actions (the event's "action"):
  check            a read-only call (users.getBalances); proves the key and allowlist
  get_nameservers  {"domain"}: whether Namecheap's own DNS is used, and the nameservers
  set_nameservers  {"domain", "nameservers"}: custom nameservers (domains.dns.setCustom)
  reset_default    {"domain"}: back to Namecheap's default DNS (domains.dns.setDefault)

An event from Terraform's aws_lambda_invocation with lifecycle_scope = "CRUD"
carries a "tf" object: create and update set the nameservers, delete resets the
domain to Namecheap's default DNS.

Any failure raises, so the invocation reports a FunctionError and Terraform or
bin/namecheap stops.
"""

import json
import os
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

import boto3

PRODUCTION_URL = "https://api.namecheap.com/xml.response"
SANDBOX_URL = "https://api.sandbox.namecheap.com/xml.response"

DOMAIN_RE = re.compile(r"^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")
HOST_RE = DOMAIN_RE

_api_key = None


class GatewayError(Exception):
    """A refused request or a Namecheap error. The message never holds the key."""


def _setting(name, default=None):
    value = os.environ.get(name, default)
    if value is None or value == "":
        raise GatewayError(f"{name} is not set on the function")
    return value


def _key():
    global _api_key
    if _api_key is None:
        ssm = boto3.client("ssm")
        resp = ssm.get_parameter(Name=_setting("API_KEY_PARAMETER"), WithDecryption=True)
        _api_key = resp["Parameter"]["Value"]
    return _api_key


def _domain(event):
    domain = str(event.get("domain", "")).strip().lower().rstrip(".")
    if not DOMAIN_RE.match(domain):
        raise GatewayError(f"not a domain name: {domain!r}")
    allowed = [d.strip().lower() for d in os.environ.get("ALLOWED_DOMAINS", "").split(",") if d.strip()]
    if allowed and domain not in allowed:
        raise GatewayError(f"{domain} is not in this gateway's allowed_domains")
    # Namecheap wants the registered name split in two: SLD "example", TLD "co.uk".
    sld, tld = domain.split(".", 1)
    return domain, sld, tld


def _nameservers(event):
    raw = event.get("nameservers")
    if not isinstance(raw, list):
        raise GatewayError("nameservers must be a list")
    names = [str(n).strip().lower().rstrip(".") for n in raw]
    if not 2 <= len(names) <= 12:
        raise GatewayError("Namecheap takes 2 to 12 nameservers")
    for n in names:
        if not HOST_RE.match(n):
            raise GatewayError(f"not a nameserver host name: {n!r}")
    return names


def _call(command, **params):
    body = {
        "ApiUser": _setting("API_USER"),
        "ApiKey": _key(),
        "UserName": _setting("USER_NAME"),
        "ClientIp": _setting("CLIENT_IP"),
        "Command": command,
        **params,
    }
    url = SANDBOX_URL if os.environ.get("SANDBOX") == "true" else PRODUCTION_URL
    req = urllib.request.Request(
        url,
        data=urllib.parse.urlencode(body).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:  # nosec B310: fixed https URL
            raw = resp.read()
    except OSError as e:  # URLError, timeouts. The URL holds no credentials.
        raise GatewayError(f"{command}: could not reach Namecheap: {getattr(e, 'reason', e)}") from None
    return _parse(command, raw)


def _parse(command, raw):
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        raise GatewayError(f"{command}: Namecheap sent a response that is not XML") from None
    if root.get("Status") != "OK":
        errors = [f"{e.get('Number', '?')}: {(e.text or '').strip()}" for e in root.findall(".//{*}Error")]
        raise GatewayError(f"{command} failed: " + ("; ".join(errors) or "no error given"))
    result = root.find("{*}CommandResponse")
    if result is None:
        raise GatewayError(f"{command}: Namecheap's response has no CommandResponse")
    return result


def _updated(result, tag, command):
    node = result.find(f"{{*}}{tag}")
    if node is None or node.get("Updated", "").lower() != "true":
        raise GatewayError(f"{command}: Namecheap did not confirm the change")


def check(_event):
    _call("namecheap.users.getBalances")
    return {"ok": True, "client_ip": _setting("CLIENT_IP")}


def get_nameservers(event):
    domain, sld, tld = _domain(event)
    result = _call("namecheap.domains.dns.getList", SLD=sld, TLD=tld)
    node = result.find("{*}DomainDNSGetListResult")
    if node is None:
        raise GatewayError("namecheap.domains.dns.getList: no result in Namecheap's response")
    return {
        "domain": domain,
        "using_namecheap_dns": node.get("IsUsingOurDNS", "").lower() == "true",
        "nameservers": sorted((n.text or "").strip().lower() for n in node.findall("{*}Nameserver")),
    }


def set_nameservers(event):
    domain, sld, tld = _domain(event)
    names = _nameservers(event)
    command = "namecheap.domains.dns.setCustom"
    _updated(_call(command, SLD=sld, TLD=tld, Nameservers=",".join(names)), "DomainDNSSetCustomResult", command)
    return {"domain": domain, "nameservers": sorted(names)}


def reset_default(event):
    domain, sld, tld = _domain(event)
    command = "namecheap.domains.dns.setDefault"
    _updated(_call(command, SLD=sld, TLD=tld), "DomainDNSSetDefaultResult", command)
    return {"domain": domain, "using_namecheap_dns": True}


ACTIONS = {
    "check": check,
    "get_nameservers": get_nameservers,
    "set_nameservers": set_nameservers,
    "reset_default": reset_default,
}


def handler(event, _context):
    if not isinstance(event, dict):
        raise GatewayError("the event must be a JSON object")
    tf = event.get("tf")
    if isinstance(tf, dict):
        # aws_lambda_invocation, lifecycle_scope = "CRUD".
        action = "reset_default" if tf.get("action") == "delete" else "set_nameservers"
    else:
        action = event.get("action")
    fn = ACTIONS.get(action)
    if fn is None:
        raise GatewayError(f"unknown action {action!r}; one of {', '.join(ACTIONS)}")
    print(json.dumps({"action": action, "domain": event.get("domain")}))
    result = fn(event)
    print(json.dumps({"action": action, "domain": event.get("domain"), "ok": True}))
    return result
