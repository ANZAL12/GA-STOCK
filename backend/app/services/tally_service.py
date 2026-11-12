import asyncio
import json
import logging
import os
import re
import secrets
import time
import uuid
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import httpx
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import AsyncSessionLocal
from app.config import settings
from app.core.websocket_manager import ws_manager
from app.models.category import Category
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.shop import Shop
from app.models.tally import (
    TallyConfig,
    TallySalesVoucher,
    TallySyncHistory,
    TallyVoucherItem,
)

logger = logging.getLogger("tally_service")
if not logger.handlers:
    _tally_handler = logging.StreamHandler()
    _tally_handler.setFormatter(logging.Formatter("%(levelname)s: %(message)s"))
    logger.addHandler(_tally_handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False


# ---------------------------------------------------------------------------
# XML Helper Utilities
# ---------------------------------------------------------------------------

def escape_xml(text: Optional[str]) -> str:
    if not text:
        return ""
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


def sanitize_tally_xml(xml_content: str) -> str:
    """
    Sanitizes Tally XML by stripping illegal XML character entity references
    (like &#4; in CSTFORMISSUETYPE), unprintable control characters, and
    undeclared XML namespace prefixes (like <UDF:...> emitted by TallyPrime
    without xmlns:UDF) that cause standard XML parsers to fail.
    """
    if not xml_content:
        return ""
    # Strip illegal XML entity references &#0; through &#8;, &#11;, &#12;, &#14; through &#31;
    s = re.sub(r'&#(?:[0-8]|1[1-2]|1[4-9]|[2-3][0-9]);', '', xml_content)
    # Strip raw control characters except tab, newline, and carriage return
    s = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', s)
    # Strip undeclared namespace prefixes on tags (e.g. <UDF:VCHCREATEDAMT> -> <VCHCREATEDAMT>)
    declared_ns = set(re.findall(r'xmlns:([A-Za-z_][\w.-]*)\s*=', s))
    declared_ns.add("xml")

    def _strip_unbound_prefix(match: re.Match) -> str:
        slash, prefix = match.group(1), match.group(2)
        if prefix in declared_ns:
            return match.group(0)
        return f"<{slash}"

    s = re.sub(r'<(/?)([A-Za-z_][\w.-]*):(?=[A-Za-z_])', _strip_unbound_prefix, s)
    return s


def clean_xml_text(elem: Optional[ET.Element]) -> str:
    if elem is None or elem.text is None:
        return ""
    return elem.text.strip()


GSTIN_REGEX = re.compile(r"\b([0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1})\b", re.IGNORECASE)


def extract_gstin(text: Optional[str]) -> Optional[str]:
    """Extract and validate 15-character Indian GSTIN from string."""
    if not text:
        return None
    cleaned = text.strip().replace("-", "").replace(" ", "").upper()
    match = GSTIN_REGEX.search(cleaned)
    if match:
        return match.group(1).upper()
    match_raw = GSTIN_REGEX.search(text.strip())
    if match_raw:
        return match_raw.group(1).upper()
    return None


def extract_gstin_from_element(elem: Optional[ET.Element]) -> Optional[str]:
    """
    Exhaustively searches an XML element (Ledger or Voucher) for GSTIN.
    Checks priority tags, nested mailing/statutory lists, and all child text.
    """
    if elem is None:
        return None

    # 1. Direct priority tags
    PRIORITY_TAGS = (
        "PARTYGSTIN",
        "GSTIN",
        "BUYERGSTIN",
        "CONSIGNEEGSTIN",
        "COUNTRYGSTIN",
        "GSTREGISTRATIONNUMBER",
        "LEDGERGSTIN",
        "PARTYREGISTRATIONNUMBER",
    )
    for tag in PRIORITY_TAGS:
        val = clean_xml_text(elem.find(tag))
        if val:
            g = extract_gstin(val)
            if g:
                return g

    # 2. Check nested lists (TallyPrime 3/4/5 puts it in LEDGSTREGDETAILS.LIST)
    for list_tag in ("LEDGSTREGDETAILS.LIST", "MAILINGDETAILS.LIST", "LEDGERENTRIES.LIST"):
        nested = elem.find(list_tag)
        if nested is not None:
            for child in nested.iter():
                txt = clean_xml_text(child)
                if txt:
                    g = extract_gstin(txt)
                    if g:
                        return g

    # 3. Regex search all children with GST, REG, or TAX in tag name
    for child in elem.iter():
        tag = child.tag.upper().split("}")[-1]
        if any(kw in tag for kw in ("GST", "REG", "TAX", "TIN", "PARTY", "BUYER")):
            txt = clean_xml_text(child)
            if txt:
                g = extract_gstin(txt)
                if g:
                    return g

    return None


def get_shop_root_name(name: str) -> str:
    """
    Normalizes shop name by removing brand suffixes/prefixes, e.g.:
    'UNIVERSAL AGENCIES - DAIKIN' -> 'UNIVERSAL AGENCIES'
    'UNIVERSAL AGENCIES (VOLTAS)' -> 'UNIVERSAL AGENCIES'
    'UNIVERSAL AGENCIES [LG]' -> 'UNIVERSAL AGENCIES'
    'UNIVERSAL AGENCIES - AC DIVISION' -> 'UNIVERSAL AGENCIES'
    'ABC ELECTRONICS DAIKIN' -> 'ABC ELECTRONICS'
    """
    if not name:
        return ""
    s = name.strip()

    # 1. Strip trailing parentheses or brackets
    s = re.sub(r"\s*[\(\[\{][^\)\]\}]*[\)\]\}]\s*$", "", s).strip()

    # 2. Strip trailing dash/slash brand identifiers
    s = re.sub(
        r"\s*[-–/:]\s*(daikin|voltas|lg|samsung|carrier|panasonic|hitachi|blue\s*star|mitsubishi|lloyd|godrej|haier|whirlpool|general|o\s*general|brand|division|distributor|dealer|sales|ac|service|branch|retail|wholesale|c&f).*$",
        "",
        s,
        flags=re.IGNORECASE,
    ).strip()

    # 3. Strip trailing plain brand words if there are multiple words
    words = s.split()
    if len(words) > 2:
        s = re.sub(
            r"\s+(daikin|voltas|lg|samsung|carrier|panasonic|hitachi|blue\s*star|mitsubishi|lloyd|godrej|haier|whirlpool|general|o\s*general|ac|division)$",
            "",
            s,
            flags=re.IGNORECASE,
        ).strip()

    # 4. Clean multiple spaces
    s = re.sub(r"\s+", " ", s).strip()
    return s if len(s) >= 3 else name.strip()


def parse_tally_quantity(qty_str: Optional[str]) -> Tuple[float, Optional[str]]:
    """
    Parses Tally quantity strings like:
      ' 10 NOS' -> (10.0, 'NOS')
      ' 1,200 NOS' -> (1200.0, 'NOS')
      '-5 SET' -> (-5.0, 'SET')
      ' 100.50 KGS' -> (100.5, 'KGS')
      '12' -> (12.0, None)
    """
    if not qty_str:
        return 0.0, None
    s = str(qty_str).replace(",", "").strip()
    match = re.search(r"^(-?[\d\.]+)\s*([A-Za-z0-9]+)?", s)
    if match:
        try:
            val = float(match.group(1))
            uom = match.group(2) if match.group(2) else None
            return val, uom
        except ValueError:
            pass
    return 0.0, None


KNOWN_TALLY_BRANDS = (
    "CARRIER", "MIDEA", "O GENERAL", "GENERAL", "FUJITSU", "FORMENTY", "FMTY",
    "ROCKWELL", "CELFROST", "HAIER", "MITSUBISHI", "AMSTRAD", "WHIRLPOOL",
    "GODREJ", "GOGREJ", "BOSCH", "LLOYD", "IFB", "SAMSUNG", "LG", "DAIKIN", "VOLTAS",
    "BLUE STAR", "BLUESTAR", "PANASONIC", "HITACHI", "ZAROOKY",
)


def extract_clean_brand_and_model(item_name: str, parent_group: Optional[str] = None) -> Tuple[str, str]:
    """
    Extracts the true clean brand and model code from a Tally stock item name.
    Eliminates category prefixes ('AC ', 'WM ', 'REF ', 'LED ', 'W/M ') and
    redundant brand repetitions (e.g. 'CARRIER CARRIER AC 12K...').
    """
    if not item_name:
        return "General", ""

    raw_name = item_name.strip()

    # 1. Detect Brand
    brand = None
    for b in KNOWN_TALLY_BRANDS:
        if re.search(r"\b" + re.escape(b) + r"\b", raw_name, re.I):
            brand = b
            if b in ("FMTY", "ZAROOKY"):
                brand = "FORMENTY"
            elif b == "O GENERAL":
                brand = "GENERAL"
            elif b == "GOGREJ":
                brand = "GODREJ"
            elif b == "BLUESTAR":
                brand = "BLUE STAR"
            break

    if not brand and parent_group:
        for b in KNOWN_TALLY_BRANDS:
            if re.search(r"\b" + re.escape(b) + r"\b", parent_group, re.I):
                brand = b
                if b == "FMTY":
                    brand = "FORMENTY"
                break

    if not brand:
        if any(kw in raw_name.lower() or (parent_group and kw in parent_group.lower()) for kw in ["stand", "trolly", "trolley", "pipe", "cover", "rubber coupler", "gear teeth", "cutter", "switch", "jar", "motor"]):
            brand = "Local"
        elif parent_group and parent_group.upper() not in ("GENERAL", "LOCAL", "AC", "WM", "REF", "LED"):
            brand = parent_group
        else:
            first = raw_name.split()[0]
            if first.upper() in ("AC", "WM", "REF", "LED", "W/M", "STAND"):
                brand = "General"
            else:
                brand = first

    brand = (brand or "General").strip().upper()
    if brand == "GOGREJ":
        brand = "GODREJ"

    # 2. Extract Model Code
    model = raw_name
    # Strip leading category noise
    model = re.sub(r"^(?:AC|WM|REF|LED|W/M)\s+", "", model, flags=re.I).strip()

    # Strip leading brand if present in model
    if brand:
        model = re.sub(r"^" + re.escape(brand) + r"[:\s\-]+", "", model, flags=re.I).strip()
        if brand == "FORMENTY":
            model = re.sub(r"^(?:FMTY|FORMENTY)[:\s\-]+", "", model, flags=re.I).strip()

    # Strip trailing brand from model
    if brand:
        model = re.sub(r"[\s\-]+" + re.escape(brand) + r"\s*$", "", model, flags=re.I).strip()
        if brand == "FORMENTY":
            model = re.sub(r"[\s\-]+(?:FMTY|FORMENTY)\s*$", "", model, flags=re.I).strip()

    model = model.strip() or raw_name
    return brand, model


def parse_tally_date(date_str: Optional[str]) -> date:
    """
    Parses Tally date strings like '20261105' (YYYYMMDD), '2026-11-05', or '5-Nov-2026'.
    """
    if not date_str:
        return date.today()
    s = date_str.strip()
    if len(s) == 8 and s.isdigit():
        try:
            return date(int(s[:4]), int(s[4:6]), int(s[6:8]))
        except ValueError:
            pass
    for fmt in ("%Y-%m-%d", "%d-%b-%Y", "%d-%B-%Y", "%d-%m-%Y"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return date.today()


def format_date_for_tally(d: Optional[date]) -> str:
    """Format date as YYYYMMDD for Tally XML envelopes."""
    if not d:
        return ""
    return d.strftime("%Y%m%d")


def format_date_for_tdl(d: Optional[date]) -> Optional[str]:
    """Format date as d-Mmm-yyyy for TDL $$Date formula (e.g. 1-Apr-2026, 31-Mar-2027)."""
    if not d:
        return None
    return f"{d.day}-{d.strftime('%b')}-{d.year}"


def _clean_sv_company(company_name: Optional[str]) -> str:
    """Returns <SVCURRENTCOMPANY> XML tag only if valid non-empty, non-zero company name is given."""
    if not company_name:
        return ""
    c = company_name.strip()
    if not c or c == "0" or c.isdigit():
        return ""
    return f"<SVCURRENTCOMPANY>{escape_xml(c)}</SVCURRENTCOMPANY>"


# ---------------------------------------------------------------------------
# XML Request Generators
# ---------------------------------------------------------------------------

class TallyXmlBuilder:
    @staticmethod
    def build_company_list_request() -> str:
        return """<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Export Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <EXPORTDATA>
      <REQUESTDESC>
        <REPORTNAME>List of Companies</REPORTNAME>
        <STATICVARIABLES>
          <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        </STATICVARIABLES>
      </REQUESTDESC>
    </EXPORTDATA>
  </BODY>
</ENVELOPE>"""

    @staticmethod
    def build_company_collection_request() -> str:
        return """<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>Company Collection</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="Company Collection">
            <TYPE>Company</TYPE>
            <FETCH>Name, StartingFrom, EndingAt, Guid</FETCH>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""

    @staticmethod
    def build_sales_vouchers_request(
        company_name: Optional[str] = None,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
        alter_id: Optional[int] = None,
    ) -> str:
        sv_company = _clean_sv_company(company_name)

        filters = ["<FILTER>InvFilt</FILTER>"]
        formulae = ['<SYSTEM TYPE="Formulae" NAME="InvFilt">$IsInvoice OR $IsCancelled</SYSTEM>']

        if alter_id is not None and alter_id > 0:
            filters.append("<FILTER>AlterFilt</FILTER>")
            formulae.append(f'<SYSTEM TYPE="Formulae" NAME="AlterFilt">$AlterID &gt; {alter_id}</SYSTEM>')
        else:
            if from_date:
                tdl_from = format_date_for_tdl(from_date)
                filters.append("<FILTER>FromDateFilt</FILTER>")
                formulae.append(f'<SYSTEM TYPE="Formulae" NAME="FromDateFilt">$Date &gt;= $$Date:"{tdl_from}"</SYSTEM>')
            if to_date:
                tdl_to = format_date_for_tdl(to_date)
                filters.append("<FILTER>ToDateFilt</FILTER>")
                formulae.append(f'<SYSTEM TYPE="Formulae" NAME="ToDateFilt">$Date &lt;= $$Date:"{tdl_to}"</SYSTEM>')

        filter_tags_str = "\n            ".join(filters)
        formulae_tags_str = "\n          ".join(formulae)

        return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>SalesInvoiceCollection</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        {sv_company}
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="SalesInvoiceCollection">
            <TYPE>Voucher</TYPE>
            <FETCH>VOUCHERNUMBER, VOUCHERTYPENAME, DATE, PARTYLEDGERNAME, ALTERID, MASTERID, GUID, STATENAME, PLACEOFSUPPLY, NARRATION, ISCANCELLED, ISDELETED, BASICBUYERNAME, BASICBUYERADDRESS.LIST, ADDRESS.LIST, PARTYGSTIN, LEDGERGSTIN, ALLINVENTORYENTRIES.LIST, ALLINVENTORYENTRIES.*</FETCH>
            {filter_tags_str}
          </COLLECTION>
          {formulae_tags_str}
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""

    @staticmethod
    def build_fallback_voucher_register_request(
        company_name: Optional[str] = None,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
    ) -> str:
        sv_company = _clean_sv_company(company_name)
        sv_from = f"<SVFROMDATE>{format_date_for_tally(from_date)}</SVFROMDATE>" if from_date else ""
        sv_to = f"<SVTODATE>{format_date_for_tally(to_date)}</SVTODATE>" if to_date else ""

        return f"""<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Export Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <EXPORTDATA>
      <REQUESTDESC>
        <REPORTNAME>Day Book</REPORTNAME>
        <STATICVARIABLES>
          <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
          <EXPLODEFLAG>Yes</EXPLODEFLAG>
          {sv_company}
          {sv_from}
          {sv_to}
        </STATICVARIABLES>
      </REQUESTDESC>
    </EXPORTDATA>
  </BODY>
</ENVELOPE>"""

    @staticmethod
    def build_stock_items_request(company_name: Optional[str] = None) -> str:
        sv_company = _clean_sv_company(company_name)
        return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>StockItemsCollection</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        {sv_company}
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="StockItemsCollection">
            <TYPE>StockItem</TYPE>
            <FETCH>Name, Parent, Guid, PartNo, MailingName, BaseUnits, Description</FETCH>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""

    @staticmethod
    def build_stock_groups_request(company_name: Optional[str] = None) -> str:
        sv_company = _clean_sv_company(company_name)
        return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>StockGroupsCollection</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        {sv_company}
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="StockGroupsCollection">
            <TYPE>StockGroup</TYPE>
            <FETCH>Name, Parent, Guid</FETCH>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""

    @staticmethod
    def build_stock_summary_request(company_name: Optional[str] = None) -> str:
        sv_company = _clean_sv_company(company_name)
        return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>StockBalanceCollection</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        {sv_company}
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="StockBalanceCollection">
            <TYPE>StockItem</TYPE>
            <FETCH>Name, ClosingBalance</FETCH>
            <FILTER>NonZeroBalFilt</FILTER>
          </COLLECTION>
          <SYSTEM TYPE="Formulae" NAME="NonZeroBalFilt">NOT $$IsEmpty:$ClosingBalance</SYSTEM>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""

    @staticmethod
    def build_ledgers_request(company_name: Optional[str] = None) -> str:
        sv_company = _clean_sv_company(company_name)
        return f"""<ENVELOPE>
  <HEADER>
    <VERSION>1</VERSION>
    <TALLYREQUEST>Export</TALLYREQUEST>
    <TYPE>Collection</TYPE>
    <ID>DebtorsCollection</ID>
  </HEADER>
  <BODY>
    <DESC>
      <STATICVARIABLES>
        <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        {sv_company}
      </STATICVARIABLES>
      <TDL>
        <TDLMESSAGE>
          <COLLECTION NAME="DebtorsCollection">
            <TYPE>Ledger</TYPE>
            <CHILDOF>Sundry Debtors</CHILDOF>
            <BELONGSTO>Yes</BELONGSTO>
            <FETCH>Name, Parent, Guid, PartyGSTIN, LedgerGSTIN, LedgerPhone, LedgerMobile, LedgerContact, Email, StateName, LedStateName, Pincode, Address.List, LedMailingDetails.List, LedGSTRegDetails.List</FETCH>
          </COLLECTION>
        </TDLMESSAGE>
      </TDL>
    </DESC>
  </BODY>
</ENVELOPE>"""


# ---------------------------------------------------------------------------
# XML Response Parser
# ---------------------------------------------------------------------------

class TallyXmlParser:
    @staticmethod
    def parse_companies(xml_content: str) -> List[Dict[str, Any]]:
        """Extract open company list from Tally XML response."""
        companies: List[Dict[str, Any]] = []
        if not xml_content or not xml_content.strip():
            return companies

        xml_clean = sanitize_tally_xml(xml_content)
        try:
            root = ET.fromstring(xml_clean)
        except ET.ParseError as e:
            logger.warning(f"Error parsing company XML from Tally: {e}")
            return companies

        seen_names = set()

        # 1. Check for current active company in Day Book / Tally envelope
        cur_comp = root.findtext(".//SVCURRENTCOMPANY")
        if cur_comp and cur_comp.strip() and not cur_comp.strip().isdigit() and cur_comp.strip() != "0":
            name = cur_comp.strip()
            seen_names.add(name)
            companies.append({"name": name})

        # 2. Check for real COMPANY tags in collection/reports (skip CMPINFO schema header counts)
        for comp in root.iter("COMPANY"):
            name = comp.attrib.get("NAME") or clean_xml_text(comp.find("NAME"))
            if not name:
                rem = comp.find("REMOTECMPINFO.LIST")
                if rem is not None:
                    name = clean_xml_text(rem.find("NAME"))
            if not name and comp.text and not comp.text.strip().isdigit() and len(comp.text.strip()) > 2:
                name = clean_xml_text(comp)

            if (
                name
                and name not in seen_names
                and name not in ("List of Companies", "XML", "0")
                and not name.isdigit()
                and len(name) > 1
                and not (len(name) == 36 and name.count("-") == 4)
            ):
                seen_names.add(name)
                start_from = clean_xml_text(comp.find("STARTINGFROM"))
                end_at = clean_xml_text(comp.find("ENDINGAT"))
                companies.append({
                    "name": name,
                    "starting_from": start_from or None,
                    "ending_at": end_at or None,
                })

        # 3. Check for Tally List of Companies report layout
        if not companies:
            for item in root.iter("REMOTECMPINFO.LIST"):
                name = clean_xml_text(item.find("NAME"))
                if (
                    name
                    and name not in seen_names
                    and not (len(name) == 36 and name.count("-") == 4)
                ):
                    seen_names.add(name)
                    companies.append({
                        "name": name,
                        "starting_from": clean_xml_text(item.find("STARTINGFROM")) or None,
                        "ending_at": clean_xml_text(item.find("ENDINGAT")) or None,
                    })

        return companies

    @staticmethod
    def parse_sales_vouchers(
        xml_content: str, default_company: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Parses sales vouchers from Tally XML response.
        SECURITY GUARANTEE: Never extracts any Rate, Amount, Tax, Discount, or financial data!
        """
        vouchers: List[Dict[str, Any]] = []
        if not xml_content or not xml_content.strip():
            return vouchers

        xml_clean = sanitize_tally_xml(xml_content)
        try:
            root = ET.fromstring(xml_clean)
        except ET.ParseError as e:
            logger.warning(f"Error parsing voucher XML from Tally: {e}")
            return vouchers

        detected_company = root.findtext(".//SVCURRENTCOMPANY") or default_company

        for vch in root.iter("VOUCHER"):
            vch_type = clean_xml_text(vch.find("VOUCHERTYPENAME")) or vch.attrib.get("VCHTYPE", "")

            # Exclude non-sales financial ledger entries (purchase, payment, receipt, contra, journal)
            non_sales = ("purchase", "payment", "receipt", "contra", "journal", "memorandum", "reversing journal")
            if vch_type and vch_type.lower() in non_sales:
                continue

            # Status flags
            is_cancelled = (
                clean_xml_text(vch.find("ISCANCELLED")).lower() in ("yes", "true", "1")
                or vch.attrib.get("ACTION", "").lower() == "cancel"
            )
            is_deleted = (
                clean_xml_text(vch.find("ISDELETED")).lower() in ("yes", "true", "1")
                or vch.attrib.get("ACTION", "").lower() == "delete"
            )

            # Only process vouchers that contain billed inventory items (goods dispatched to customers),
            # unless it is cancelled or deleted in Tally so cancellation can be synchronized to GA STOCK
            inv_nodes = list(vch.findall("ALLINVENTORYENTRIES.LIST")) + list(vch.findall("INVENTORYENTRIES.LIST"))
            if not inv_nodes and not (is_cancelled or is_deleted):
                continue

            # 1. Identifier extraction
            guid = clean_xml_text(vch.find("GUID")) or vch.attrib.get("REMOTEID") or vch.attrib.get("VCHKEY")
            vch_num = clean_xml_text(vch.find("VOUCHERNUMBER")) or vch.attrib.get("VCHKEY", "BILL")
            raw_date = clean_xml_text(vch.find("DATE"))
            parsed_date = parse_tally_date(raw_date)

            # Fallback deterministic GUID if Tally did not provide one
            if not guid:
                guid = f"TALLY-{detected_company or 'GA'}-{vch_num}-{raw_date}"

            alter_id_str = clean_xml_text(vch.find("ALTERID"))
            alter_id = int(alter_id_str) if alter_id_str and alter_id_str.isdigit() else None

            master_id_str = clean_xml_text(vch.find("MASTERID"))
            master_id = int(master_id_str) if master_id_str and master_id_str.isdigit() else None

            # 2. Party & Buyer Information
            party_name = (
                clean_xml_text(vch.find("PARTYNAME"))
                or clean_xml_text(vch.find("PARTYLEDGERNAME"))
                or clean_xml_text(vch.find("BASICBUYERNAME"))
                or "Unknown Party"
            )
            party_ledger_name = clean_xml_text(vch.find("PARTYLEDGERNAME")) or None
            buyer_name = clean_xml_text(vch.find("BASICBUYERNAME")) or None
            state_name = clean_xml_text(vch.find("STATENAME")) or clean_xml_text(vch.find("PLACEOFSUPPLY")) or None

            # Party GSTIN, Phone, Pincode
            party_gstin = extract_gstin_from_element(vch)
            phone = clean_xml_text(vch.find("PHONENUMBER")) or clean_xml_text(vch.find("LEDGERPHONE")) or None
            pincode = clean_xml_text(vch.find("PINCODE")) or clean_xml_text(vch.find("BASICBUYERPINCODE")) or None

            # Address list (check ADDRESS.LIST, BASICBUYERADDRESS.LIST, CONSIGNEEADDRESS.LIST)
            address_lines = []
            for a_tag in ("ADDRESS.LIST", "BASICBUYERADDRESS.LIST", "CONSIGNEEADDRESS.LIST"):
                addr_list = vch.find(a_tag)
                if addr_list is not None:
                    for a in addr_list.iter("ADDRESS"):
                        txt = clean_xml_text(a)
                        if txt and txt not in address_lines:
                            address_lines.append(txt)
            address = ", ".join(address_lines) if address_lines else None

            # 3. Narration
            narration = clean_xml_text(vch.find("NARRATION")) or None

            # 4. Inventory items extraction (STRICTLY NON-FINANCIAL)
            items: List[Dict[str, Any]] = []

            for inv in inv_nodes:
                stock_name = clean_xml_text(inv.find("STOCKITEMNAME"))
                if not stock_name:
                    continue  # skip non-inventory ledger lines

                item_code = (
                    clean_xml_text(inv.find("STOCKITEMID"))
                    or clean_xml_text(inv.find("PARTNO"))
                    or clean_xml_text(inv.find("STOCKITEMCODE"))
                    or None
                )

                # Quantities and units
                raw_qty = clean_xml_text(inv.find("ACTUALQTY")) or clean_xml_text(inv.find("BILLEDQTY"))
                qty, uom_from_qty = parse_tally_quantity(raw_qty)
                uom = clean_xml_text(inv.find("UNIT")) or uom_from_qty

                # Godown and batch allocations
                godown_name = None
                batch_name = None
                batches: List[Dict[str, Any]] = []

                batch_nodes = inv.findall("BATCHALLOCATIONS.LIST")
                for b in batch_nodes:
                    b_godown = clean_xml_text(b.find("GODOWNNAME"))
                    b_batch = clean_xml_text(b.find("BATCHNAME"))
                    b_raw_qty = clean_xml_text(b.find("ACTUALQTY")) or clean_xml_text(b.find("BILLEDQTY"))
                    b_qty, b_uom = parse_tally_quantity(b_raw_qty)

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

                # Check top-level godown if not found in batch allocations
                if not godown_name:
                    godown_name = clean_xml_text(inv.find("GODOWNNAME")) or None

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
                "voucher_date": parsed_date,
                "voucher_type": vch_type or "Sales",
                "party_name": party_name,
                "party_ledger_name": party_ledger_name,
                "buyer_name": buyer_name,
                "address": address,
                "state_name": state_name,
                "party_gstin": party_gstin,
                "phone": phone,
                "pincode": pincode,
                "company_name": detected_company or default_company,
                "is_cancelled": is_cancelled,
                "is_deleted": is_deleted,
                "notes": narration,
                "raw_metadata": {"narration": narration} if narration else None,
                "items": items,
            })

        return vouchers

    @staticmethod
    def parse_stock_groups(xml_content: str) -> List[Dict[str, Any]]:
        """
        Parses Stock Groups from Tally XML response into categories.
        STRICTLY NO FINANCIAL DATA.
        """
        groups: List[Dict[str, Any]] = []
        if not xml_content or not xml_content.strip():
            return groups

        xml_clean = sanitize_tally_xml(xml_content)
        try:
            root = ET.fromstring(xml_clean)
        except Exception as e:
            logger.warning(f"Failed to parse Stock Groups XML: {e}")
            return groups

        for sg in root.iter():
            tag_name = sg.tag.upper().split("}")[-1]
            if tag_name not in ("STOCKGROUP", "GROUP"):
                continue

            name = clean_xml_text(sg.find("NAME")) or sg.attrib.get("NAME")
            if not name or name.strip().lower() in ("primary", ""):
                continue

            parent = clean_xml_text(sg.find("PARENT"))
            guid = clean_xml_text(sg.find("GUID")) or sg.attrib.get("GUID")

            groups.append({
                "name": name.strip(),
                "parent": parent.strip() if parent else None,
                "guid": guid.strip() if guid else None,
            })

        return groups

    @staticmethod
    def parse_stock_items(xml_content: str) -> List[Dict[str, Any]]:
        """
        Parses Stock Items from Tally XML response into products.
        STRICTLY NO FINANCIAL DATA.
        """
        items: List[Dict[str, Any]] = []
        if not xml_content or not xml_content.strip():
            return items

        xml_clean = sanitize_tally_xml(xml_content)
        try:
            root = ET.fromstring(xml_clean)
        except Exception as e:
            logger.warning(f"Failed to parse Stock Items XML: {e}")
            return items

        for si in root.iter():
            tag_name = si.tag.upper().split("}")[-1]
            if tag_name not in ("STOCKITEM", "ITEM"):
                continue

            name = clean_xml_text(si.find("NAME")) or si.attrib.get("NAME")
            if not name or not name.strip():
                continue

            parent = clean_xml_text(si.find("PARENT"))
            part_no = clean_xml_text(si.find("PARTNO")) or clean_xml_text(si.find("MAILINGNAME"))
            base_units = clean_xml_text(si.find("BASEUNITS")) or "piece"
            description = clean_xml_text(si.find("DESCRIPTION"))
            guid = clean_xml_text(si.find("GUID")) or si.attrib.get("GUID")
            alter_id = clean_xml_text(si.find("ALTERID"))

            items.append({
                "name": name.strip(),
                "parent_group": parent.strip() if parent else None,
                "part_number": part_no.strip() if part_no else None,
                "unit": base_units.strip() if base_units else "piece",
                "description": description.strip() if description else None,
                "guid": guid.strip() if guid else None,
                "alter_id": int(alter_id) if alter_id and alter_id.isdigit() else None,
            })

        return items

    @staticmethod
    def parse_stock_summary(xml_content: str) -> Dict[str, int]:
        """
        Parses item-wise Stock Summary from Tally into a dictionary:
        { "clean item name lower": closing_qty_int }
        Handles commas in numbers, negative stock floored at 0, and whitespace normalization.
        """
        stock_map: Dict[str, int] = {}
        if not xml_content or not xml_content.strip():
            return stock_map

        xml_clean = sanitize_tally_xml(xml_content)
        try:
            root = ET.fromstring(xml_clean)
        except Exception as e:
            logger.warning(f"Failed to parse Stock Summary XML: {e}")
            return stock_map

        current_name = None
        for elem in root.iter():
            tag = elem.tag.upper().split("}")[-1]
            if tag == "STOCKITEM":
                item_name = elem.attrib.get("NAME") or clean_xml_text(elem.find(".//NAME"))
                if item_name and item_name.strip():
                    norm_name = " ".join(item_name.split()).lower()
                    bal_text = clean_xml_text(elem.find("CLOSINGBALANCE"))
                    if bal_text:
                        val, _ = parse_tally_quantity(bal_text)
                        stock_map[norm_name] = max(0, int(round(val)))
                    else:
                        stock_map[norm_name] = 0
            elif tag == "DSPACCNAME":
                disp = elem.find("DSPDISPNAME")
                if disp is not None and disp.text:
                    current_name = " ".join(disp.text.split()).lower()
            elif tag == "DSPSTKINFO" and current_name:
                cl = elem.find(".//DSPCLQTY")
                qty_str = cl.text.strip() if (cl is not None and cl.text) else ""
                if qty_str:
                    clean_qty = qty_str.replace(",", "").strip()
                    m = re.search(r"([+-]?\d+(?:\.\d+)?)", clean_qty)
                    qty = max(0, int(round(float(m.group(1))))) if m else 0
                    stock_map[current_name] = qty
                else:
                    stock_map[current_name] = 0
                current_name = None

        return stock_map

    @staticmethod
    def parse_ledgers(xml_content: str) -> List[Dict[str, Any]]:
        """
        Parses customer / debtor ledgers from Tally XML response into shop records.
        Extracts complete details: GSTIN, address lines, state, pincode, phone, email, contact person.
        STRICTLY NO FINANCIAL DATA.
        """
        ledgers: List[Dict[str, Any]] = []
        if not xml_content or not xml_content.strip():
            return ledgers

        xml_clean = sanitize_tally_xml(xml_content)
        try:
            root = ET.fromstring(xml_clean)
        except Exception as e:
            logger.warning(f"Failed to parse Ledgers XML: {e}")
            return ledgers

        for node in root.iter():
            tag_name = node.tag.upper().split("}")[-1]
            if tag_name not in ("LEDGER",):
                continue

            name = clean_xml_text(node.find("NAME")) or node.attrib.get("NAME")
            if not name or not name.strip():
                continue

            guid = clean_xml_text(node.find("GUID")) or node.attrib.get("GUID")
            parent = clean_xml_text(node.find("PARENT")) or ""

            # Check GSTIN (including nested LEDGSTREGDETAILS and MAILINGDETAILS)
            gstin = extract_gstin_from_element(node)

            # Check Address
            address_lines = []
            for a_tag in ("ADDRESS.LIST", "MAILINGDETAILS.LIST"):
                addr_list = node.find(a_tag)
                if addr_list is not None:
                    for a in addr_list.iter("ADDRESS"):
                        txt = clean_xml_text(a)
                        if txt and txt not in address_lines:
                            address_lines.append(txt)
            if not address_lines:
                for a in node.iter("ADDRESS"):
                    txt = clean_xml_text(a)
                    if txt and txt not in address_lines:
                        address_lines.append(txt)
            address = ", ".join(address_lines) if address_lines else None

            # State & Pincode
            state = clean_xml_text(node.find("STATENAME")) or clean_xml_text(node.find("LEDSTATENAME")) or None
            pincode = clean_xml_text(node.find("PINCODE")) or clean_xml_text(node.find("LEDPINCODE")) or None

            # Phone / Mobile
            phone = (
                clean_xml_text(node.find("LEDGERPHONE"))
                or clean_xml_text(node.find("PHONENUMBER"))
                or clean_xml_text(node.find("LEDGERMOBILE"))
                or clean_xml_text(node.find("MOBILENUMBER"))
                or None
            )

            # Contact person & Email
            contact_person = clean_xml_text(node.find("LEDGERCONTACT")) or clean_xml_text(node.find("CONTACTPERSON")) or None
            email = clean_xml_text(node.find("EMAIL")) or None

            ledgers.append({
                "name": name.strip(),
                "guid": guid.strip() if guid else None,
                "parent": parent.strip() if parent else None,
                "gstin": gstin.strip() if gstin else None,
                "address": address.strip() if address else None,
                "state": state.strip() if state else None,
                "pincode": pincode.strip() if pincode else None,
                "phone": phone.strip() if phone else None,
                "contact_person": contact_person.strip() if contact_person else None,
                "email": email.strip() if email else None,
            })

        return ledgers


# ---------------------------------------------------------------------------
# HTTP Client to Tally
# ---------------------------------------------------------------------------

class TallyHttpClient:
    @staticmethod
    def get_url(host: str, port: int, tally_url: Optional[str] = None) -> str:
        if tally_url and tally_url.strip():
            url = tally_url.strip()
            if not url.startswith("http://") and not url.startswith("https://"):
                url = f"http://{url}"
            return url.rstrip("/")
        clean_host = host.strip() if host else "localhost"
        if clean_host.startswith("http://") or clean_host.startswith("https://"):
            return f"{clean_host}:{port}".rstrip("/")
        return f"http://{clean_host}:{port}"

    @classmethod
    async def post_xml(
        cls,
        host: str,
        port: int,
        xml_payload: str,
        tally_url: Optional[str] = None,
        timeout: float = 10.0,
    ) -> str:
        url = cls.get_url(host, port, tally_url)
        headers = {
            "Content-Type": "application/xml; charset=utf-8",
            "Accept": "application/xml",
        }
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post(url, content=xml_payload.encode("utf-8"), headers=headers)
            resp.raise_for_status()
            return resp.text

    @classmethod
    async def test_connection(
        cls,
        host: str,
        port: int,
        tally_url: Optional[str] = None,
        timeout: float = 4.0,
    ) -> Tuple[bool, str, List[Dict[str, Any]]]:
        """Tests if Tally is online and extracts list of open companies."""
        try:
            req_xml = TallyXmlBuilder.build_company_collection_request()
            resp_xml = await cls.post_xml(host, port, req_xml, tally_url, timeout=timeout)
            companies = TallyXmlParser.parse_companies(resp_xml)
            if not companies:
                # Fallback to Day Book request which returns SVCURRENTCOMPANY in native reports
                daybook_xml = TallyXmlBuilder.build_fallback_voucher_register_request()
                try:
                    resp_db = await cls.post_xml(host, port, daybook_xml, tally_url, timeout=timeout)
                    companies = TallyXmlParser.parse_companies(resp_db)
                except Exception:
                    pass
            if not companies:
                try:
                    list_xml = TallyXmlBuilder.build_company_list_request()
                    resp_list = await cls.post_xml(host, port, list_xml, tally_url, timeout=timeout)
                    companies = TallyXmlParser.parse_companies(resp_list)
                except Exception:
                    pass

            return True, "Successfully connected to TallyPrime.", companies
        except httpx.ConnectError:
            url = cls.get_url(host, port, tally_url)
            return False, f"Cannot connect to Tally at {url}. Make sure TallyPrime is open with port {port} enabled.", []
        except httpx.TimeoutException:
            url = cls.get_url(host, port, tally_url)
            return False, f"Connection to Tally timed out after {timeout}s at {url}.", []
        except Exception as e:
            return False, f"Tally connection error: {str(e)}", []

    @classmethod
    async def probe_endpoints(
        cls,
        endpoints: List[Tuple[str, int, Optional[str]]],
        timeout: float = 3.0,
    ) -> List[Tuple[str, int, Optional[str], bool, str, List[Dict[str, Any]]]]:
        """Probes multiple Tally endpoints concurrently and returns status + open companies for each."""
        async def _probe_one(ep: Tuple[str, int, Optional[str]]):
            h, p, u = ep
            ok, msg, comps = await cls.test_connection(h, p, u, timeout=timeout)
            return (h, p, u, ok, msg, comps)

        return list(await asyncio.gather(*(_probe_one(ep) for ep in endpoints)))


# ---------------------------------------------------------------------------
# Database Sync Manager
# ---------------------------------------------------------------------------

class TallySyncService:
    _endpoint_alter_ids: Dict[str, int] = {}
    _alter_cache_loaded: bool = False
    _alter_cache_file: Path = Path(__file__).resolve().parents[2] / ".tally_alter_cache.json"
    _last_probe_states: Dict[str, Tuple[bool, Tuple[str, ...]]] = {}
    _cached_probe_results: Optional[List[Tuple[str, int, Optional[str], bool, str, List[Dict[str, Any]]]]] = None
    _cached_probe_at: float = 0.0
    _endpoint_cooldown_until: Dict[str, float] = {}
    _last_full_alter_poll_at: Dict[str, float] = {}
    _PROBE_CACHE_TTL_SEC: float = 60.0
    _ENDPOINT_ERROR_COOLDOWN_SEC: float = 30.0
    _FULL_ALTER_SWEEP_SEC: float = 120.0

    @classmethod
    def _load_alter_cache(cls) -> None:
        if cls._alter_cache_loaded:
            return
        cls._alter_cache_loaded = True
        try:
            if cls._alter_cache_file.exists():
                raw = json.loads(cls._alter_cache_file.read_text(encoding="utf-8"))
                if isinstance(raw, dict):
                    for k, v in raw.items():
                        if isinstance(k, str) and isinstance(v, int) and v > 0:
                            cls._endpoint_alter_ids[k] = v
        except Exception as e:
            logger.debug(f"[TallySync] Could not load alter cache: {e}")

    @classmethod
    def _save_alter_cache(cls) -> None:
        try:
            cls._alter_cache_file.write_text(
                json.dumps(cls._endpoint_alter_ids, indent=2),
                encoding="utf-8",
            )
        except Exception as e:
            logger.debug(f"[TallySync] Could not save alter cache: {e}")

    @classmethod
    def _log_probe_statuses(
        cls,
        probe_results: List[Tuple[str, int, Optional[str], bool, str, List[Dict[str, Any]]]],
        force_log: bool = False,
    ) -> None:
        connected_count = sum(1 for p in probe_results if p[3])
        total_count = len(probe_results)
        any_changed = False

        for ep_host, ep_port, ep_url, ok, msg, ep_companies in probe_results:
            ep_label = ep_url or f"{ep_host}:{ep_port}"
            comp_names = tuple(
                c["name"].strip()
                for c in ep_companies
                if c.get("name") and c["name"].strip() != "0" and not c["name"].strip().isdigit()
            )
            state_sig = (ok, comp_names)
            prev_sig = cls._last_probe_states.get(ep_label)
            if force_log or prev_sig != state_sig:
                any_changed = True
                cls._last_probe_states[ep_label] = state_sig
                if ok:
                    comp_str = ", ".join(comp_names) if comp_names else "No company open"
                    logger.info(f"[TallySync] {ep_label} -> CONNECTED (Companies: {comp_str})")
                else:
                    logger.warning(f"[TallySync] {ep_label} -> DISCONNECTED ({msg})")

        if any_changed:
            logger.info(f"[TallySync] Tally Connection Summary: {connected_count}/{total_count} host(s) connected.")

    @staticmethod
    def parse_host_entry(entry: str, default_port: int = 9000) -> Optional[Tuple[str, int, Optional[str]]]:
        raw = (entry or "").strip()
        if not raw or raw.startswith("#"):
            return None
        if raw.startswith("http://") or raw.startswith("https://"):
            from urllib.parse import urlparse
            parsed = urlparse(raw)
            host = parsed.hostname or "localhost"
            port = parsed.port or default_port
            return (host, port, raw.rstrip("/"))
        if ":" in raw:
            host_part, port_part = raw.rsplit(":", 1)
            host = host_part.strip()
            if not host or host.startswith("#"):
                return None
            try:
                port = int(port_part.strip())
            except ValueError:
                port = default_port
            return (host, port, None)
        return (raw, default_port, None)

    @classmethod
    def get_configured_endpoints(cls, cfg: Optional[TallyConfig] = None) -> List[Tuple[str, int, Optional[str]]]:
        """
        Builds ordered, deduplicated list of (host, port, tally_url) endpoints
        from TALLY_HOSTS (.env) and the active TallyConfig row.
        """
        endpoints: List[Tuple[str, int, Optional[str]]] = []
        seen: set[Tuple[str, int, str]] = set()

        def _add(ep: Optional[Tuple[str, int, Optional[str]]]) -> None:
            if not ep:
                return
            h, p, u = ep
            h_clean = (h or "").strip()
            u_clean = (u or "").strip()
            if (not h_clean and not u_clean) or h_clean.startswith("#") or u_clean.startswith("#"):
                return
            key = (h_clean.lower(), int(p), u_clean.lower())
            if key not in seen:
                seen.add(key)
                endpoints.append((h_clean, int(p), u))

        raw_hosts = getattr(settings, "tally_hosts", None) or ""
        if raw_hosts.strip():
            for part in raw_hosts.split(","):
                _add(cls.parse_host_entry(part, default_port=settings.tally_port or 9000))

        if cfg:
            # Avoid waiting on unreachable localhost:9000 when TALLY_HOSTS is explicitly configured
            cfg_host_clean = (cfg.host or "").strip().lower()
            if not endpoints or cfg.tally_url or cfg_host_clean not in ("localhost", "127.0.0.1", ""):
                _add((cfg.host, cfg.port, cfg.tally_url))
        elif not endpoints:
            _add((settings.tally_host, settings.tally_port, None))

        return endpoints

    @staticmethod
    async def get_or_create_config(db: AsyncSession) -> TallyConfig:
        res = await db.execute(select(TallyConfig).order_by(TallyConfig.created_at.asc()).limit(1))
        cfg = res.scalar_one_or_none()
        parsed_multi = []
        if getattr(settings, "tally_hosts", None):
            for part in settings.tally_hosts.split(","):
                ep = TallySyncService.parse_host_entry(part, default_port=settings.tally_port or 9000)
                if ep:
                    parsed_multi.append(ep)

        default_host = parsed_multi[0][0] if (settings.tally_host in ("localhost", "127.0.0.1") and parsed_multi) else settings.tally_host
        default_port = parsed_multi[0][1] if (settings.tally_host in ("localhost", "127.0.0.1") and parsed_multi) else settings.tally_port

        if not cfg:
            cfg = TallyConfig(
                host=default_host,
                port=default_port,
                company_name=settings.tally_company_name,
                is_enabled=True,
                auto_sync=settings.tally_auto_sync,
                sync_interval_minutes=settings.tally_sync_interval_minutes,
                last_alter_id=0,
                agent_token=settings.tally_agent_token or secrets.token_urlsafe(32),
            )
            db.add(cfg)
            await db.commit()
            await db.refresh(cfg)
        else:
            changed = False
            if settings.tally_agent_token and cfg.agent_token != settings.tally_agent_token:
                cfg.agent_token = settings.tally_agent_token
                changed = True
            elif not cfg.agent_token:
                cfg.agent_token = secrets.token_urlsafe(32)
                changed = True
            # If settings explicitly configured in .env and config is different
            if settings.tally_host and settings.tally_host != "localhost" and cfg.host != settings.tally_host:
                cfg.host = settings.tally_host
                changed = True
            elif cfg.host in ("localhost", "127.0.0.1") and parsed_multi:
                cfg.host = parsed_multi[0][0]
                cfg.port = parsed_multi[0][1]
                changed = True
            if settings.tally_company_name and not cfg.company_name:
                cfg.company_name = settings.tally_company_name
                changed = True
            if changed:
                await db.commit()
                await db.refresh(cfg)
        return cfg

    @classmethod
    async def cancel_outward_batches_for_bill(
        cls, db: AsyncSession, bill_number: Optional[str]
    ) -> int:
        """
        Marks OutwardBatch and OutwardLines as cancelled when a bill is cancelled in Tally.
        STRICT USER CONSTRAINT:
        Do NOT change SerialNumber status or product stock!
        Godown staff must physically receive and scan the models as Return in Inward.
        """
        if not bill_number or not bill_number.strip():
            return 0

        clean_b = bill_number.strip()
        clean_b_lower = clean_b.lower()

        res = await db.execute(
            select(OutwardBatch).where(
                func.lower(func.trim(OutwardBatch.bill_number)) == clean_b_lower,
                OutwardBatch.is_cancelled == False,
            )
        )
        active_batches = res.scalars().all()
        if not active_batches:
            return 0

        now = datetime.now()
        batch_ids = [b.id for b in active_batches]
        for b in active_batches:
            b.is_cancelled = True
            b.cancelled_at = now
            b.cancel_reason = "Cancelled in TallyPrime"

        lines_res = await db.execute(
            select(OutwardLine).where(
                OutwardLine.batch_id.in_(batch_ids),
                OutwardLine.is_cancelled == False,
            )
        )
        for l in lines_res.scalars().all():
            l.is_cancelled = True

        try:
            await ws_manager.broadcast("stock_updated", {
                "type": "bill_cancelled",
                "bill_number": clean_b,
                "voucher_number": clean_b,
                "reason": "Cancelled in TallyPrime",
            })
            await ws_manager.broadcast("tally_bill_cancelled", {
                "bill_number": clean_b,
                "voucher_number": clean_b,
                "reason": "Cancelled in TallyPrime",
            })
        except Exception as e:
            logger.warning(f"Could not broadcast bill_cancelled event: {e}")

        logger.info(f"Successfully marked {len(active_batches)} outward batch(es) for Bill '{clean_b}' as cancelled.")
        return len(active_batches)

    @classmethod
    async def process_vouchers(
        cls,
        db: AsyncSession,
        voucher_dicts: List[Dict[str, Any]],
        company_name: Optional[str] = None,
    ) -> Tuple[int, int, int]:
        """
        Inserts or updates Tally vouchers and items atomically inside a database transaction.
        Returns: (created_count, updated_count, cancelled_count)
        """
        if not voucher_dicts:
            return 0, 0, 0

        # Pre-load all GA STOCK products for item auto-matching
        prod_res = await db.execute(select(Product))
        all_products = prod_res.scalars().all()
        prod_lookup_by_name = {p.name.strip().lower(): p.id for p in all_products}
        prod_lookup_by_model = {p.model.strip().lower(): p.id for p in all_products}
        prod_by_id = {p.id: p for p in all_products}

        is_tally_2 = bool(company_name and "2025-26" in company_name)
        cat_res = await db.execute(select(Category))
        all_cats = cat_res.scalars().all()
        cat_map = {c.name.strip().lower(): c for c in all_cats}

        default_cat_name = "General (Tally 2)" if is_tally_2 and "general (tally 2)" in cat_map else "General"
        default_cat = cat_map.get(default_cat_name.lower())
        if not default_cat:
            default_cat = cat_map.get("general")
        if not default_cat and all_cats:
            default_cat = all_cats[0]
        if not default_cat:
            default_cat = Category(name="General", has_dual_serial=False, is_active=True, source="TALLY")
            db.add(default_cat)
            await db.flush()

        created = 0
        updated = 0
        cancelled = 0
        new_vouchers_to_broadcast = []

        for v_data in voucher_dicts:
            guid = v_data["guid"]
            alter_id = v_data.get("alter_id")
            master_id = v_data.get("master_id")
            is_cancelled = v_data.get("is_cancelled", False)
            is_deleted = v_data.get("is_deleted", False)

            # Auto-match or auto-create Shop for party_name so shop details are already prepared
            party_name_clean = v_data.get("party_name", "").strip()
            shop = None
            if party_name_clean:
                s_res = await db.execute(
                    select(Shop).where(func.lower(Shop.name) == func.lower(party_name_clean))
                )
                shop = s_res.scalar_one_or_none()
                city_val = v_data.get("state_name")
                if not city_val and v_data.get("address"):
                    city_val = v_data["address"].split(",")[0][:90].strip()

                party_gstin = v_data.get("party_gstin")

                # If voucher XML did not contain GSTIN, check if shop already has one in DB
                if not party_gstin and shop and shop.gstin:
                    party_gstin = shop.gstin
                    v_data["party_gstin"] = party_gstin

                # If STILL no GSTIN, search for sibling brand shops in DB
                if not party_gstin:
                    root_name = get_shop_root_name(party_name_clean)
                    if root_name:
                        rel_res = await db.execute(
                            select(Shop.gstin).where(
                                func.lower(Shop.name).like(f"{root_name.lower()}%"),
                                Shop.gstin.is_not(None),
                                func.length(Shop.gstin) == 15,
                            ).limit(1)
                        )
                        found_g = rel_res.scalar_one_or_none()
                        if found_g:
                            party_gstin = found_g
                            v_data["party_gstin"] = found_g
                            logger.info(f"[TallySync] Inherited GSTIN {found_g} for voucher {v_data.get('voucher_number')} from sibling brand shop for '{party_name_clean}'.")

                if not shop:
                    shop = Shop(
                        name=party_name_clean,
                        city=city_val or "Local",
                        address=v_data.get("address"),
                        state=v_data.get("state_name"),
                        gstin=party_gstin,
                        phone=v_data.get("phone"),
                        pincode=v_data.get("pincode"),
                        source="TALLY",
                        is_active=True,
                    )
                    db.add(shop)
                    await db.flush()
                    try:
                        await ws_manager.broadcast("shop_created", {
                            "id": str(shop.id),
                            "name": shop.name,
                            "city": shop.city,
                            "gstin": shop.gstin,
                            "address": shop.address,
                            "phone": shop.phone,
                            "is_active": True,
                        })
                    except Exception:
                        pass
                else:
                    # Enrich shop details from bill if missing
                    if not shop.gstin and party_gstin:
                        shop.gstin = party_gstin
                    if not shop.address and v_data.get("address"):
                        shop.address = v_data.get("address")
                    if not shop.state and v_data.get("state_name"):
                        shop.state = v_data.get("state_name")
                    if not shop.pincode and v_data.get("pincode"):
                        shop.pincode = v_data.get("pincode")
                    if not shop.phone and v_data.get("phone"):
                        shop.phone = v_data.get("phone")

            # Ensure voucher_date is python date object
            v_date = v_data.get("voucher_date") or v_data.get("date")
            if isinstance(v_date, str):
                v_date = parse_tally_date(v_date)

            # Check existing voucher
            res = await db.execute(
                select(TallySalesVoucher).where(TallySalesVoucher.guid == guid)
            )
            existing_vch = res.scalar_one_or_none()

            if existing_vch:
                # Update existing record
                existing_vch.voucher_number = v_data["voucher_number"]
                existing_vch.voucher_date = v_date
                existing_vch.party_name = v_data["party_name"]
                existing_vch.party_ledger_name = v_data.get("party_ledger_name")
                existing_vch.buyer_name = v_data.get("buyer_name")
                existing_vch.address = v_data.get("address")
                existing_vch.state_name = v_data.get("state_name")
                if company_name:
                    existing_vch.company_name = company_name

                if alter_id is not None:
                    existing_vch.alter_id = alter_id
                if master_id is not None:
                    existing_vch.master_id = master_id

                # Cancellation status
                if is_cancelled or is_deleted:
                    # If cancelled in Tally, delete from DB immediately as requested
                    await db.delete(existing_vch)
                    cancelled += 1
                    await cls.cancel_outward_batches_for_bill(db, v_data.get("voucher_number"))
                    continue
                else:
                    existing_vch.is_cancelled = False
                    existing_vch.is_deleted = False

                if v_data.get("notes"):
                    existing_vch.notes = v_data["notes"]

                # Replace items
                existing_vch.items.clear()
                for itm in v_data.get("items", []):
                    clean_brand, clean_model = extract_clean_brand_and_model(itm["item_name"])
                    item_name_clean = itm["item_name"].strip().lower()
                    clean_model_lower = clean_model.strip().lower()

                    matched_prod_id = (
                        prod_lookup_by_name.get(item_name_clean)
                        or prod_lookup_by_model.get(item_name_clean)
                        or prod_lookup_by_model.get(clean_model_lower)
                        or prod_lookup_by_name.get(clean_model_lower)
                    )

                    if not matched_prod_id:
                        target_cat = None
                        brand_upper = clean_brand.upper()
                        if is_tally_2 and f"{brand_upper.lower()} (tally 2)" in cat_map:
                            target_cat = cat_map[f"{brand_upper.lower()} (tally 2)"]
                        elif brand_upper.lower() in cat_map:
                            target_cat = cat_map[brand_upper.lower()]

                        if not target_cat:
                            target_cat = default_cat

                        auto_p = Product(
                            name=itm["item_name"].strip(),
                            brand=clean_brand,
                            model=clean_model,
                            category_id=target_cat.id,
                            unit=itm.get("uom") or "piece",
                            serial_number_required=True,
                            is_active=True,
                            source="TALLY",
                        )
                        db.add(auto_p)
                        await db.flush()
                        matched_prod_id = auto_p.id
                        prod_lookup_by_name[item_name_clean] = matched_prod_id
                        prod_lookup_by_model[clean_model_lower] = matched_prod_id
                        prod_by_id[matched_prod_id] = auto_p

                    new_itm = TallyVoucherItem(
                        item_name=itm["item_name"],
                        item_code=itm.get("item_code"),
                        product_id=matched_prod_id,
                        quantity=itm["quantity"],
                        uom=itm.get("uom"),
                        raw_qty_text=itm.get("raw_qty_text"),
                        godown_name=itm.get("godown_name"),
                        batch_name=itm.get("batch_name"),
                        batch_details=itm.get("batch_details"),
                    )
                    existing_vch.items.append(new_itm)

                updated += 1
            else:
                # Do not insert cancelled or deleted vouchers into DB
                if is_cancelled or is_deleted:
                    cancelled += 1
                    await cls.cancel_outward_batches_for_bill(db, v_data.get("voucher_number"))
                    continue

                # Create new voucher
                new_vch = TallySalesVoucher(
                    guid=guid,
                    alter_id=alter_id,
                    master_id=master_id,
                    voucher_number=v_data["voucher_number"],
                    voucher_date=v_date,
                    voucher_type=v_data.get("voucher_type", "Sales"),
                    party_name=v_data["party_name"],
                    party_ledger_name=v_data.get("party_ledger_name"),
                    buyer_name=v_data.get("buyer_name"),
                    address=v_data.get("address"),
                    state_name=v_data.get("state_name"),
                    company_name=company_name or v_data.get("company_name"),
                    is_cancelled=False,
                    is_deleted=False,
                    is_processed=False,
                    notes=v_data.get("notes"),
                    raw_metadata=v_data.get("raw_metadata"),
                )

                for itm in v_data.get("items", []):
                    clean_brand, clean_model = extract_clean_brand_and_model(itm["item_name"])
                    item_name_clean = itm["item_name"].strip().lower()
                    clean_model_lower = clean_model.strip().lower()

                    matched_prod_id = (
                        prod_lookup_by_name.get(item_name_clean)
                        or prod_lookup_by_model.get(item_name_clean)
                        or prod_lookup_by_model.get(clean_model_lower)
                        or prod_lookup_by_name.get(clean_model_lower)
                    )

                    if not matched_prod_id:
                        target_cat = None
                        brand_upper = clean_brand.upper()
                        if is_tally_2 and f"{brand_upper.lower()} (tally 2)" in cat_map:
                            target_cat = cat_map[f"{brand_upper.lower()} (tally 2)"]
                        elif brand_upper.lower() in cat_map:
                            target_cat = cat_map[brand_upper.lower()]

                        if not target_cat:
                            target_cat = default_cat

                        auto_p = Product(
                            name=itm["item_name"].strip(),
                            brand=clean_brand,
                            model=clean_model,
                            category_id=target_cat.id,
                            unit=itm.get("uom") or "piece",
                            serial_number_required=True,
                            is_active=True,
                            source="TALLY",
                        )
                        db.add(auto_p)
                        await db.flush()
                        matched_prod_id = auto_p.id
                        prod_lookup_by_name[item_name_clean] = matched_prod_id
                        prod_lookup_by_model[clean_model_lower] = matched_prod_id
                        prod_by_id[matched_prod_id] = auto_p

                    new_itm = TallyVoucherItem(
                        item_name=itm["item_name"],
                        item_code=itm.get("item_code"),
                        product_id=matched_prod_id,
                        quantity=itm["quantity"],
                        uom=itm.get("uom"),
                        raw_qty_text=itm.get("raw_qty_text"),
                        godown_name=itm.get("godown_name"),
                        batch_name=itm.get("batch_name"),
                        batch_details=itm.get("batch_details"),
                    )
                    new_vch.items.append(new_itm)

                db.add(new_vch)
                created += 1
                new_vouchers_to_broadcast.append((new_vch, str(shop.id) if shop else None))

        await db.commit()

        # Real-time WebSocket broadcast for newly detected vouchers so mobile scanners react instantly
        for vch, shop_id_str in new_vouchers_to_broadcast:
            try:
                vch_payload = {
                    "id": str(vch.id),
                    "guid": vch.guid,
                    "voucher_number": vch.voucher_number,
                    "voucher_date": vch.voucher_date.isoformat(),
                    "voucher_type": vch.voucher_type,
                    "party_name": vch.party_name,
                    "party_ledger_name": vch.party_ledger_name,
                    "buyer_name": vch.buyer_name,
                    "address": vch.address,
                    "state_name": vch.state_name,
                    "company_name": vch.company_name,
                    "shop_id": shop_id_str,
                    "vehicle_number": vch.vehicle_number,
                    "transporter_name": vch.transporter_name,
                    "delivery_note": vch.delivery_note,
                    "destination": vch.destination,
                    "is_cancelled": vch.is_cancelled,
                    "is_deleted": vch.is_deleted,
                    "is_processed": vch.is_processed,
                    "item_count": len(vch.items),
                    "total_quantity": sum(i.quantity for i in vch.items),
                    "godowns": list({i.godown_name for i in vch.items if i.godown_name}),
                    "items": [
                        {
                            "id": str(i.id),
                            "voucher_id": str(vch.id),
                            "item_name": i.item_name,
                            "item_code": i.item_code,
                            "product_id": str(i.product_id) if i.product_id else None,
                            "quantity": i.quantity,
                            "uom": i.uom,
                            "raw_qty_text": i.raw_qty_text,
                            "godown_name": i.godown_name,
                            "batch_name": i.batch_name,
                            "matched_product_name": prod_by_id[i.product_id].name if i.product_id in prod_by_id else None,
                            "matched_product_model": prod_by_id[i.product_id].model if i.product_id in prod_by_id else None,
                        }
                        for i in vch.items
                    ],
                }
                await ws_manager.broadcast("tally_bill_created", vch_payload)
                logger.info(f"[TallySync] Broadcasted tally_bill_created for '{vch.voucher_number}' ({vch.party_name})")
            except Exception as b_ex:
                logger.debug(f"[TallySync] WebSocket broadcast error: {b_ex}")

        return created, updated, cancelled

    @classmethod
    async def sync_stock_quantities_from_tally(
        cls,
        db: AsyncSession,
        company_name: Optional[str] = None,
    ) -> int:
        """
        Lightweight sync that fetches ONLY item stock balances from Tally (~0.1s per host)
        and updates Product.tally_stock_qty without pulling categories, items, or ledgers.
        """
        cfg = await cls.get_or_create_config(db)
        endpoints = cls.get_configured_endpoints(cfg)

        now_ts = time.time()
        if cls._cached_probe_results is not None and (now_ts - cls._cached_probe_at) < cls._PROBE_CACHE_TTL_SEC:
            probes = cls._cached_probe_results
        else:
            probes = await TallyHttpClient.probe_endpoints(endpoints, timeout=3.0)
            cls._cached_probe_results = probes
            cls._cached_probe_at = now_ts
            cls._log_probe_statuses(probes)

        reachable = [p for p in probes if p[3]]
        if not reachable:
            return 0

        merged_stock_map: Dict[str, int] = {}
        any_company_succeeded = False

        for ep_host, ep_port, ep_url, _, _, ep_companies in reachable:
            base_url = TallyHttpClient.get_url(ep_host, ep_port, ep_url)
            if time.time() < cls._endpoint_cooldown_until.get(base_url, 0.0):
                continue

            open_names = [
                c["name"].strip()
                for c in ep_companies
                if c.get("name") and c["name"].strip() != "0" and not c["name"].strip().isdigit()
            ]
            if company_name:
                if open_names and company_name not in open_names:
                    continue
                target_companies: List[Optional[str]] = [company_name]
            elif open_names:
                target_companies = list(dict.fromkeys(open_names))
            else:
                target_companies = [cfg.company_name]

            for comp in target_companies:
                try:
                    req_sum = TallyXmlBuilder.build_stock_summary_request(company_name=comp)
                    resp_sum = await TallyHttpClient.post_xml(ep_host, ep_port, req_sum, ep_url, timeout=15.0)
                    if resp_sum:
                        comp_map = TallyXmlParser.parse_stock_summary(resp_sum)
                        any_company_succeeded = True
                        for k, q in comp_map.items():
                            merged_stock_map[k] = merged_stock_map.get(k, 0) + q
                except Exception as e:
                    cls._endpoint_cooldown_until[base_url] = time.time() + cls._ENDPOINT_ERROR_COOLDOWN_SEC
                    logger.debug(f"[TallySync] Stock qty poll skipped on {base_url} ({comp}): {e}")
                    break

        if not any_company_succeeded:
            return 0

        all_prods = (await db.execute(select(Product))).scalars().all()
        updated_count = 0
        for p in all_prods:
            p_norm = " ".join(p.name.split()).lower()
            m_norm = " ".join(p.model.split()).lower() if p.model else ""
            t_qty = merged_stock_map.get(p_norm)
            if t_qty is None and m_norm:
                t_qty = merged_stock_map.get(m_norm)

            if t_qty is not None:
                if p.tally_stock_qty != t_qty:
                    p.tally_stock_qty = t_qty
                    updated_count += 1
            elif p.source == "TALLY" and p.tally_guid and p.tally_stock_qty != 0:
                p.tally_stock_qty = 0
                updated_count += 1

        if updated_count > 0:
            await db.commit()

        return updated_count

    @classmethod
    async def sync_masters_from_tally(
        cls,
        db: AsyncSession,
        company_name: Optional[str] = None,
        target_host: Optional[str] = None,
        target_port: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        Syncs Stock Groups as Categories, Stock Items as Products, and Ledgers as Shops from Tally.
        Supports multiple Tally PCs configured in TALLY_HOSTS as well as explicit target_host.
        STRICTLY NON-FINANCIAL (no rates, prices, costs, or values).
        """
        cfg = await cls.get_or_create_config(db)

        if target_host:
            return await cls._sync_masters_single(
                db=db,
                cfg=cfg,
                sync_host=target_host,
                sync_port=target_port or cfg.port,
                sync_url=None,
                active_company=company_name,
            )

        endpoints = cls.get_configured_endpoints(cfg)
        probes = await TallyHttpClient.probe_endpoints(endpoints, timeout=3.0)
        reachable = [p for p in probes if p[3]]
        if not reachable:
            tried = ", ".join(TallyHttpClient.get_url(h, p, u) for h, p, u in endpoints)
            raise RuntimeError(f"All connection attempts failed (tried: {tried})")

        agg = {
            "status": "SUCCESS",
            "categories_created": 0,
            "categories_updated": 0,
            "products_created": 0,
            "products_updated": 0,
            "tally_stock_synced": 0,
            "shops_created": 0,
            "shops_updated": 0,
            "gstins_cross_filled": 0,
        }

        for ep_host, ep_port, ep_url, _, _, ep_companies in reachable:
            open_names = [
                c["name"]
                for c in ep_companies
                if c.get("name") and c["name"].strip() != "0" and not c["name"].strip().isdigit()
            ]
            if company_name:
                if open_names and company_name not in open_names:
                    continue
                target_companies: List[Optional[str]] = [company_name]
            elif open_names:
                target_companies = list(dict.fromkeys(open_names))
            else:
                target_companies = [cfg.company_name]

            for comp in target_companies:
                res = await cls._sync_masters_single(
                    db=db,
                    cfg=cfg,
                    sync_host=ep_host,
                    sync_port=ep_port,
                    sync_url=ep_url,
                    active_company=comp,
                    run_cross_fill=False,
                )
                for k in (
                    "categories_created",
                    "categories_updated",
                    "products_created",
                    "products_updated",
                    "tally_stock_synced",
                    "shops_created",
                    "shops_updated",
                ):
                    agg[k] += int(res.get(k, 0))

        agg["gstins_cross_filled"] = await cls.auto_fill_brand_gstins(db)
        return agg

    @classmethod
    async def _sync_masters_single(
        cls,
        db: AsyncSession,
        cfg: TallyConfig,
        sync_host: str,
        sync_port: int,
        sync_url: Optional[str],
        active_company: Optional[str] = None,
        run_cross_fill: bool = True,
    ) -> Dict[str, Any]:
        """Single-endpoint / single-company master sync helper."""
        is_tally_2 = bool(active_company and ("2025-26" in active_company or "tally 2" in active_company.lower()))

        categories_created = 0
        categories_updated = 0
        products_created = 0
        products_updated = 0

        # Ensure default category exists
        def_res = await db.execute(select(Category).where(func.lower(Category.name) == "general"))
        default_cat = def_res.scalar_one_or_none()
        if not default_cat:
            default_cat = Category(name="General", has_dual_serial=False, is_active=True, source="TALLY")
            db.add(default_cat)
            await db.flush()

        # 1. Fetch & Sync Stock Groups (Categories)
        try:
            req_sg = TallyXmlBuilder.build_stock_groups_request(company_name=active_company)
            resp_sg = await TallyHttpClient.post_xml(sync_host, sync_port, req_sg, sync_url, timeout=15.0)
            if resp_sg:
                stock_groups = TallyXmlParser.parse_stock_groups(resp_sg)
                for sg in stock_groups:
                    name_clean = sg["name"].strip()
                    sg_guid = sg.get("guid")

                    # 1. Match by guid first
                    existing_c = None
                    if sg_guid:
                        c_by_guid = await db.execute(select(Category).where(Category.tally_guid == sg_guid))
                        existing_c = c_by_guid.scalar_one_or_none()

                    # 2. If not matched by guid, determine target name and match
                    target_name = name_clean
                    if not existing_c:
                        if is_tally_2:
                            # If company is Tally 2, keep colliding names separate (e.g. AC, General, REFRIGERATOR)
                            c_plain = (await db.execute(
                                select(Category).where(func.lower(Category.name) == func.lower(name_clean))
                            )).scalar_one_or_none()
                            if c_plain and (c_plain.tally_guid != sg_guid or name_clean.upper() in ("AC", "GENERAL", "REFRIGERATOR")):
                                target_name = f"{name_clean} (Tally 2)"

                        c_by_name = await db.execute(
                            select(Category).where(func.lower(Category.name) == func.lower(target_name))
                        )
                        existing_c = c_by_name.scalar_one_or_none()

                    is_dual = any(kw in target_name.lower() for kw in ("ac", "air conditioner", "split"))
                    if existing_c:
                        if sg_guid:
                            existing_c.tally_guid = sg_guid
                        if sg.get("parent"):
                            existing_c.tally_parent_group = sg["parent"]
                        existing_c.source = "TALLY"
                        categories_updated += 1
                    else:
                        new_c = Category(
                            name=target_name,
                            has_dual_serial=is_dual,
                            is_active=True,
                            tally_guid=sg_guid,
                            tally_parent_group=sg.get("parent"),
                            source="TALLY",
                        )
                        db.add(new_c)
                        categories_created += 1
                await db.flush()
        except Exception as e:
            logger.debug(f"[TallySync] Stock Groups fetch skipped/failed: {e}")

        # Refresh map of categories
        all_cats = (await db.execute(select(Category))).scalars().all()
        cat_map = {c.name.strip().lower(): c for c in all_cats}

        # Select appropriate default category for this company
        if is_tally_2 and "general (tally 2)" in cat_map:
            active_default_cat = cat_map["general (tally 2)"]
        else:
            active_default_cat = default_cat

        # 2. Fetch & Sync Stock Items (Products)
        try:
            req_si = TallyXmlBuilder.build_stock_items_request(company_name=active_company)
            resp_si = await TallyHttpClient.post_xml(sync_host, sync_port, req_si, sync_url, timeout=45.0)
            if resp_si:
                stock_items = TallyXmlParser.parse_stock_items(resp_si)
                for si in stock_items:
                    item_name = si["name"].strip()
                    parent_group = si.get("parent_group")
                    matched_cat = None
                    if parent_group:
                        pg_clean = parent_group.strip().lower()
                        if is_tally_2:
                            # Try Tally 2 specific category first (e.g. 'ac (tally 2)', 'general (tally 2)', 'refrigerator (tally 2)')
                            matched_cat = cat_map.get(f"{pg_clean} (tally 2)")
                        if not matched_cat:
                            matched_cat = cat_map.get(pg_clean)
                    if not matched_cat:
                        matched_cat = active_default_cat

                    brand, model_code = extract_clean_brand_and_model(item_name, parent_group)
                    if si.get("part_number"):
                        model_code = si["part_number"].strip()

                    p_res = await db.execute(
                        select(Product).where(
                            or_(
                                (Product.tally_guid == si["guid"]) if si.get("guid") else False,
                                func.lower(Product.name) == func.lower(item_name),
                                func.lower(Product.model) == func.lower(model_code),
                            )
                        )
                    )
                    existing_p = p_res.scalars().first()
                    if existing_p:
                        existing_p.name = item_name
                        existing_p.brand = brand
                        existing_p.model = model_code
                        # Never reassign category if existing product already has serial numbers
                        has_serials = (await db.execute(
                            select(func.count(SerialNumber.id)).where(SerialNumber.product_id == existing_p.id)
                        )).scalar() or 0
                        if has_serials == 0:
                            existing_p.category_id = matched_cat.id

                        if si.get("guid"):
                            existing_p.tally_guid = si["guid"]
                        if si.get("part_number"):
                            existing_p.tally_part_number = si["part_number"]
                        existing_p.source = "TALLY"
                        products_updated += 1
                    else:
                        new_p = Product(
                            name=item_name,
                            brand=brand,
                            model=model_code,
                            category_id=matched_cat.id,
                            unit=si.get("unit") or "piece",
                            serial_number_required=True,
                            description=si.get("description"),
                            is_active=True,
                            tally_guid=si.get("guid"),
                            tally_part_number=si.get("part_number"),
                            source="TALLY",
                        )
                        db.add(new_p)
                        products_created += 1

                await db.commit()
        except Exception as e:
            logger.debug(f"[TallySync] Stock Items fetch skipped/failed: {e}")

        # 2b. Fetch & Sync Stock Summary (Tally Stock Quantities per Model)
        tally_stock_synced = 0
        try:
            req_sum = TallyXmlBuilder.build_stock_summary_request(company_name=active_company)
            resp_sum = await TallyHttpClient.post_xml(sync_host, sync_port, req_sum, sync_url, timeout=20.0)
            if resp_sum:
                stock_summary_map = TallyXmlParser.parse_stock_summary(resp_sum)
                if stock_summary_map:
                    all_prods = (await db.execute(select(Product))).scalars().all()
                    for p in all_prods:
                        p_norm = " ".join(p.name.split()).lower()
                        m_norm = " ".join(p.model.split()).lower() if p.model else ""
                        t_qty = stock_summary_map.get(p_norm)
                        if t_qty is None and m_norm:
                            t_qty = stock_summary_map.get(m_norm)

                        if t_qty is not None:
                            p.tally_stock_qty = t_qty
                            tally_stock_synced += 1
                        elif p.source == "TALLY" and p.tally_guid:
                            p.tally_stock_qty = 0
                            tally_stock_synced += 1
                    await db.commit()
        except Exception as e:
            logger.debug(f"[TallySync] Stock Summary fetch skipped/failed: {e}")

        # 3. Fetch & Sync Ledgers (Shops / Sundry Debtors)
        shops_created = 0
        shops_updated = 0
        try:
            req_l = TallyXmlBuilder.build_ledgers_request(company_name=active_company)
            resp_l = await TallyHttpClient.post_xml(sync_host, sync_port, req_l, sync_url, timeout=20.0)
            if resp_l:
                ledgers = TallyXmlParser.parse_ledgers(resp_l)
                for led in ledgers:
                    led_name = led["name"].strip()
                    parent_grp = (led.get("parent") or "").lower()
                    # Skip explicit non-debtor accounting groups if an un-filtered XML report was parsed
                    non_debtor_groups = {
                        "bank accounts", "bank od a/c", "cash-in-hand", "duties & taxes",
                        "sales accounts", "purchase accounts", "direct expenses", "indirect expenses",
                        "direct incomes", "indirect incomes", "sundry creditors", "loans (liability)",
                        "fixed assets", "capital account", "current liabilities", "provisions",
                        "stock-in-hand", "investments", "suspense a/c", "reserves & surplus",
                    }
                    if parent_grp in non_debtor_groups:
                        continue

                    s_res = await db.execute(
                        select(Shop).where(
                            (func.lower(Shop.name) == func.lower(led_name))
                            | (Shop.tally_guid == led["guid"] if led.get("guid") else False)
                        )
                    )
                    existing_s = s_res.scalar_one_or_none()
                    if existing_s:
                        if led.get("guid"):
                            existing_s.tally_guid = led["guid"]
                        if led.get("gstin"):
                            existing_s.gstin = led["gstin"]
                        if led.get("address"):
                            existing_s.address = led["address"]
                        if led.get("state"):
                            existing_s.state = led["state"]
                        if led.get("pincode"):
                            existing_s.pincode = led["pincode"]
                        if led.get("phone"):
                            existing_s.phone = led["phone"]
                        if led.get("contact_person"):
                            existing_s.contact_person = led["contact_person"]
                        if led.get("email"):
                            existing_s.email = led["email"]
                        existing_s.source = "TALLY"
                        shops_updated += 1
                    else:
                        new_s = Shop(
                            name=led_name,
                            city=led.get("state") or "Local",
                            phone=led.get("phone"),
                            gstin=led.get("gstin"),
                            address=led.get("address"),
                            state=led.get("state"),
                            pincode=led.get("pincode"),
                            contact_person=led.get("contact_person"),
                            email=led.get("email"),
                            tally_guid=led.get("guid"),
                            source="TALLY",
                            is_active=True,
                        )
                        db.add(new_s)
                        shops_created += 1
                await db.commit()
        except Exception as e:
            logger.debug(f"[TallySync] Ledgers fetch skipped/failed: {e}")

        # Cross-fill GSTINs across brand-differentiated shops
        inherited_gstins = await cls.auto_fill_brand_gstins(db) if run_cross_fill else 0

        return {
            "status": "SUCCESS",
            "categories_created": categories_created,
            "categories_updated": categories_updated,
            "products_created": products_created,
            "products_updated": products_updated,
            "tally_stock_synced": tally_stock_synced,
            "shops_created": shops_created,
            "shops_updated": shops_updated,
            "gstins_cross_filled": inherited_gstins,
        }

    @classmethod
    async def auto_fill_brand_gstins(cls, db: AsyncSession) -> int:
        """
        Cross-fills missing GSTINs across brand-differentiated shops.
        E.g., if 'ABC ENTERPRISES (DAIKIN)' has a GSTIN, 'ABC ENTERPRISES - VOLTAS'
        will automatically inherit that GSTIN.
        """
        all_shops_res = await db.execute(select(Shop).where(Shop.is_active == True))
        all_shops = all_shops_res.scalars().all()

        root_gstin_map: Dict[str, str] = {}
        phone_gstin_map: Dict[str, str] = {}

        for s in all_shops:
            if s.gstin:
                g_extracted = extract_gstin(s.gstin)
                if g_extracted:
                    root = get_shop_root_name(s.name).lower()
                    if root and root not in root_gstin_map:
                        root_gstin_map[root] = g_extracted
                    if s.phone and len(s.phone.strip()) >= 8 and s.phone.strip() not in phone_gstin_map:
                        phone_gstin_map[s.phone.strip()] = g_extracted

        # Also inspect historical sales vouchers raw_metadata
        vch_res = await db.execute(
            select(TallySalesVoucher.party_name, TallySalesVoucher.raw_metadata).where(
                TallySalesVoucher.raw_metadata.is_not(None)
            )
        )
        for p_name, meta in vch_res.all():
            if isinstance(meta, dict) and p_name:
                v_g = extract_gstin(meta.get("party_gstin")) or extract_gstin(meta.get("buyer_gstin"))
                if v_g:
                    root = get_shop_root_name(p_name).lower()
                    if root and root not in root_gstin_map:
                        root_gstin_map[root] = v_g

        updated_count = 0
        for s in all_shops:
            if not s.gstin or not extract_gstin(s.gstin):
                root = get_shop_root_name(s.name).lower()
                matched_gst = root_gstin_map.get(root)
                if not matched_gst and s.phone:
                    matched_gst = phone_gstin_map.get(s.phone.strip())

                if matched_gst and matched_gst != s.gstin:
                    s.gstin = matched_gst
                    updated_count += 1
                    logger.info(f"[TallySync] Auto-filled GSTIN {matched_gst} for shop '{s.name}' from related brand shop '{root}'.")

        if updated_count > 0:
            await db.commit()
            try:
                await ws_manager.broadcast("shop_updated", {"bulk": True, "count": updated_count})
            except Exception:
                pass
            logger.info(f"[TallySync] Cross-filled GSTIN for {updated_count} brand-separated shop(s).")

        return updated_count

    @classmethod
    async def perform_sync(
        cls,
        db: AsyncSession,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
        company_name: Optional[str] = None,
        force_full: bool = False,
        source: str = "DIRECT_HTTP",
        record_empty_history: bool = True,
    ) -> Optional[TallySyncHistory]:
        """
        Executes a synchronization run against all configured/reachable Tally HTTP endpoints.
        Extracts sales bills, stores non-financial vouchers, and updates sync state.
        """
        cfg = await cls.get_or_create_config(db)
        active_company = company_name or cfg.company_name
        if active_company and (active_company.strip() == "0" or active_company.strip().isdigit()):
            active_company = None

        endpoints = cls.get_configured_endpoints(cfg)
        cls._load_alter_cache()
        now_ts = time.time()
        use_cached_probe = (
            not record_empty_history
            and not force_full
            and cls._cached_probe_results is not None
            and (now_ts - cls._cached_probe_at) < cls._PROBE_CACHE_TTL_SEC
        )
        if use_cached_probe:
            probe_results = cls._cached_probe_results
        else:
            probe_results = await TallyHttpClient.probe_endpoints(endpoints, timeout=3.0)
            cls._cached_probe_results = probe_results
            cls._cached_probe_at = now_ts
            cls._log_probe_statuses(probe_results, force_log=record_empty_history)
        reachable = [p for p in probe_results if p[3]]

        all_open_names: List[str] = []
        for _, _, _, _, _, ep_companies in reachable:
            for c in ep_companies:
                cname = (c.get("name") or "").strip()
                if cname and cname != "0" and not cname.isdigit() and cname not in all_open_names:
                    all_open_names.append(cname)

        if not company_name and all_open_names and (not active_company or active_company not in all_open_names):
            active_company = all_open_names[0]
            cfg.company_name = active_company
            await db.commit()
            logger.info(f"[TallySync] Updated active company to open Tally company: '{active_company}'")

        start_time = time.time()
        history: Optional[TallySyncHistory] = None
        if record_empty_history:
            history = TallySyncHistory(
                sync_source=source,
                company_name=active_company,
                status="IN_PROGRESS",
                started_at=datetime.now(),
                from_date=from_date.isoformat() if from_date else None,
                to_date=to_date.isoformat() if to_date else None,
                last_alter_id=None if force_full else cfg.last_alter_id,
            )
            db.add(history)
            await db.commit()
            await db.refresh(history)

        if not reachable:
            tried = ", ".join(TallyHttpClient.get_url(h, p, u) for h, p, u in endpoints)
            err_msg = f"All connection attempts failed (tried: {tried})"
            if record_empty_history:
                logger.error(f"[TallySync] Failed: {err_msg}")
            else:
                logger.debug(f"[TallySync] Tick connect status: {err_msg}")

            cfg.last_sync_status = "FAILED"
            cfg.last_sync_message = err_msg
            if history:
                history.status = "FAILED"
                history.completed_at = datetime.now()
                history.error_message = err_msg
                await db.commit()
                await db.refresh(history)
                return history
            await db.commit()
            return None

        try:
            fetched_count = 0
            created = 0
            updated = 0
            cancelled = 0
            is_single_target = len(reachable) == 1 and len(all_open_names) <= 1

            today = date.today()
            fy_start_year = today.year if today.month >= 4 else today.year - 1
            fy_start_date = date(fy_start_year, 4, 1)
            eff_to_date = to_date or today

            # Check if DB already has synced vouchers so background cold-start doesn't dump the full FY (~25MB)
            existing_vch_count = 0
            if not force_full and from_date is None and not record_empty_history:
                existing_vch_count = (await db.execute(select(func.count(TallySalesVoucher.id)))).scalar() or 0
            # Keep background cold-start fallback strictly to today so turning on server stays ~0.1s per host
            default_from_date = today if (existing_vch_count > 0 and not force_full and not record_empty_history) else fy_start_date

            alter_cache_dirty = False
            for ep_host, ep_port, ep_url, _, _, ep_companies in reachable:
                base_url = TallyHttpClient.get_url(ep_host, ep_port, ep_url)
                if not record_empty_history and not force_full:
                    cooldown_until = cls._endpoint_cooldown_until.get(base_url, 0.0)
                    if time.time() < cooldown_until:
                        continue

                ep_open = [
                    c["name"].strip()
                    for c in ep_companies
                    if c.get("name") and c["name"].strip() != "0" and not c["name"].strip().isdigit()
                ]
                if company_name:
                    if ep_open and company_name not in ep_open:
                        continue
                    target_companies: List[Optional[str]] = [company_name]
                elif ep_open:
                    target_companies = list(dict.fromkeys(ep_open))
                else:
                    target_companies = [active_company]

                for comp in target_companies:
                    alter_key = f"{base_url}|{comp or ''}"
                    if force_full or from_date is not None:
                        alter_id = None
                    elif alter_key in cls._endpoint_alter_ids:
                        alter_id = cls._endpoint_alter_ids[alter_key] or None
                    elif is_single_target and cfg.last_alter_id > 0:
                        alter_id = cfg.last_alter_id
                    else:
                        alter_id = None

                    # On steady background ticks, Tally's date-indexed Day Book for today (~0.09s) is up to
                    # 9x faster than full-company Collection scanning (~0.8-0.97s). Sweep full AlterID every 120s
                    # (skipping immediate boot sweep when alter_id is already cached so server startup never lags Tally).
                    tick_now = time.time()
                    if (
                        not record_empty_history
                        and not force_full
                        and from_date is None
                        and alter_id
                        and alter_key not in cls._last_full_alter_poll_at
                    ):
                        cls._last_full_alter_poll_at[alter_key] = tick_now

                    use_fast_today_daybook = (
                        not record_empty_history
                        and not force_full
                        and from_date is None
                        and alter_id is not None
                        and (tick_now - cls._last_full_alter_poll_at.get(alter_key, 0.0)) < cls._FULL_ALTER_SWEEP_SEC
                    )

                    eff_from_date = from_date or (None if alter_id else default_from_date)

                    if use_fast_today_daybook:
                        req_xml = TallyXmlBuilder.build_fallback_voucher_register_request(
                            company_name=comp,
                            from_date=today,
                            to_date=eff_to_date,
                        )
                    else:
                        req_xml = TallyXmlBuilder.build_sales_vouchers_request(
                            company_name=comp,
                            from_date=eff_from_date,
                            to_date=eff_to_date,
                            alter_id=alter_id,
                        )
                    try:
                        resp_xml = await TallyHttpClient.post_xml(
                            ep_host, ep_port, req_xml, ep_url, timeout=45.0
                        )
                        if not use_fast_today_daybook and not record_empty_history:
                            cls._last_full_alter_poll_at[alter_key] = time.time()
                    except Exception as e:
                        if use_fast_today_daybook:
                            cls._endpoint_cooldown_until[base_url] = time.time() + cls._ENDPOINT_ERROR_COOLDOWN_SEC
                            cls._cached_probe_at = 0.0
                            logger.warning(f"[TallySync] Skipping {base_url} ({comp}) for {int(cls._ENDPOINT_ERROR_COOLDOWN_SEC)}s after Day Book poll error: {e}")
                            break
                        logger.warning(f"TDL collection query failed on {base_url} ({comp}), trying Day Book fallback: {e}")
                        try:
                            fb_xml = TallyXmlBuilder.build_fallback_voucher_register_request(
                                company_name=comp,
                                from_date=eff_from_date or default_from_date,
                                to_date=eff_to_date,
                            )
                            resp_xml = await TallyHttpClient.post_xml(
                                ep_host, ep_port, fb_xml, ep_url, timeout=30.0
                            )
                        except Exception as fb_err:
                            # Put failing endpoint on short cooldown & force re-probe next time without stalling other hosts
                            cls._endpoint_cooldown_until[base_url] = time.time() + cls._ENDPOINT_ERROR_COOLDOWN_SEC
                            cls._cached_probe_at = 0.0
                            if record_empty_history:
                                raise
                            logger.warning(f"[TallySync] Skipping {base_url} ({comp}) for {int(cls._ENDPOINT_ERROR_COOLDOWN_SEC)}s after error: {fb_err}")
                            break

                    parsed_vouchers = TallyXmlParser.parse_sales_vouchers(resp_xml, default_company=comp)
                    if not active_company:
                        detected_comps = TallyXmlParser.parse_companies(resp_xml)
                        if detected_comps:
                            active_company = detected_comps[0].get("name")
                            cfg.company_name = active_company
                            if history:
                                history.company_name = active_company

                    ep_max_alter = max(
                        [v["alter_id"] for v in parsed_vouchers if v.get("alter_id") is not None],
                        default=cls._endpoint_alter_ids.get(alter_key, 0),
                    )
                    if use_fast_today_daybook and alter_id:
                        parsed_vouchers = [
                            v for v in parsed_vouchers
                            if v.get("alter_id") is None or v["alter_id"] > alter_id
                        ]

                    fetched_count += len(parsed_vouchers)
                    if parsed_vouchers:
                        c_new, c_upd, c_can = await cls.process_vouchers(
                            db, parsed_vouchers, company_name=comp
                        )
                        created += c_new
                        updated += c_upd
                        cancelled += c_can

                    if ep_max_alter:
                        prev_alter = cls._endpoint_alter_ids.get(alter_key, 0)
                        if ep_max_alter > prev_alter:
                            cls._endpoint_alter_ids[alter_key] = ep_max_alter
                            alter_cache_dirty = True
                        if ep_max_alter > cfg.last_alter_id:
                            cfg.last_alter_id = ep_max_alter

            if alter_cache_dirty:
                cls._save_alter_cache()

            cfg.last_sync_at = datetime.now()
            cfg.last_sync_status = "SUCCESS"
            cfg.last_sync_message = f"Synced {fetched_count} vouchers ({created} new, {updated} updated, {cancelled} cancelled)."

            if record_empty_history or created > 0 or updated > 0 or cancelled > 0:
                if not history:
                    history = TallySyncHistory(
                        sync_source=source,
                        company_name=active_company,
                        status="SUCCESS",
                        started_at=datetime.fromtimestamp(start_time),
                        from_date=from_date.isoformat() if from_date else None,
                        to_date=eff_to_date.isoformat() if eff_to_date else None,
                        last_alter_id=cfg.last_alter_id,
                    )
                    db.add(history)
                history.status = "SUCCESS"
                history.completed_at = datetime.now()
                history.vouchers_fetched = fetched_count
                history.vouchers_created = created
                history.vouchers_updated = updated
                history.vouchers_cancelled = cancelled
                history.last_alter_id = cfg.last_alter_id

            await db.commit()
            if history:
                await db.refresh(history)

            if created > 0 or updated > 0 or cancelled > 0 or record_empty_history:
                logger.info(
                    f"[TallySync] Complete in {time.time()-start_time:.2f}s across {len(reachable)} host(s): "
                    f"{fetched_count} fetched, {created} created, {updated} updated, {cancelled} cancelled."
                )
            return history

        except Exception as ex:
            err_msg = str(ex)
            if record_empty_history or "ConnectError" not in err_msg:
                logger.error(f"[TallySync] Failed: {err_msg}")
            else:
                logger.debug(f"[TallySync] Tick connect status: {err_msg}")

            cfg.last_sync_status = "FAILED"
            cfg.last_sync_message = err_msg

            if record_empty_history:
                if not history:
                    history = TallySyncHistory(
                        sync_source=source,
                        company_name=active_company,
                        status="FAILED",
                        started_at=datetime.fromtimestamp(start_time),
                    )
                    db.add(history)
                history.status = "FAILED"
                history.completed_at = datetime.now()
                history.error_message = err_msg
                await db.commit()
                await db.refresh(history)
                return history
            else:
                await db.commit()
                return None


# ---------------------------------------------------------------------------
# Background Periodic Sync Worker
# ---------------------------------------------------------------------------

class TallyBackgroundWorker:
    _instance: Optional["TallyBackgroundWorker"] = None
    _lock: asyncio.Lock = asyncio.Lock()
    _is_running: bool = False
    _task: Optional[asyncio.Task] = None

    def __init__(self):
        self._is_syncing = False

    @classmethod
    def get_instance(cls) -> "TallyBackgroundWorker":
        if cls._instance is None:
            cls._instance = TallyBackgroundWorker()
        return cls._instance

    @property
    def is_syncing(self) -> bool:
        return self._is_syncing

    def start(self):
        if self._is_running:
            return
        self._is_running = True
        self._task = asyncio.create_task(self._worker_loop())
        logger.info("[TallyWorker] Background sync worker started.")

    def stop(self):
        self._is_running = False
        if self._task and not self._task.done():
            self._task.cancel()
        logger.info("[TallyWorker] Background sync worker stopped.")

    async def _worker_loop(self):
        # Wait 5 seconds after server startup so FastAPI/DB initialization settles before first Tally poll
        await asyncio.sleep(5)
        logger.info("[TallyWorker] Polling Tally hosts (bills & stock quantities only; masters are button-triggered)...")
        while self._is_running:
            try:
                async with AsyncSessionLocal() as session:
                    cfg = await TallySyncService.get_or_create_config(session)
                    interval_sec = max(getattr(settings, "tally_sync_interval_seconds", 10) or 10, 10)

                    if cfg.is_enabled and cfg.auto_sync:
                        async with self._lock:
                            self._is_syncing = True
                            try:
                                # 1. Fetch generated bills (~0.07-0.25s via Day Book today + 2m AlterID sweep)
                                await TallySyncService.perform_sync(
                                    session,
                                    source="DIRECT_HTTP",
                                    record_empty_history=False,
                                )

                                # 2. Fetch ONLY live stock quantities (~0.1s NonZero StockBalance collection)
                                await TallySyncService.sync_stock_quantities_from_tally(session)
                            except Exception as e:
                                logger.debug(f"[TallyWorker] Background sync tick: {e}")
                            finally:
                                self._is_syncing = False
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"[TallyWorker] Error in background sync loop: {e}")
                interval_sec = 4

            try:
                await asyncio.sleep(max(1, interval_sec))
            except asyncio.CancelledError:
                break

    async def run_manual_masters_sync(
        self,
        company_name: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Manually pulls Stock Groups (Categories), Stock Items (Products), Shops (Ledgers) & Stock Qty."""
        if self._lock.locked():
            raise RuntimeError("A Tally synchronization job is already running. Please wait for it to complete.")

        async with self._lock:
            self._is_syncing = True
            try:
                async with AsyncSessionLocal() as session:
                    return await TallySyncService.sync_masters_from_tally(
                        session,
                        company_name=company_name,
                    )
            finally:
                self._is_syncing = False

    async def run_manual_sync(
        self,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
        company_name: Optional[str] = None,
        force_full: bool = False,
    ) -> TallySyncHistory:
        """Triggers an immediate sync safely without overlapping."""
        if self._lock.locked():
            raise RuntimeError("A Tally synchronization job is already running. Please wait for it to complete.")

        async with self._lock:
            self._is_syncing = True
            try:
                async with AsyncSessionLocal() as session:
                    history = await TallySyncService.perform_sync(
                        session,
                        from_date=from_date,
                        to_date=to_date,
                        company_name=company_name,
                        force_full=force_full,
                        source="MANUAL",
                    )
                    return history
            finally:
                self._is_syncing = False
