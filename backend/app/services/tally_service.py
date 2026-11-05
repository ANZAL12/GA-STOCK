import asyncio
import logging
import re
import secrets
import time
import uuid
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

import httpx
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import AsyncSessionLocal
from app.config import settings
from app.core.websocket_manager import ws_manager
from app.models.product import Product
from app.models.shop import Shop
from app.models.tally import (
    TallyConfig,
    TallySalesVoucher,
    TallySyncHistory,
    TallyVoucherItem,
)

logger = logging.getLogger("tally_service")


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
    (like &#4; in CSTFORMISSUETYPE) and unprintable control characters that
    cause standard XML parsers to fail.
    """
    if not xml_content:
        return ""
    # Strip illegal XML entity references &#0; through &#8;, &#11;, &#12;, &#14; through &#31;
    s = re.sub(r'&#(?:[0-8]|1[1-2]|1[4-9]|[2-3][0-9]);', '', xml_content)
    # Strip raw control characters except tab, newline, and carriage return
    s = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', s)
    return s


def clean_xml_text(elem: Optional[ET.Element]) -> str:
    if elem is None or elem.text is None:
        return ""
    return elem.text.strip()


def parse_tally_quantity(qty_str: Optional[str]) -> Tuple[float, Optional[str]]:
    """
    Parses Tally quantity strings like:
      ' 10 NOS' -> (10.0, 'NOS')
      '-5 SET' -> (-5.0, 'SET')
      ' 100.50 KGS' -> (100.5, 'KGS')
      '12' -> (12.0, None)
    """
    if not qty_str:
        return 0.0, None
    s = qty_str.strip()
    match = re.search(r"^(-?[\d\.]+)\s*([A-Za-z0-9]+)?", s)
    if match:
        try:
            val = float(match.group(1))
            uom = match.group(2) if match.group(2) else None
            return val, uom
        except ValueError:
            pass
    return 0.0, None


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
    <TALLYREQUEST>Export Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <EXPORTDATA>
      <REQUESTDESC>
        <STATICVARIABLES>
          <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
        </STATICVARIABLES>
        <TDL>
          <TDLMESSAGE>
            <COLLECTION NAME="CompanyCollection" ISINITIALIZE="Yes">
              <TYPE>Company</TYPE>
              <NATIVEMETHOD>Name</NATIVEMETHOD>
              <NATIVEMETHOD>StartingFrom</NATIVEMETHOD>
              <NATIVEMETHOD>EndingAt</NATIVEMETHOD>
              <NATIVEMETHOD>Guid</NATIVEMETHOD>
            </COLLECTION>
          </TDLMESSAGE>
        </TDL>
      </REQUESTDESC>
    </EXPORTDATA>
  </BODY>
</ENVELOPE>"""

    @staticmethod
    def build_sales_vouchers_request(
        company_name: Optional[str] = None,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
        alter_id: Optional[int] = None,
    ) -> str:
        sv_company = f"<SVCURRENTCOMPANY>{escape_xml(company_name)}</SVCURRENTCOMPANY>" if company_name else ""
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
          {sv_company}
          {sv_from}
          {sv_to}
        </STATICVARIABLES>
      </REQUESTDESC>
    </EXPORTDATA>
  </BODY>
</ENVELOPE>"""

    @staticmethod
    def build_fallback_voucher_register_request(
        company_name: Optional[str] = None,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
    ) -> str:
        sv_company = f"<SVCURRENTCOMPANY>{escape_xml(company_name)}</SVCURRENTCOMPANY>" if company_name else ""
        sv_from = f"<SVFROMDATE>{format_date_for_tally(from_date)}</SVFROMDATE>" if from_date else ""
        sv_to = f"<SVTODATE>{format_date_for_tally(to_date)}</SVTODATE>" if to_date else ""

        return f"""<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Export Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <EXPORTDATA>
      <REQUESTDESC>
        <REPORTNAME>Voucher Register</REPORTNAME>
        <STATICVARIABLES>
          <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
          <VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>
          {sv_company}
          {sv_from}
          {sv_to}
        </STATICVARIABLES>
      </REQUESTDESC>
    </EXPORTDATA>
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
        if cur_comp and cur_comp.strip():
            name = cur_comp.strip()
            seen_names.add(name)
            companies.append({"name": name})

        # 2. Check for COMPANY tags anywhere
        for comp in root.iter("COMPANY"):
            name = comp.attrib.get("NAME") or clean_xml_text(comp.find("NAME")) or clean_xml_text(comp)
            if not name:
                rem = comp.find("REMOTECMPINFO.LIST")
                if rem is not None:
                    name = clean_xml_text(rem.find("NAME"))
            if (
                name
                and name not in seen_names
                and name not in ("List of Companies", "XML")
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

            # Only process vouchers that contain billed inventory items (goods dispatched to customers)
            inv_nodes = list(vch.findall("ALLINVENTORYENTRIES.LIST")) + list(vch.findall("INVENTORYENTRIES.LIST"))
            if not inv_nodes:
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
            state_name = clean_xml_text(vch.find("STATENAME")) or None

            # Address list
            address_lines = []
            addr_list = vch.find("ADDRESS.LIST")
            if addr_list is not None:
                for a in addr_list.iter("ADDRESS"):
                    txt = clean_xml_text(a)
                    if txt:
                        address_lines.append(txt)
            address = ", ".join(address_lines) if address_lines else None

            # 3. Status flags
            is_cancelled = clean_xml_text(vch.find("ISCANCELLED")).lower() in ("yes", "true", "1")
            is_deleted = clean_xml_text(vch.find("ISDELETED")).lower() in ("yes", "true", "1")

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
                "company_name": detected_company or default_company,
                "is_cancelled": is_cancelled,
                "is_deleted": is_deleted,
                "notes": narration,
                "raw_metadata": {"narration": narration} if narration else None,
                "items": items,
            })

        return vouchers


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
            req_xml = TallyXmlBuilder.build_company_list_request()
            resp_xml = await cls.post_xml(host, port, req_xml, tally_url, timeout=timeout)
            companies = TallyXmlParser.parse_companies(resp_xml)
            if not companies:
                # Fallback to Day Book request which always returns SVCURRENTCOMPANY in native reports
                daybook_xml = TallyXmlBuilder.build_sales_vouchers_request()
                try:
                    resp_db = await cls.post_xml(host, port, daybook_xml, tally_url, timeout=timeout)
                    companies = TallyXmlParser.parse_companies(resp_db)
                except Exception:
                    pass
            if not companies:
                # Fallback to collection request
                try:
                    col_xml = TallyXmlBuilder.build_company_collection_request()
                    resp_col = await cls.post_xml(host, port, col_xml, tally_url, timeout=timeout)
                    companies = TallyXmlParser.parse_companies(resp_col)
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


# ---------------------------------------------------------------------------
# Database Sync Manager
# ---------------------------------------------------------------------------

class TallySyncService:
    @staticmethod
    async def get_or_create_config(db: AsyncSession) -> TallyConfig:
        res = await db.execute(select(TallyConfig).order_by(TallyConfig.created_at.asc()).limit(1))
        cfg = res.scalar_one_or_none()
        if not cfg:
            cfg = TallyConfig(
                host=settings.tally_host,
                port=settings.tally_port,
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
            # If settings explicitly overridden in .env and config is still default localhost
            if settings.tally_host != "localhost" and cfg.host == "localhost":
                cfg.host = settings.tally_host
                changed = True
            if settings.tally_company_name and not cfg.company_name:
                cfg.company_name = settings.tally_company_name
                changed = True
            if changed:
                await db.commit()
                await db.refresh(cfg)
        return cfg

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
                if not shop:
                    city_val = v_data.get("state_name")
                    if not city_val and v_data.get("address"):
                        city_val = v_data["address"].split("\n")[0][:90].strip()
                    shop = Shop(
                        name=party_name_clean,
                        city=city_val or "Local",
                        is_active=True,
                    )
                    db.add(shop)
                    await db.flush()
                    try:
                        await ws_manager.broadcast("shop_created", {
                            "id": str(shop.id),
                            "name": shop.name,
                            "city": shop.city,
                            "is_active": True,
                        })
                    except Exception:
                        pass

            # Ensure voucher_date is python date object
            v_date = v_data["voucher_date"]
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
                    existing_vch.is_cancelled = True
                    existing_vch.is_deleted = is_deleted
                    cancelled += 1
                else:
                    existing_vch.is_cancelled = False
                    existing_vch.is_deleted = False

                if v_data.get("notes"):
                    existing_vch.notes = v_data["notes"]

                # Replace items
                existing_vch.items.clear()
                for itm in v_data.get("items", []):
                    item_name_clean = itm["item_name"].strip().lower()
                    matched_prod_id = prod_lookup_by_name.get(item_name_clean) or prod_lookup_by_model.get(item_name_clean)

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
                    is_cancelled=is_cancelled or is_deleted,
                    is_deleted=is_deleted,
                    is_processed=False,
                    notes=v_data.get("notes"),
                    raw_metadata=v_data.get("raw_metadata"),
                )

                for itm in v_data.get("items", []):
                    item_name_clean = itm["item_name"].strip().lower()
                    matched_prod_id = prod_lookup_by_name.get(item_name_clean) or prod_lookup_by_model.get(item_name_clean)

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
                if is_cancelled or is_deleted:
                    cancelled += 1
                else:
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
    async def perform_sync(
        cls,
        db: AsyncSession,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
        company_name: Optional[str] = None,
        force_full: bool = False,
        source: str = "DIRECT_HTTP",
    ) -> TallySyncHistory:
        """
        Executes a synchronization run against Tally HTTP interface.
        Extracts sales bills, stores non-financial vouchers, and updates sync state.
        """
        cfg = await cls.get_or_create_config(db)
        active_company = company_name or cfg.company_name

        # Validate or auto-detect active company against open Tally instance
        try:
            ok, _, companies = await TallyHttpClient.test_connection(cfg.host, cfg.port, cfg.tally_url, timeout=3.0)
            if ok and companies:
                open_names = [c["name"] for c in companies if c.get("name")]
                if open_names:
                    # If active_company not explicitly requested or not currently open in Tally, adopt the open company
                    if not company_name and (not active_company or active_company not in open_names):
                        active_company = open_names[0]
                        cfg.company_name = active_company
                        await db.commit()
                        logger.info(f"[TallySync] Updated active company to open Tally company: '{active_company}'")
        except Exception as e:
            logger.debug(f"[TallySync] Could not auto-detect company: {e}")

        alter_id = None if force_full else (cfg.last_alter_id if cfg.last_alter_id > 0 else None)

        # Default date range: current financial year (April 1st) if unspecified
        if not from_date and not alter_id:
            today = date.today()
            fy_start_year = today.year if today.month >= 4 else today.year - 1
            from_date = date(fy_start_year, 4, 1)
        if not to_date:
            to_date = date.today()

        history = TallySyncHistory(
            sync_source=source,
            company_name=active_company,
            status="IN_PROGRESS",
            started_at=datetime.now(),
            from_date=from_date.isoformat() if from_date else None,
            to_date=to_date.isoformat() if to_date else None,
            last_alter_id=alter_id,
        )
        db.add(history)
        await db.commit()
        await db.refresh(history)

        start_time = time.time()
        try:
            # 1. Fetch XML from Tally
            req_xml = TallyXmlBuilder.build_sales_vouchers_request(
                company_name=active_company,
                from_date=from_date,
                to_date=to_date,
                alter_id=alter_id,
            )
            try:
                resp_xml = await TallyHttpClient.post_xml(
                    cfg.host, cfg.port, req_xml, cfg.tally_url, timeout=30.0
                )
            except Exception as e:
                # If collection failed, attempt fallback Voucher Register
                logger.warning(f"TDL collection query failed, trying Voucher Register fallback: {e}")
                fb_xml = TallyXmlBuilder.build_fallback_voucher_register_request(
                    company_name=active_company, from_date=from_date, to_date=to_date
                )
                resp_xml = await TallyHttpClient.post_xml(
                    cfg.host, cfg.port, fb_xml, cfg.tally_url, timeout=30.0
                )

            # 2. Parse non-financial vouchers
            parsed_vouchers = TallyXmlParser.parse_sales_vouchers(resp_xml, default_company=active_company)
            if not active_company:
                detected_comps = TallyXmlParser.parse_companies(resp_xml)
                if detected_comps:
                    active_company = detected_comps[0].get("name")
                    cfg.company_name = active_company
                    history.company_name = active_company
            fetched_count = len(parsed_vouchers)

            # 3. Process into Database
            created, updated, cancelled = await cls.process_vouchers(
                db, parsed_vouchers, company_name=active_company
            )

            # 4. Update alter_id tracker
            max_alter = max([v["alter_id"] for v in parsed_vouchers if v.get("alter_id") is not None], default=cfg.last_alter_id)
            if max_alter and max_alter > cfg.last_alter_id:
                cfg.last_alter_id = max_alter

            cfg.last_sync_at = datetime.now()
            cfg.last_sync_status = "SUCCESS"
            cfg.last_sync_message = f"Synced {fetched_count} vouchers ({created} new, {updated} updated, {cancelled} cancelled)."

            history.status = "SUCCESS"
            history.completed_at = datetime.now()
            history.vouchers_fetched = fetched_count
            history.vouchers_created = created
            history.vouchers_updated = updated
            history.vouchers_cancelled = cancelled
            history.last_alter_id = cfg.last_alter_id
            await db.commit()
            await db.refresh(history)

            logger.info(
                f"[TallySync] Complete in {time.time()-start_time:.2f}s: "
                f"{fetched_count} fetched, {created} created, {updated} updated, {cancelled} cancelled."
            )
            return history

        except Exception as ex:
            err_msg = str(ex)
            logger.error(f"[TallySync] Failed: {err_msg}")
            cfg.last_sync_status = "FAILED"
            cfg.last_sync_message = err_msg

            history.status = "FAILED"
            history.completed_at = datetime.now()
            history.error_message = err_msg
            await db.commit()
            await db.refresh(history)
            return history


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
        # Wait 10 seconds after server startup before initial sync run
        await asyncio.sleep(10)
        while self._is_running:
            try:
                async with AsyncSessionLocal() as session:
                    cfg = await TallySyncService.get_or_create_config(session)
                    interval_sec = getattr(settings, "tally_sync_interval_seconds", None) or max(10, cfg.sync_interval_minutes * 60)

                    if cfg.is_enabled and cfg.auto_sync:
                        async with self._lock:
                            self._is_syncing = True
                            try:
                                await TallySyncService.perform_sync(session, source="DIRECT_HTTP")
                            except Exception as e:
                                logger.warning(f"[TallyWorker] Background sync tick failed: {e}")
                            finally:
                                self._is_syncing = False
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"[TallyWorker] Error in background sync loop: {e}")
                interval_sec = 60

            # Sleep for the configured interval
            try:
                await asyncio.sleep(interval_sec)
            except asyncio.CancelledError:
                break

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
