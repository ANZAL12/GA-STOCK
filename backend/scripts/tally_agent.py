#!/usr/bin/env python3
"""
TallyPrime Local Connector Agent for GA STOCK
---------------------------------------------
A lightweight, secure connector designed to run on the office PC where
TallyPrime is hosted (default port 9000).

Extracts newly created / modified Sales Bills from local Tally,
STRIPS ALL FINANCIAL DATA (Rate, Amount, Tax, Discount, Ledger Totals),
and securely transmits only non-financial voucher and inventory records
to the GA STOCK backend via HTTPS.

Usage:
  python tally_agent.py --test
  python tally_agent.py --once
  python tally_agent.py --loop --interval 60
"""

import argparse
import configparser
import json
import logging
import os
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("TallyAgent")


# ---------------------------------------------------------------------------
# Non-Financial XML Extraction & Parsing
# ---------------------------------------------------------------------------

def clean_text(elem: Optional[ET.Element]) -> str:
    if elem is None or elem.text is None:
        return ""
    return elem.text.strip()


def parse_quantity(qty_str: Optional[str]) -> Tuple[float, Optional[str]]:
    if not qty_str:
        return 0.0, None
    s = qty_str.strip()
    match = re.search(r"^(-?[\d\.]+)\s*([A-Za-z0-9]+)?", s)
    if match:
        try:
            return float(match.group(1)), match.group(2)
        except ValueError:
            pass
    return 0.0, None


def parse_tally_date(date_str: Optional[str]) -> str:
    if not date_str:
        return date.today().isoformat()
    s = date_str.strip()
    if len(s) == 8 and s.isdigit():
        try:
            return date(int(s[:4]), int(s[4:6]), int(s[6:8])).isoformat()
        except ValueError:
            pass
    for fmt in ("%Y-%m-%d", "%d-%b-%Y", "%d-%B-%Y", "%d-%m-%Y"):
        try:
            return datetime.strptime(s, fmt).date().isoformat()
        except ValueError:
            continue
    return date.today().isoformat()


def build_tally_export_xml(
    company_name: Optional[str] = None,
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
) -> str:
    company_tag = f"<SVCURRENTCOMPANY>{company_name}</SVCURRENTCOMPANY>" if company_name else ""
    from_tag = f"<SVFROMDATE>{from_date}</SVFROMDATE>" if from_date else ""
    to_tag = f"<SVTODATE>{to_date}</SVTODATE>" if to_date else ""

    return f"""<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Export Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <EXPORTDATA>
      <REQUESTDESC>
        <STATICVARIABLES>
          <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
          {company_tag}
          {from_tag}
          {to_tag}
        </STATICVARIABLES>
        <TDL>
          <TDLMESSAGE>
            <COLLECTION NAME="GAStockSales" ISINITIALIZE="Yes">
              <TYPE>Voucher</TYPE>
              <FILTER>IsSalesVch</FILTER>
              <!-- STRICTLY NON-FINANCIAL TAGS ONLY -->
              <FETCH>GUID,ALTERID,MASTERID,DATE,VOUCHERNUMBER,VOUCHERTYPENAME,PARTYNAME,PARTYLEDGERNAME,BASICBUYERNAME,ADDRESS.LIST,STATENAME,ISCANCELLED,ISDELETED,NARRATION</FETCH>
              <FETCH>ALLINVENTORYENTRIES.STOCKITEMNAME,ALLINVENTORYENTRIES.ACTUALQTY,ALLINVENTORYENTRIES.BILLEDQTY,ALLINVENTORYENTRIES.UNIT,ALLINVENTORYENTRIES.BATCHALLOCATIONS.*</FETCH>
              <FETCH>INVENTORYENTRIES.STOCKITEMNAME,INVENTORYENTRIES.ACTUALQTY,INVENTORYENTRIES.BILLEDQTY,INVENTORYENTRIES.UNIT,INVENTORYENTRIES.BATCHALLOCATIONS.*</FETCH>
            </COLLECTION>
            <SYSTEM TYPE="Formulae" NAME="IsSalesVch">
              $$IsSales:$VoucherTypeName
            </SYSTEM>
          </TDLMESSAGE>
        </TDL>
      </REQUESTDESC>
    </EXPORTDATA>
  </BODY>
</ENVELOPE>"""


def parse_vouchers_from_xml(xml_content: str, company_name: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Parses Tally XML response into non-financial voucher dictionaries.
    ABSOLUTELY NO RATE, AMOUNT, TAX, DISCOUNT OR FINANCIAL INFO IS EXTRACTED.
    """
    vouchers: List[Dict[str, Any]] = []
    if not xml_content or not xml_content.strip():
        return vouchers

    try:
        root = ET.fromstring(xml_content)
    except ET.ParseError as e:
        logger.error(f"XML parse error from Tally response: {e}")
        return vouchers

    for vch in root.iter("VOUCHER"):
        vch_type = clean_text(vch.find("VOUCHERTYPENAME")) or vch.attrib.get("VCHTYPE", "")
        if vch_type and "sales" not in vch_type.lower():
            continue

        guid = clean_text(vch.find("GUID"))
        vch_num = clean_text(vch.find("VOUCHERNUMBER"))
        raw_date = clean_text(vch.find("DATE"))
        iso_date = parse_tally_date(raw_date)

        if not guid:
            guid = f"TALLY-{company_name or 'GA'}-{vch_num}-{raw_date}"

        alter_id_str = clean_text(vch.find("ALTERID"))
        alter_id = int(alter_id_str) if alter_id_str.isdigit() else None

        master_id_str = clean_text(vch.find("MASTERID"))
        master_id = int(master_id_str) if master_id_str.isdigit() else None

        party_name = (
            clean_text(vch.find("PARTYNAME"))
            or clean_text(vch.find("PARTYLEDGERNAME"))
            or clean_text(vch.find("BASICBUYERNAME"))
            or "Unknown Party"
        )
        party_ledger = clean_text(vch.find("PARTYLEDGERNAME")) or None
        buyer_name = clean_text(vch.find("BASICBUYERNAME")) or None
        state_name = clean_text(vch.find("STATENAME")) or None

        address_lines = []
        addr_list = vch.find("ADDRESS.LIST")
        if addr_list is not None:
            for a in addr_list.iter("ADDRESS"):
                txt = clean_text(a)
                if txt:
                    address_lines.append(txt)
        address = ", ".join(address_lines) if address_lines else None

        is_cancelled = clean_text(vch.find("ISCANCELLED")).lower() in ("yes", "true", "1")
        is_deleted = clean_text(vch.find("ISDELETED")).lower() in ("yes", "true", "1")
        narration = clean_text(vch.find("NARRATION")) or None

        # Parse items (STRICTLY NON-FINANCIAL)
        items: List[Dict[str, Any]] = []
        inv_nodes = list(vch.findall("ALLINVENTORYENTRIES.LIST")) + list(vch.findall("INVENTORYENTRIES.LIST"))
        for inv in inv_nodes:
            stock_name = clean_text(inv.find("STOCKITEMNAME"))
            if not stock_name:
                continue

            item_code = clean_text(inv.find("STOCKITEMID")) or clean_text(inv.find("PARTNO")) or None
            raw_qty = clean_text(inv.find("ACTUALQTY")) or clean_text(inv.find("BILLEDQTY"))
            qty, uom_from_qty = parse_quantity(raw_qty)
            uom = clean_text(inv.find("UNIT")) or uom_from_qty

            godown_name = None
            batch_name = None
            batches: List[Dict[str, Any]] = []

            for b in inv.findall("BATCHALLOCATIONS.LIST"):
                b_godown = clean_text(b.find("GODOWNNAME"))
                b_batch = clean_text(b.find("BATCHNAME"))
                b_raw_qty = clean_text(b.find("ACTUALQTY")) or clean_text(b.find("BILLEDQTY"))
                b_qty, b_uom = parse_quantity(b_raw_qty)

                if not godown_name and b_godown:
                    godown_name = b_godown
                if not batch_name and b_batch and b_batch.lower() != "primary batch":
                    batch_name = b_batch

                batches.append({
                    "godown": b_godown or None,
                    "batch": b_batch or None,
                    "quantity": b_qty,
                    "uom": b_uom or uom,
                })

            if not godown_name:
                godown_name = clean_text(inv.find("GODOWNNAME")) or None

            items.append({
                "item_name": stock_name,
                "item_code": item_code,
                "quantity": qty,
                "uom": uom,
                "raw_qty_text": raw_qty or None,
                "godown_name": godown_name,
                "batch_name": batch_name,
                "batch_details": {"allocations": batches} if len(batches) > 1 else None,
            })

        vouchers.append({
            "guid": guid,
            "alter_id": alter_id,
            "master_id": master_id,
            "voucher_number": vch_num or "VCH-UNNUMBERED",
            "voucher_date": iso_date,
            "voucher_type": vch_type or "Sales",
            "party_name": party_name,
            "party_ledger_name": party_ledger,
            "buyer_name": buyer_name,
            "address": address,
            "state_name": state_name,
            "company_name": company_name,
            "is_cancelled": is_cancelled,
            "is_deleted": is_deleted,
            "notes": narration,
            "raw_metadata": {"narration": narration} if narration else None,
            "items": items,
        })

    return vouchers


# ---------------------------------------------------------------------------
# HTTP Communication
# ---------------------------------------------------------------------------

def post_to_tally(tally_url: str, xml_body: str, timeout: int = 15) -> str:
    req = urllib.request.Request(
        tally_url,
        data=xml_body.encode("utf-8"),
        headers={"Content-Type": "application/xml; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def push_to_backend(backend_url: str, agent_token: str, payload: Dict[str, Any], timeout: int = 20) -> Dict[str, Any]:
    url = f"{backend_url.rstrip('/')}/api/v1/tally/agent/push"
    data_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data_bytes,
        headers={
            "Content-Type": "application/json",
            "X-Tally-Agent-Token": agent_token,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


# ---------------------------------------------------------------------------
# Main Controller & CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="TallyPrime Local Connector Agent for GA STOCK")
    parser.add_argument("--backend-url", default=os.getenv("GA_BACKEND_URL", "http://localhost:8000"), help="GA STOCK backend URL")
    parser.add_argument("--agent-token", default=os.getenv("GA_AGENT_TOKEN", ""), help="Agent token from Tally config in GA STOCK")
    parser.add_argument("--tally-host", default=os.getenv("TALLY_HOST", "localhost"), help="Tally host")
    parser.add_argument("--tally-port", type=int, default=int(os.getenv("TALLY_PORT", "9000")), help="Tally port (default 9000)")
    parser.add_argument("--company", default=os.getenv("TALLY_COMPANY", ""), help="Active Tally company name")
    parser.add_argument("--interval", type=int, default=60, help="Loop interval in seconds (default 60)")
    parser.add_argument("--days", type=int, default=30, help="Days back to sync on full run (default 30)")
    parser.add_argument("--test", action="store_true", help="Test connectivity to Tally and backend")
    parser.add_argument("--once", action="store_true", help="Perform single synchronization and exit")
    parser.add_argument("--loop", action="store_true", help="Run continuous background loop")

    args = parser.parse_args()

    tally_url = f"http://{args.tally_host}:{args.tally_port}"

    if args.test:
        logger.info(f"Testing local connection to Tally at {tally_url}...")
        try:
            test_xml = """<ENVELOPE><HEADER><TALLYREQUEST>Export Data</TALLYREQUEST></HEADER><BODY><EXPORTDATA><REQUESTDESC><REPORTNAME>List of Companies</REPORTNAME><STATICVARIABLES><SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT></STATICVARIABLES></REQUESTDESC></EXPORTDATA></BODY></ENVELOPE>"""
            resp = post_to_tally(tally_url, test_xml, timeout=5)
            logger.info("✓ TallyPrime is reachable and responding!")
        except Exception as e:
            logger.error(f"✗ Cannot connect to TallyPrime at {tally_url}: {e}")

        logger.info(f"Testing backend connection to {args.backend_url}...")
        try:
            health_url = f"{args.backend_url.rstrip('/')}/health"
            with urllib.request.urlopen(health_url, timeout=5) as r:
                res_data = json.loads(r.read().decode("utf-8"))
                logger.info(f"✓ GA STOCK backend is reachable: {res_data}")
        except Exception as e:
            logger.error(f"✗ Cannot connect to GA STOCK backend at {args.backend_url}: {e}")

        return

    def do_sync():
        logger.info("Fetching Sales Vouchers from local TallyPrime...")
        active_company = args.company
        if not active_company:
            try:
                comp_req = """<ENVELOPE><HEADER><TALLYREQUEST>Export Data</TALLYREQUEST></HEADER><BODY><EXPORTDATA><REQUESTDESC><REPORTNAME>List of Companies</REPORTNAME><STATICVARIABLES><SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT></STATICVARIABLES></REQUESTDESC></EXPORTDATA></BODY></ENVELOPE>"""
                c_resp = post_to_tally(tally_url, comp_req, timeout=5)
                c_root = ET.fromstring(c_resp)
                for comp_elem in c_root.iter():
                    if comp_elem.tag.upper() in ("COMPANY", "NAME") and comp_elem.text and comp_elem.text.strip():
                        txt = comp_elem.text.strip()
                        if txt not in ("List of Companies", "XML"):
                            active_company = txt
                            break
            except Exception as ce:
                logger.debug(f"Could not auto-detect company name: {ce}")

        from_d = (date.today() - timedelta(days=args.days)).strftime("%Y%m%d")
        to_d = date.today().strftime("%Y%m%d")

        xml_req = build_tally_export_xml(
            company_name=active_company if active_company else None,
            from_date=from_d,
            to_date=to_d,
        )

        try:
            xml_resp = post_to_tally(tally_url, xml_req, timeout=30)
            vouchers = parse_vouchers_from_xml(xml_resp, company_name=active_company)
            logger.info(f"Extracted {len(vouchers)} sales vouchers from Tally ({active_company or 'Default Company'}, Non-financial data only).")

            if not args.agent_token:
                logger.warning("No --agent-token provided. Cannot push to GA STOCK backend.")
                return

            payload = {
                "company_name": active_company or None,
                "vouchers": vouchers,
            }

            resp = push_to_backend(args.backend_url, args.agent_token, payload)
            logger.info(f"✓ Pushed to GA STOCK backend: {resp}")
        except urllib.error.URLError as e:
            logger.error(f"Network error during sync: {e}")
        except Exception as e:
            logger.error(f"Error during sync: {e}")

    if args.once or not args.loop:
        do_sync()
    else:
        logger.info(f"Starting TallyPrime continuous connector loop (Interval: {args.interval}s)...")
        while True:
            try:
                do_sync()
            except Exception as e:
                logger.error(f"Unhandled loop error: {e}")
            time.sleep(args.interval)


if __name__ == "__main__":
    main()

