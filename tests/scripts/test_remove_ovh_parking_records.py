import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from remove_ovh_parking_records import is_parking  # noqa: E402


def record(field_type, subdomain, target):
    return {"fieldType": field_type, "subDomain": subdomain, "target": target, "id": 1}


class IsParkingTest(unittest.TestCase):
    # Records found in a new OVHcloud zone (technogix.dev, 2026-10-05).
    PARKING = [
        record("A", "", "213.186.33.5"),
        record("A", "www", "213.186.33.5"),
        record("TXT", "", '"1|www.technogix.dev"'),
        record("TXT", "www", '"3|welcome"'),
    ]
    KEPT = [
        record("MX", "", "1 mx1.mail.ovh.net."),
        record("SPF", "", "v=spf1 include:mx.ovh.com -all"),
        record("CNAME", "ovhmo-selector-1._domainkey", "ovhmo-selector-1._domainkey.1.mh.dkim.mail.ovh.net."),
        record("SRV", "_imaps._tcp", "0 0 993 ssl0.ovh.net."),
        record("CNAME", "imap", "ssl0.ovh.net."),
        record("CNAME", "ftp", "technogix.dev."),
        record("NS", "", "dns111.ovh.net."),
        # Site records: GitHub Pages addresses, and a parking IP elsewhere.
        record("A", "", "185.199.108.153"),
        record("CNAME", "www", "technogix.github.io."),
        record("A", "blog", "213.186.33.5"),
        # A real TXT on the apex (e.g. a domain verification).
        record("TXT", "", '"google-site-verification=abc"'),
    ]

    def test_parking_records_selected(self):
        for r in self.PARKING:
            self.assertTrue(is_parking(r), r)

    def test_other_records_kept(self):
        for r in self.KEPT:
            self.assertFalse(is_parking(r), r)


if __name__ == "__main__":
    unittest.main()
