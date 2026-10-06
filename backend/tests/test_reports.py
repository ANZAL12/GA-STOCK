import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app


@pytest.mark.asyncio
async def test_reports_and_export_flow():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Login as Staff
        staff_res = await client.post("/api/v1/auth/login", json={"username": "staff_test", "password": "Staff@12345"})
        assert staff_res.status_code == 200
        staff_headers = {"Authorization": f"Bearer {staff_res.json()['access_token']}"}

        # 2. Overview Report
        ov_res = await client.get("/api/v1/reports/overview", headers=staff_headers)
        assert ov_res.status_code == 200
        ov_data = ov_res.json()
        assert "tracked_items_on_shelves" in ov_data
        assert "received_since_golive" in ov_data
        assert "needs_attention" in ov_data
        assert isinstance(ov_data["needs_attention"]["all_clear"], bool)

        # 3. Stock by Model JSON Report
        sbm_res = await client.get("/api/v1/reports/stock-by-model", headers=staff_headers)
        assert sbm_res.status_code == 200
        sbm_list = sbm_res.json()
        assert len(sbm_list) >= 4
        samsung = next((p for p in sbm_list if "Samsung" in p["name"]), None)
        assert samsung is not None
        assert "available_count" in samsung
        assert "unmatched_dispatched_count" in samsung

        # 4. Export Stock by Model: CSV
        csv_res = await client.get("/api/v1/reports/stock-by-model?export=csv", headers=staff_headers)
        assert csv_res.status_code == 200
        assert "text/csv" in csv_res.headers["content-type"]
        assert len(csv_res.content) > 50

        # 5. Export Stock by Model: Excel (.xlsx)
        xlsx_res = await client.get("/api/v1/reports/stock-by-model?export=xlsx", headers=staff_headers)
        assert xlsx_res.status_code == 200
        assert "spreadsheetml" in xlsx_res.headers["content-type"]
        assert len(xlsx_res.content) > 100

        # 6. Export Stock by Model: PDF (.pdf)
        pdf_res = await client.get("/api/v1/reports/stock-by-model?export=pdf", headers=staff_headers)
        assert pdf_res.status_code == 200
        assert "application/pdf" in pdf_res.headers["content-type"]
        assert pdf_res.content.startswith(b"%PDF")

        # 7. Today Movements Timeline
        tl_res = await client.get("/api/v1/reports/today-timeline", headers=staff_headers)
        assert tl_res.status_code == 200
        tl_list = tl_res.json()
        assert isinstance(tl_list, list)

        # 8. Stock Out Report
        so_res = await client.get("/api/v1/reports/stock-out", headers=staff_headers)
        assert so_res.status_code == 200
        so_list = so_res.json()
        assert isinstance(so_list, list)

        # 9. Dedicated Unmatched Outward Report
        unm_res = await client.get("/api/v1/reports/unmatched-outward", headers=staff_headers)
        assert unm_res.status_code == 200
        unm_list = unm_res.json()
        assert isinstance(unm_list, list)
        for item in unm_list:
            assert item["is_matched"] is False

        # 10. Damaged Report
        dam_res = await client.get("/api/v1/reports/damaged", headers=staff_headers)
        assert dam_res.status_code == 200
        dam_list = dam_res.json()
        assert isinstance(dam_list, list)