#!/usr/bin/env python3
"""Check an EU VAT number against the European Commission's VIES service.

    vat-check NL123456789B01      # also accepts spaces, dots and dashes
    vat-check --self-test         # offline asserts on parsing and verdicts

Exit 0 valid, 1 invalid, 2 malformed input or VIES could not answer. Replaces the vies-vat MCP
server: one GET to ec.europa.eu, no key.
"""

import json
import re
import sys
import urllib.error
import urllib.request

URL = "https://ec.europa.eu/taxation_customs/vies/rest-api/ms/{cc}/vat/{num}"
# EU member states as VIES names them (Greece is EL, Northern Ireland is XI).
COUNTRIES = set(
    "AT BE BG CY CZ DE DK EE EL ES FI FR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK XI".split()
)


def parse(raw):
    """'nl 1234.567-89b01' -> ('NL', '123456789B01'), or None when it cannot be a VAT number."""
    s = re.sub(r"[\s.\-]", "", raw).upper()
    m = re.fullmatch(r"([A-Z]{2})([0-9A-Z+*]{2,12})", s)
    if not m or m.group(1) not in COUNTRIES:
        return None
    return m.group(1), m.group(2)


def verdict(resp):
    """VIES JSON -> (exit code, text). Only isValid true counts as valid."""
    if resp.get("isValid") is True:
        lines = ["valid"] + [
            resp[k] for k in ("name", "address") if resp.get(k) not in (None, "", "---")
        ]
        return 0, "\n".join(lines)
    err = resp.get("userError", "")
    if err in ("INVALID", "INVALID_INPUT"):
        return 1, "invalid" + (
            " (VIES rejected the format)" if err == "INVALID_INPUT" else ""
        )
    # MS_UNAVAILABLE, TIMEOUT, MS_MAX_CONCURRENT_REQ, …: VIES did not decide, so neither do we.
    return 2, f"unknown: VIES answered {err or 'nothing usable'}, try again later"


def self_test():
    assert parse("NL123456789B01") == ("NL", "123456789B01")
    assert parse(" nl 1234.567-89b01 ") == ("NL", "123456789B01")
    assert parse("EL123456789") == ("EL", "123456789")
    assert parse("GR123456789") is None  # VIES uses EL for Greece
    assert parse("US123456789") is None
    assert parse("NL12;rm") is None
    assert parse("") is None
    assert verdict({"isValid": True, "name": "ACME BV", "address": "---"}) == (
        0,
        "valid\nACME BV",
    )
    assert verdict({"isValid": False, "userError": "INVALID"}) == (1, "invalid")
    assert verdict({"isValid": False, "userError": "INVALID_INPUT"})[0] == 1
    assert verdict({"isValid": False, "userError": "MS_UNAVAILABLE"})[0] == 2
    assert verdict({"isValid": "true"})[0] == 2  # only a real boolean true is valid
    assert verdict({})[0] == 2
    print("self-test ok")


def main(argv):
    if argv == ["--self-test"]:
        self_test()
        return 0
    if len(argv) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    parsed = parse(argv[0])
    if parsed is None:
        print(
            f"{argv[0]!r} is not a VAT number: expected an EU country code and digits, like NL123456789B01",
            file=sys.stderr,
        )
        return 2
    cc, num = parsed
    try:
        with urllib.request.urlopen(URL.format(cc=cc, num=num), timeout=20) as r:
            resp = json.load(r)
    except (urllib.error.URLError, TimeoutError, ValueError) as e:
        print(f"unknown: could not reach VIES ({e})", file=sys.stderr)
        return 2
    code, text = verdict(resp)
    print(text)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
