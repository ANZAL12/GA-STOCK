import uuid
from datetime import date
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app


@pytest.mark.asyncio
async def test_outward_dispatch_flow():
    run_id = uuid.uuid4().hex[:6]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Login as Staff
        staff_res = await client.post("/api/v1/auth/login", json={"username": "staff_test", "password": "Staff@12345"})
        assert staff_res.status_code == 200
        staff_headers = {"Authorization": f"Bearer {staff_res.json()['access_token']}"}

        # 2. Get Shop and Product
        shop_res = await client.get("/api/v1/shops?limit=10", headers=staff_headers)
        assert shop_res.status_code == 200
        shops = shop_res.json()
        assert len(shops) >= 1
        shop = shops[0]
        shop_id = shop["id"]

        prod_res = await client.get("/api/v1/products?limit=10", headers=staff_headers)
        assert prod_res.status_code == 200
        products = prod_res.json()
        assert len(products) >= 2
        tv_prod = products[0]
        tv_id = tv_prod["id"]

        fridge_prod = products[1]
        fridge_id = fridge_prod["id"]

        # 3. Inward a serial for TV so we have a known tracked unit
        inward_serial = f"SMTV-{run_id}-MATCH"
        inw_res = await client.post(
            "/api/v1/inward/batches",
            json={
                "product_id": tv_id,
                "invoice_reference": f"INV-{run_id}-01",
                "serials": [inward_serial],
            },
            headers=staff_headers,
        )
        assert inw_res.status_code == 201

        # 4. Check serial - Case 1: Matched (Available and correct model)
        chk1 = await client.post(
            "/api/v1/outward/check-serial",
            json={"product_id": tv_id, "shop_id": shop_id, "serial_number": inward_serial},
            headers=staff_headers,
        )
        assert chk1.status_code == 200
        data1 = chk1.json()
        assert data1["case"] == 1
        assert data1["badge"] == "matched"
        assert data1["requires_confirmation"] is False

        # 5. Check serial - Case 2: Unmatched (pre-go-live stock, not in system)
        unmatched_serial = f"OLD-STOCK-{run_id}-99"
        chk2 = await client.post(
            "/api/v1/outward/check-serial",
            json={"product_id": tv_id, "shop_id": shop_id, "serial_number": unmatched_serial},
            headers=staff_headers,
        )
        assert chk2.status_code == 200
        data2 = chk2.json()
        assert data2["case"] == 2
        assert data2["badge"] == "unmatched"
        assert data2["requires_confirmation"] is False  # NOT an error!

        # 6. Check serial - Case 4: Model mismatch (TV serial scanned under Fridge)
        chk4 = await client.post(
            "/api/v1/outward/check-serial",
            json={"product_id": fridge_id, "shop_id": shop_id, "serial_number": inward_serial},
            headers=staff_headers,
        )
        assert chk4.status_code == 200
        data4 = chk4.json()
        assert data4["case"] == 4
        assert data4["badge"] == "warning"
        assert data4["requires_confirmation"] is True

        # 7. Check delivery reference soft warning
        ref_check1 = await client.post(
            "/api/v1/outward/check-reference",
            json={"shop_id": shop_id, "delivery_reference": f"DEL-{run_id}"},
            headers=staff_headers,
        )
        assert ref_check1.status_code == 200
        assert ref_check1.json()["has_warning"] is False

        # 8. Submit Outward batch with Case 1 (matched) and Case 2 (unmatched old stock)
        outward_res = await client.post(
            "/api/v1/outward/batches",
            json={
                "shop_id": shop_id,
                "product_id": tv_id,
                "delivery_reference": f"DEL-{run_id}",
                "serials": [
                    {"serial_number": inward_serial, "confirmed_warning": False},
                    {"serial_number": unmatched_serial, "confirmed_warning": False},
                ],
                "remarks": "Dispatched 1 matched and 1 old stock unit",
            },
            headers=staff_headers,
        )
        assert outward_res.status_code == 201
        outward_data = outward_res.json()
        assert outward_data["quantity"] == 2
        assert outward_data["matched_count"] == 1
        assert outward_data["unmatched_count"] == 1
        assert outward_data["flagged_count"] == 0
        batch_id = outward_data["id"]

        lines = outward_data["lines"]
        matched_line = next(l for l in lines if l["serial_text"] == inward_serial)
        assert matched_line["is_matched"] is True
        assert matched_line["status_label"] == "Matched"

        unmatched_line = next(l for l in lines if l["serial_text"] == unmatched_serial)
        assert unmatched_line["is_matched"] is False
        assert unmatched_line["serial_number_id"] is None
        assert unmatched_line["status_label"] == "Recorded only"

        # 9. Now inward_serial is in status Dispatched -> Check serial is blocked (Case 0)!
        chk0 = await client.post(
            "/api/v1/outward/check-serial",
            json={"product_id": tv_id, "shop_id": shop_id, "serial_number": inward_serial},
            headers=staff_headers,
        )
        assert chk0.status_code == 200
        data0 = chk0.json()
        assert data0["case"] == 0
        assert data0["badge"] == "blocked"
        assert data0["warning_duplicate_dispatch"] is True

        # 10. Attempting to dispatch an already-dispatched serial fails with 400
        fail_disp = await client.post(
            "/api/v1/outward/batches",
            json={
                "shop_id": shop_id,
                "product_id": tv_id,
                "serials": [{"serial_number": inward_serial, "confirmed_warning": False}],
            },
            headers=staff_headers,
        )
        assert fail_disp.status_code == 400
        assert "marked as dispatched" in fail_disp.json()["detail"].lower()

        # 11. Test Case 4 (Model Mismatch): Inward for TV, then dispatch under Fridge WITH confirmation -> flags for review
        mismatch_serial = f"SMTV-{run_id}-MISMATCH"
        await client.post(
            "/api/v1/inward/batches",
            json={"product_id": tv_id, "invoice_reference": f"INV-{run_id}-MM", "serials": [mismatch_serial]},
            headers=staff_headers,
        )
        ok_disp = await client.post(
            "/api/v1/outward/batches",
            json={
                "shop_id": shop_id,
                "product_id": fridge_id,
                "serials": [{"serial_number": mismatch_serial, "confirmed_warning": True}],
            },
            headers=staff_headers,
        )
        assert ok_disp.status_code == 201
        assert ok_disp.json()["flagged_count"] == 1
        assert ok_disp.json()["lines"][0]["is_flagged_for_review"] is True
        assert ok_disp.json()["lines"][0]["status_label"] == "Flagged"

        # 12. Soft warning for delivery reference triggers for the same shop same day
        ref_check2 = await client.post(
            "/api/v1/outward/check-reference",
            json={"shop_id": shop_id, "delivery_reference": f"DEL-{run_id}"},
            headers=staff_headers,
        )
        assert ref_check2.status_code == 200
        assert ref_check2.json()["has_warning"] is True

        # 13. Verify Shop dispatched serials list shows the dispatches
        shop_serials_res = await client.get(f"/api/v1/shops/{shop_id}/dispatched-serials", headers=staff_headers)
        assert shop_serials_res.status_code == 200
        disp_serials = shop_serials_res.json()
        texts = [s["serial_text"] for s in disp_serials]
        assert inward_serial in texts
        assert unmatched_serial in texts


@pytest.mark.asyncio
async def test_bill_update_and_delete_flow():
    run_id = uuid.uuid4().hex[:6]
    test_bill = f"BILL-UPD-DEL-{run_id}"

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Admin login
        adm_res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "Admin@12345"})
        assert adm_res.status_code == 200
        admin_headers = {"Authorization": f"Bearer {adm_res.json()['access_token']}"}

        # Get Shop & Product
        shop_res = await client.get("/api/v1/shops?limit=1", headers=admin_headers)
        shop = shop_res.json()[0]
        prod_res = await client.get("/api/v1/products?limit=1", headers=admin_headers)
        prod = prod_res.json()[0]

        # Inward serial
        sn = f"SN-{run_id}-TEST"
        await client.post(
            "/api/v1/inward/batches",
            json={"product_id": prod["id"], "invoice_reference": f"INV-{run_id}", "serials": [sn]},
            headers=admin_headers,
        )

        # Dispatch with bill_number
        disp_res = await client.post(
            "/api/v1/outward/batches",
            json={
                "shop_id": shop["id"],
                "product_id": prod["id"],
                "bill_number": test_bill,
                "delivery_reference": "OLD-VEHICLE-123",
                "serials": [{"serial_number": sn}],
            },
            headers=admin_headers,
        )
        assert disp_res.status_code == 201

        # 1. Update bill details via PATCH
        upd_res = await client.patch(
            f"/api/v1/outward/bills/{test_bill}",
            json={
                "vehicle_number": "KL-11-ZZ-9999",
                "transporter_name": "FastTrack Cargo",
                "delivery_note": "LR-445566",
                "remarks": "Updated delivery remarks",
            },
            headers=admin_headers,
        )
        assert upd_res.status_code == 200
        upd_data = upd_res.json()
        assert upd_data["success"] is True
        assert upd_data["vehicle_number"] == "KL-11-ZZ-9999"

        # Verify bill detail reflects updated fields
        detail_res = await client.get(f"/api/v1/outward/bills/{test_bill}", headers=admin_headers)
        assert detail_res.status_code == 200
        assert detail_res.json()["vehicle_number"] == "KL-11-ZZ-9999"
        assert detail_res.json()["remarks"] == "Updated delivery remarks"

        # 2. Delete bill via DELETE
        del_res = await client.delete(f"/api/v1/outward/bills/{test_bill}", headers=admin_headers)
        assert del_res.status_code == 200
        assert del_res.json()["success"] is True

        # Bill should no longer exist
        detail_after = await client.get(f"/api/v1/outward/bills/{test_bill}", headers=admin_headers)
        assert detail_after.status_code == 404
