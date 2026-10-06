import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app


@pytest.mark.asyncio
async def test_returns_and_status_flow():
    run_id = uuid.uuid4().hex[:6]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Login as Staff and Admin
        staff_res = await client.post("/api/v1/auth/login", json={"username": "staff_test", "password": "Staff@12345"})
        assert staff_res.status_code == 200
        staff_headers = {"Authorization": f"Bearer {staff_res.json()['access_token']}"}

        admin_res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "Admin@12345"})
        assert admin_res.status_code == 200
        admin_headers = {"Authorization": f"Bearer {admin_res.json()['access_token']}"}

        # 2. Get Shop and Product
        shop_res = await client.get("/api/v1/shops?q=sree", headers=staff_headers)
        shop = shop_res.json()[0]
        shop_id = shop["id"]

        tv_res = await client.get("/api/v1/products?q=samsung", headers=staff_headers)
        tv_prod = tv_res.json()[0]
        tv_id = tv_prod["id"]

        # 3. Setup: Inward a tracked serial and dispatch it
        tracked_sn = f"SMTV-RET-{run_id}-01"
        unmatched_sn = f"OLD-RET-{run_id}-02"

        # Inward tracked_sn
        await client.post(
            "/api/v1/inward/batches",
            json={"product_id": tv_id, "serials": [tracked_sn]},
            headers=staff_headers,
        )

        # Dispatch both tracked_sn (matched) and unmatched_sn (unmatched)
        out_res = await client.post(
            "/api/v1/outward/batches",
            json={
                "shop_id": shop_id,
                "product_id": tv_id,
                "delivery_reference": f"DEL-RET-{run_id}",
                "serials": [
                    {"serial_number": tracked_sn, "confirmed_warning": False},
                    {"serial_number": unmatched_sn, "confirmed_warning": False},
                ],
            },
            headers=staff_headers,
        )
        assert out_res.status_code == 201

        # 4. Lookup tracked serial for return
        lookup_tracked = await client.get(f"/api/v1/returns/lookup-serial?serial_number={tracked_sn}", headers=staff_headers)
        assert lookup_tracked.status_code == 200
        data_tr = lookup_tracked.json()
        assert data_tr["found"] is True
        assert data_tr["was_matched"] is True
        assert data_tr["shop_name"] == shop["name"]

        # 5. Record return for tracked serial
        ret_res1 = await client.post(
            "/api/v1/returns",
            json={
                "serial_number": tracked_sn,
                "product_id": tv_id,
                "shop_id": shop_id,
                "reason": "Customer reported minor display issue",
                "condition": "Like new with original box",
            },
            headers=staff_headers,
        )
        assert ret_res1.status_code == 201
        ret_data1 = ret_res1.json()
        assert ret_data1["serial_text"] == tracked_sn
        assert ret_data1["inspection_result"] is None
        return_id = ret_data1["id"]

        # 6. Admin inspects returned unit as Available (returns to stock!)
        initial_stock = (await client.get(f"/api/v1/products/{tv_id}", headers=staff_headers)).json()["current_stock_qty"]

        insp_res = await client.post(
            f"/api/v1/returns/{return_id}/inspect",
            json={"inspection_result": "available", "remarks": "Tested display port, HDMI cable was loose. Fully functional."},
            headers=admin_headers,
        )
        assert insp_res.status_code == 200
        assert insp_res.json()["inspection_result"] == "available"

        # Verify stock count restored +1
        after_stock = (await client.get(f"/api/v1/products/{tv_id}", headers=staff_headers)).json()["current_stock_qty"]
        assert after_stock == initial_stock + 1

        # 7. Return of unmatched pre-go-live serial
        lookup_unmatched = await client.get(f"/api/v1/returns/lookup-serial?serial_number={unmatched_sn}", headers=staff_headers)
        assert lookup_unmatched.status_code == 200
        data_unm = lookup_unmatched.json()
        assert data_unm["found"] is True
        assert data_unm["was_matched"] is False

        ret_res2 = await client.post(
            "/api/v1/returns",
            json={
                "serial_number": unmatched_sn,
                "product_id": tv_id,
                "shop_id": shop_id,
                "reason": "Shop stock return (pre-go-live surplus)",
            },
            headers=staff_headers,
        )
        assert ret_res2.status_code == 201
        assert ret_res2.json()["serial_number_id"] is not None  # Now has a tracked serial record!

        # 8. Universal Serial Lookup: checks complete vertical history
        lookup_full = await client.get(f"/api/v1/serials/lookup?serial_number={tracked_sn}", headers=staff_headers)
        assert lookup_full.status_code == 200
        detail = lookup_full.json()
        assert detail["is_tracked"] is True
        assert detail["status"] == "available"
        assert len(detail["history"]) >= 4  # inward, dispatched, returned, inspected!
        actions = [h["action"] for h in detail["history"]]
        assert "inward_recorded" in actions
        assert "dispatched_matched" in actions
        assert "returned" in actions
        assert "inspected" in actions

        # 9. Manual Status Change: Mark as Damaged
        sn_id = detail["serial_number_id"]
        status_chg = await client.patch(
            f"/api/v1/serials/{sn_id}/status",
            json={"new_status": "damaged", "reason": "Accidental drop in warehouse loading bay"},
            headers=admin_headers,
        )
        assert status_chg.status_code == 200
        assert status_chg.json()["status"] == "damaged"

        # Verify stock decreased by 1
        curr_stock = (await client.get(f"/api/v1/products/{tv_id}", headers=staff_headers)).json()["current_stock_qty"]
        assert curr_stock == after_stock - 1