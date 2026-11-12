import uuid
from datetime import date, datetime
import pytest
from httpx import ASGITransport, AsyncClient

from app.database import AsyncSessionLocal
from sqlalchemy import delete, select
from app.main import app
from app.models.product import Product
from app.models.tally import TallyConfig, TallySalesVoucher, TallyVoucherItem
from app.services.tally_service import (
    TallySyncService,
    TallyXmlBuilder,
    TallyXmlParser,
    parse_tally_date,
    parse_tally_quantity,
)

SAMPLE_COMPANIES_XML = """<ENVELOPE>
  <BODY>
    <DATA>
      <COLLECTION>
        <COMPANY NAME="Global Agencies (2026-2027)">
          <NAME>Global Agencies (2026-2027)</NAME>
          <STARTINGFROM>20260401</STARTINGFROM>
          <ENDINGAT>20270331</ENDINGAT>
          <GUID>comp-guid-001</GUID>
        </COMPANY>
        <COMPANY NAME="Global Branches Kerala">
          <NAME>Global Branches Kerala</NAME>
          <STARTINGFROM>20260401</STARTINGFROM>
          <ENDINGAT>20270331</ENDINGAT>
          <GUID>comp-guid-002</GUID>
        </COMPANY>
      </COLLECTION>
    </DATA>
  </BODY>
</ENVELOPE>"""

SAMPLE_SALES_VOUCHERS_XML = """<ENVELOPE>
  <BODY>
    <DATA>
      <COLLECTION>
        <!-- Voucher 1: Active Sales Bill with 2 items and godown allocations -->
        <VOUCHER VCHTYPE="Sales" ACTION="Create">
          <DATE>20261105</DATE>
          <GUID>tally-guid-sales-001</GUID>
          <ALTERID>1001</ALTERID>
          <MASTERID>501</MASTERID>
          <VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>
          <VOUCHERNUMBER>INV/2026/0451</VOUCHERNUMBER>
          <PARTYNAME>Sree Electronics</PARTYNAME>
          <PARTYLEDGERNAME>Sree Electronics Ledger</PARTYLEDGERNAME>
          <BASICBUYERNAME>Sree Electronics Outlet</BASICBUYERNAME>
          <STATENAME>Kerala</STATENAME>
          <ADDRESS.LIST>
            <ADDRESS>Door No. 12/400, MG Road</ADDRESS>
            <ADDRESS>Calicut, Kerala - 673001</ADDRESS>
          </ADDRESS.LIST>
          <ISCANCELLED>No</ISCANCELLED>
          <ISDELETED>No</ISDELETED>
          <NARRATION>Urgent festive stock dispatch</NARRATION>

          <!-- DUMMY FINANCIAL FIELDS IN TALLY THAT MUST BE COMPLETELY IGNORED -->
          <RATE>24500.00/NOS</RATE>
          <AMOUNT>-245000.00</AMOUNT>
          <DISCOUNT>5%</DISCOUNT>
          <TAXAMOUNT>44100.00</TAXAMOUNT>

          <!-- Inventory Item 1 -->
          <ALLINVENTORYENTRIES.LIST>
            <STOCKITEMNAME>Samsung 43 Crystal UHD 4K TV</STOCKITEMNAME>
            <ACTUALQTY> 10 NOS</ACTUALQTY>
            <BILLEDQTY> 10 NOS</BILLEDQTY>
            <UNIT>NOS</UNIT>
            <RATE>24500.00/NOS</RATE>
            <AMOUNT>-245000.00</AMOUNT>
            <BATCHALLOCATIONS.LIST>
              <GODOWNNAME>Main Godown</GODOWNNAME>
              <BATCHNAME>BATCH-2026-TV-01</BATCHNAME>
              <ACTUALQTY> 10 NOS</ACTUALQTY>
              <BILLEDQTY> 10 NOS</BILLEDQTY>
              <AMOUNT>-245000.00</AMOUNT>
            </BATCHALLOCATIONS.LIST>
          </ALLINVENTORYENTRIES.LIST>

          <!-- Inventory Item 2 -->
          <ALLINVENTORYENTRIES.LIST>
            <STOCKITEMNAME>Voltas 1.5T Inverter AC Split</STOCKITEMNAME>
            <STOCKITEMID>VOL-15T-INV</STOCKITEMID>
            <ACTUALQTY> 4 SET</ACTUALQTY>
            <BILLEDQTY> 4 SET</BILLEDQTY>
            <UNIT>SET</UNIT>
            <RATE>32000.00/SET</RATE>
            <AMOUNT>-128000.00</AMOUNT>
            <BATCHALLOCATIONS.LIST>
              <GODOWNNAME>North Warehouse</GODOWNNAME>
              <BATCHNAME>BATCH-AC-SPLIT</BATCHNAME>
              <ACTUALQTY> 4 SET</ACTUALQTY>
              <BILLEDQTY> 4 SET</BILLEDQTY>
            </BATCHALLOCATIONS.LIST>
          </ALLINVENTORYENTRIES.LIST>

          <!-- Ledger entries containing taxes & totals - MUST BE IGNORED -->
          <LEDGERENTRIES.LIST>
            <LEDGERNAME>CGST @ 9%</LEDGERNAME>
            <AMOUNT>-33570.00</AMOUNT>
          </LEDGERENTRIES.LIST>
        </VOUCHER>

        <!-- Voucher 2: Cancelled Bill -->
        <VOUCHER VCHTYPE="Sales" ACTION="Alter">
          <DATE>20261104</DATE>
          <GUID>tally-guid-sales-002</GUID>
          <ALTERID>1002</ALTERID>
          <MASTERID>502</MASTERID>
          <VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>
          <VOUCHERNUMBER>INV/2026/0450</VOUCHERNUMBER>
          <PARTYNAME>Metro Appliances</PARTYNAME>
          <ISCANCELLED>Yes</ISCANCELLED>
          <ISDELETED>No</ISDELETED>
          <ALLINVENTORYENTRIES.LIST>
            <STOCKITEMNAME>LG 8kg Front Load Washing Machine</STOCKITEMNAME>
            <ACTUALQTY> 2 NOS</ACTUALQTY>
            <BILLEDQTY> 2 NOS</BILLEDQTY>
            <UNIT>NOS</UNIT>
          </ALLINVENTORYENTRIES.LIST>
        </VOUCHER>
      </COLLECTION>
    </DATA>
  </BODY>
</ENVELOPE>"""


def test_tally_helpers():
    # Test Quantity parsing
    q1, u1 = parse_tally_quantity(" 10.50 NOS")
    assert q1 == 10.5
    assert u1 == "NOS"

    q2, u2 = parse_tally_quantity("-5 SET")
    assert q2 == -5.0
    assert u2 == "SET"

    q3, u3 = parse_tally_quantity("25")
    assert q3 == 25.0
    assert u3 is None

    # Test Date parsing
    d1 = parse_tally_date("20261105")
    assert d1 == date(2026, 11, 5)

    d2 = parse_tally_date("2026-11-05")
    assert d2 == date(2026, 11, 5)

    d3 = parse_tally_date("5-Nov-2026")
    assert d3 == date(2026, 11, 5)


def test_parse_tally_companies_xml():
    companies = TallyXmlParser.parse_companies(SAMPLE_COMPANIES_XML)
    assert len(companies) == 2
    assert companies[0]["name"] == "Global Agencies (2026-2027)"
    assert companies[0]["starting_from"] == "20260401"
    assert companies[1]["name"] == "Global Branches Kerala"


def test_parse_tally_sales_vouchers_non_financial():
    vouchers = TallyXmlParser.parse_sales_vouchers(SAMPLE_SALES_VOUCHERS_XML, default_company="Global Agencies (2026-2027)")
    assert len(vouchers) == 2

    # Check Voucher 1
    v1 = vouchers[0]
    assert v1["guid"] == "tally-guid-sales-001"
    assert v1["voucher_number"] == "INV/2026/0451"
    assert v1["voucher_date"] == date(2026, 11, 5)
    assert v1["party_name"] == "Sree Electronics"
    assert v1["party_ledger_name"] == "Sree Electronics Ledger"
    assert v1["buyer_name"] == "Sree Electronics Outlet"
    assert v1["state_name"] == "Kerala"
    assert "MG Road" in v1["address"]
    assert v1["is_cancelled"] is False
    assert v1["notes"] == "Urgent festive stock dispatch"

    # Strictly verify NO financial keys exist in parsed voucher
    for financial_key in ("rate", "amount", "tax", "discount", "total", "outstanding", "price"):
        assert financial_key not in v1

    # Check items of Voucher 1
    items = v1["items"]
    assert len(items) == 2

    i1 = items[0]
    assert i1["item_name"] == "Samsung 43 Crystal UHD 4K TV"
    assert i1["quantity"] == 10.0
    assert i1["uom"] == "NOS"
    assert i1["godown_name"] == "Main Godown"
    assert i1["batch_name"] == "BATCH-2026-TV-01"

    # Strictly verify NO financial keys in parsed items
    for financial_key in ("rate", "amount", "tax", "discount", "price", "value"):
        assert financial_key not in i1

    i2 = items[1]
    assert i2["item_name"] == "Voltas 1.5T Inverter AC Split"
    assert i2["item_code"] == "VOL-15T-INV"
    assert i2["quantity"] == 4.0
    assert i2["uom"] == "SET"
    assert i2["godown_name"] == "North Warehouse"

    # Check Voucher 2 (Cancelled)
    v2 = vouchers[1]
    assert v2["guid"] == "tally-guid-sales-002"
    assert v2["voucher_number"] == "INV/2026/0450"
    assert v2["is_cancelled"] is True
    assert len(v2["items"]) == 1
    assert v2["items"][0]["quantity"] == 2.0


@pytest.mark.asyncio
async def test_tally_database_sync_and_endpoints():
    run_id = uuid.uuid4().hex[:6]
    test_xml = SAMPLE_SALES_VOUCHERS_XML.replace("tally-guid-sales-", f"tally-guid-sales-{run_id}-").replace("INV/2026/", f"INV/{run_id}/")

    async with AsyncSessionLocal() as session:
        # 1. Process sample vouchers into DB
        parsed_vouchers = TallyXmlParser.parse_sales_vouchers(test_xml, default_company="Global Agencies")
        created, updated, cancelled = await TallySyncService.process_vouchers(
            session, parsed_vouchers, company_name="Global Agencies"
        )
        assert created == 1
        assert cancelled == 1

        # Check idempotent update
        c2, u2, canc2 = await TallySyncService.process_vouchers(
            session, parsed_vouchers, company_name="Global Agencies"
        )
        assert c2 == 0
        assert u2 == 1

    # 2. Test FastAPI Endpoints
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Login as Admin
        admin_res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "Admin@12345"})
        assert admin_res.status_code == 200
        admin_token = admin_res.json()["access_token"]
        headers = {"Authorization": f"Bearer {admin_token}"}

        # Test GET /api/tally/status (direct alias)
        status_res = await client.get("/api/tally/status", headers=headers)
        assert status_res.status_code == 200
        status_data = status_res.json()
        assert "is_connected" in status_data
        assert "total_vouchers" in status_data
        assert status_data["total_vouchers"] >= 1

        # Test POST /api/tally/connect
        conn_res = await client.post(
            "/api/tally/connect",
            json={
                "host": "localhost",
                "port": 9000,
                "company_name": "Global Agencies (2026-2027)",
                "auto_sync": True,
                "sync_interval_minutes": 2,
            },
            headers=headers,
        )
        assert conn_res.status_code == 200
        conn_data = conn_res.json()
        assert conn_data["active_company"] == "Global Agencies (2026-2027)"
        agent_token = conn_data["config"]["agent_token"]
        assert agent_token is not None

        # Test GET /api/tally/sales-vouchers
        list_res = await client.get(f"/api/tally/sales-vouchers?q={run_id}&include_mock=true", headers=headers)
        assert list_res.status_code == 200
        vouchers_list = list_res.json()
        assert len(vouchers_list) >= 1
        v1 = vouchers_list[0]
        assert v1["voucher_number"] == f"INV/{run_id}/0451"
        assert v1["party_name"] == "Sree Electronics"
        assert v1["item_count"] == 2
        assert "Main Godown" in v1["godowns"]

        # Ensure NO financial information in API response
        for k in ("rate", "amount", "total", "tax", "discount", "price"):
            assert k not in v1

        # Test GET /api/tally/sales-vouchers/{id}
        detail_res = await client.get(f"/api/tally/sales-vouchers/{v1['id']}", headers=headers)
        assert detail_res.status_code == 200
        detail_data = detail_res.json()
        assert len(detail_data["items"]) == 2
        for itm in detail_data["items"]:
            assert "item_name" in itm
            assert "quantity" in itm
            assert "uom" in itm
            # No financial info in items response
            for k in ("rate", "amount", "total", "tax", "discount", "price"):
                assert k not in itm

        # Test POST /api/tally/sales-vouchers/{id}/mark-processed
        proc_res = await client.post(
            f"/api/tally/sales-vouchers/{v1['id']}/mark-processed?processed=true&notes=Dispatched",
            headers=headers,
        )
        assert proc_res.status_code == 200
        assert proc_res.json()["is_processed"] is True

        # Test GET /api/tally/sync-status
        sync_status_res = await client.get("/api/tally/sync-status", headers=headers)
        assert sync_status_res.status_code == 200
        assert "is_syncing" in sync_status_res.json()

        # Test POST /api/tally/agent/push (with valid token)
        agent_push_res = await client.post(
            "/api/v1/tally/agent/push",
            headers={"X-Tally-Agent-Token": agent_token},
            json={
                "company_name": "Global Agencies",
                "vouchers": [
                    {
                        "guid": f"agent-push-vch-{run_id}",
                        "voucher_number": f"INV/AGENT/{run_id}",
                        "voucher_date": "2026-11-05",
                        "party_name": "Agent Delivered Store",
                        "items": [
                            {"item_name": "Micro Wave Oven", "quantity": 1.0, "uom": "NOS", "godown_name": "Main Location"}
                        ]
                    }
                ]
            }
        )
        assert agent_push_res.status_code == 200
        assert agent_push_res.json()["status"] == "SUCCESS"
        assert agent_push_res.json()["created_count"] == 1

        # Test POST /api/tally/agent/push with INVALID token (expect 403)
        bad_token_res = await client.post(
            "/api/v1/tally/agent/push",
            headers={"X-Tally-Agent-Token": "invalid-token-123"},
            json={"vouchers": []}
        )
        assert bad_token_res.status_code == 403

        # Clean up only this test run's vouchers and shops
        async with AsyncSessionLocal() as cleanup_session:
            from app.models.tally import TallyVoucherItem, TallySalesVoucher, TallySyncHistory
            from app.models.shop import Shop
            from sqlalchemy import or_
            await cleanup_session.execute(
                delete(TallyVoucherItem).where(
                    TallyVoucherItem.voucher_id.in_(
                        select(TallySalesVoucher.id).where(
                            or_(
                                TallySalesVoucher.guid.contains(run_id),
                                TallySalesVoucher.guid.startswith("tally-guid-sales-"),
                                TallySalesVoucher.guid.startswith("agent-push-vch-"),
                            )
                        )
                    )
                )
            )
            await cleanup_session.execute(
                delete(TallySalesVoucher).where(
                    or_(
                        TallySalesVoucher.guid.contains(run_id),
                        TallySalesVoucher.guid.startswith("tally-guid-sales-"),
                        TallySalesVoucher.guid.startswith("agent-push-vch-"),
                    )
                )
            )
            await cleanup_session.execute(delete(Shop).where(Shop.name.in_(["Agent Delivered Store", "Sree Electronics"])))
            await cleanup_session.commit()


@pytest.mark.asyncio
async def test_outward_check_serial_with_tally_fallback_id():
    """Verify that check-serial and check-reference gracefully handle non-UUID strings without 422."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Login
        login_res = await client.post("/api/v1/auth/login", json={"username": "staff_test", "password": "Staff@12345"})
        assert login_res.status_code == 200
        headers = {"Authorization": f"Bearer {login_res.json()['access_token']}"}

        # 1. GET check-serial with non-UUID product_id fallback string
        res1 = await client.get(
            "/api/v1/outward/check-serial?serial_number=NONEXISTENT123&product_id=tally_item_dummy123",
            headers=headers,
        )
        assert res1.status_code == 200, f"Expected 200 but got {res1.status_code}: {res1.text}"
        data1 = res1.json()
        assert data1["case"] == 2  # Untracked stock case

        # 2. POST check-serial with non-UUID product_id fallback string
        res2 = await client.post(
            "/api/v1/outward/check-serial",
            headers=headers,
            json={"serial_number": "NONEXISTENT123", "product_id": "tally_item_dummy123"},
        )
        assert res2.status_code == 200, f"Expected 200 but got {res2.status_code}: {res2.text}"
        data2 = res2.json()
        assert data2["case"] == 2

        # 3. GET check-reference with non-UUID shop_id
        res3 = await client.get(
            "/api/v1/outward/check-reference?reference=REF123&shop_id=tally_shop_nonuuid",
            headers=headers,
        )
        assert res3.status_code == 200, f"Expected 200 but got {res3.status_code}: {res3.text}"
        data3 = res3.json()
        assert data3["has_warning"] is False


@pytest.mark.asyncio
async def test_tally_cancellation_marks_outward_batch_cancelled_without_changing_serial_status():
    """
    Verify that when a bill is cancelled from Tally:
    1. OutwardBatch.is_cancelled is marked True with reason 'Cancelled in TallyPrime'
    2. OutwardLine.is_cancelled is marked True
    3. SerialNumber.status is NOT changed (remains dispatched until physically scanned as Return by godown staff)
    """
    from datetime import date
    from app.models.outward import OutwardBatch, OutwardLine
    from app.models.serial import SerialNumber, SerialStatus
    from app.models.product import Product
    from app.models.shop import Shop
    from app.models.user import User

    test_b_num = f"TALLY-CANCEL-{uuid.uuid4().hex[:6]}".upper()

    async with AsyncSessionLocal() as session:
        # 1. Setup test product & shop
        prod = (await session.execute(select(Product))).scalars().first()
        shop = (await session.execute(select(Shop))).scalars().first()
        user = (await session.execute(select(User))).scalars().first()
        assert prod is not None
        assert shop is not None
        assert user is not None

        # 2. Setup outward batch and line
        batch = OutwardBatch(
            shop_id=shop.id,
            product_id=prod.id,
            dispatched_by_user_id=user.id,
            quantity=1,
            matched_count=1,
            unmatched_count=0,
            flagged_count=0,
            transaction_date=date.today(),
            bill_number=test_b_num,
            is_cancelled=False,
        )
        session.add(batch)
        await session.flush()

        test_sn_text = f"SN-CANCEL-TEST-{uuid.uuid4().hex[:6]}".upper()
        sn = SerialNumber(
            serial_number=test_sn_text,
            product_id=prod.id,
            status=SerialStatus.dispatched,
            last_shop_id=shop.id,
        )
        session.add(sn)
        await session.flush()

        line = OutwardLine(
            batch_id=batch.id,
            product_id=prod.id,
            shop_id=shop.id,
            serial_text=test_sn_text,
            serial_number_id=sn.id,
            is_matched=True,
            is_cancelled=False,
            transaction_date=date.today(),
        )
        session.add(line)
        await session.commit()

        try:
            # 3. Process incoming Tally cancellation for this voucher
            vch_cancel_payload = [
                {
                    "guid": f"tally-guid-cancel-{test_b_num}",
                    "voucher_number": test_b_num,
                    "voucher_date": date.today(),
                    "party_name": shop.name,
                    "is_cancelled": True,
                    "is_deleted": False,
                    "items": [],
                }
            ]
            c, u, canc = await TallySyncService.process_vouchers(session, vch_cancel_payload)
            assert canc == 1

            # 4. Verify OutwardBatch and OutwardLine are cancelled
            reloaded_batch = await session.get(OutwardBatch, batch.id)
            assert reloaded_batch.is_cancelled is True
            assert reloaded_batch.cancel_reason == "Cancelled in TallyPrime"
            assert reloaded_batch.cancelled_at is not None

            reloaded_line = await session.get(OutwardLine, line.id)
            assert reloaded_line.is_cancelled is True

            # 5. STRICT USER CONSTRAINT: Serial number status MUST NOT be changed!
            reloaded_sn = await session.get(SerialNumber, sn.id)
            assert reloaded_sn.status == SerialStatus.dispatched

        finally:
            # Cleanup test data
            await session.delete(line)
            await session.delete(sn)
            await session.delete(batch)
            await session.commit()


@pytest.mark.asyncio
async def test_brand_separated_shop_gstin_auto_fill():
    """
    Test GSTIN extraction from nested Tally elements, root name extraction,
    and automatic GSTIN inheritance across brand-separated shops.
    """
    from app.services.tally_service import (
        extract_gstin,
        extract_gstin_from_element,
        get_shop_root_name,
        TallySyncService,
    )
    from app.models.shop import Shop
    import xml.etree.ElementTree as ET
    import uuid

    # 1. Test root name normalization
    assert get_shop_root_name("APOLLO ELECTRONICS - DAIKIN") == "APOLLO ELECTRONICS"
    assert get_shop_root_name("APOLLO ELECTRONICS (VOLTAS)") == "APOLLO ELECTRONICS"
    assert get_shop_root_name("APOLLO ELECTRONICS [LG]") == "APOLLO ELECTRONICS"
    assert get_shop_root_name("APOLLO ELECTRONICS - AC DIVISION") == "APOLLO ELECTRONICS"
    assert get_shop_root_name("APOLLO ELECTRONICS DAIKIN") == "APOLLO ELECTRONICS"

    # 2. Test nested Tally GST extraction
    xml_sample = """
    <LEDGER NAME="ABC TRADERS (DAIKIN)">
      <LEDGSTREGDETAILS.LIST>
        <LEDGSTREGDETAILS>
          <GSTREGISTRATIONNUMBER>32AABCU9876D1Z5</GSTREGISTRATIONNUMBER>
        </LEDGSTREGDETAILS>
      </LEDGSTREGDETAILS.LIST>
    </LEDGER>
    """
    elem = ET.fromstring(xml_sample)
    extracted = extract_gstin_from_element(elem)
    assert extracted == "32AABCU9876D1Z5"

    # 3. Test Database auto_fill_brand_gstins across brand siblings
    async with AsyncSessionLocal() as session:
        uid = uuid.uuid4().hex[:6]
        shop_a = Shop(
            name=f"BRAND SHOP {uid} (DAIKIN)",
            city="Cochin",
            gstin="32AABCU1234F1Z5",
            source="TALLY",
            is_active=True,
        )
        shop_b = Shop(
            name=f"BRAND SHOP {uid} - VOLTAS",
            city="Cochin",
            gstin=None,
            source="TALLY",
            is_active=True,
        )
        session.add(shop_a)
        session.add(shop_b)
        await session.commit()

        try:
            filled = await TallySyncService.auto_fill_brand_gstins(session)
            assert filled >= 1

            reloaded_b = await session.get(Shop, shop_b.id)
            assert reloaded_b.gstin == "32AABCU1234F1Z5"

        finally:
            await session.delete(shop_a)
            await session.delete(shop_b)
            await session.commit()

