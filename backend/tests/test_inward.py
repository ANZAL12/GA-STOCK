import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app


@pytest.mark.asyncio
async def test_inward_stock_flow():
    run_id = uuid.uuid4().hex[:6]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Login as Staff
        staff_res = await client.post("/api/v1/auth/login", json={"username": "staff_test", "password": "Staff@12345"})
        assert staff_res.status_code == 200
        staff_headers = {"Authorization": f"Bearer {staff_res.json()['access_token']}"}

        # 2. Get a sample product (Samsung TV)
        prod_res = await client.get("/api/v1/products?q=samsung", headers=staff_headers)
        assert prod_res.status_code == 200
        products = prod_res.json()
        assert len(products) >= 1
        tv_product = products[0]
        tv_prod_id = tv_product["id"]
        initial_stock = tv_product["current_stock_qty"]

        # 3. Real-time validation for an unused serial
        serial_1 = f"SMTV-{run_id}-001"
        serial_2 = f"SMTV-{run_id}-002"
        serial_3 = f"SMTV-{run_id}-003"

        val_res = await client.post(
            "/api/v1/inward/validate-serial",
            json={"serial_number": serial_1},
            headers=staff_headers,
        )
        assert val_res.status_code == 200
        val_data = val_res.json()
        assert val_data["is_valid"] is True
        assert val_data["already_exists"] is False

        # 4. Reject batch with duplicate serials inside itself
        dup_batch_res = await client.post(
            "/api/v1/inward/batches",
            json={
                "product_id": tv_prod_id,
                "invoice_reference": f"INV-{run_id}-DUP",
                "serials": [serial_1, serial_1],
            },
            headers=staff_headers,
        )
        assert dup_batch_res.status_code == 400
        assert "duplicate serial number in this batch" in dup_batch_res.json()["detail"].lower()

        # 5. Successfully submit a valid inward batch
        batch_res = await client.post(
            "/api/v1/inward/batches",
            json={
                "product_id": tv_prod_id,
                "invoice_reference": f"INV-{run_id}-01",
                "serials": [serial_1, serial_2, serial_3],
                "remarks": "Received in good condition via truck 12",
            },
            headers=staff_headers,
        )
        assert batch_res.status_code == 201
        batch_data = batch_res.json()
        assert batch_data["quantity"] == 3
        assert len(batch_data["serials"]) == 3
        batch_id = batch_data["id"]

        # 6. Verify product stock increased by 3 and has_had_inward is True
        updated_prod_res = await client.get(f"/api/v1/products/{tv_prod_id}", headers=staff_headers)
        assert updated_prod_res.status_code == 200
        updated_prod = updated_prod_res.json()
        assert updated_prod["current_stock_qty"] == initial_stock + 3
        assert updated_prod["has_had_inward"] is True

        # 7. Real-time validation for an existing serial now reports model registered under
        val_existing = await client.post(
            "/api/v1/inward/validate-serial",
            json={"serial_number": serial_1},
            headers=staff_headers,
        )
        assert val_existing.status_code == 200
        val_existing_data = val_existing.json()
        assert val_existing_data["is_valid"] is False
        assert val_existing_data["already_exists"] is True
        assert "Samsung" in val_existing_data["registered_model_name"]
        assert "already registered" in val_existing_data["message"]

        # 8. Attempt to inward the same serial under a different product (e.g. LG Fridge)
        fridge_res = await client.get("/api/v1/products?q=refrigerator", headers=staff_headers)
        fridge_prod = fridge_res.json()[0]

        clash_batch_res = await client.post(
            "/api/v1/inward/batches",
            json={
                "product_id": fridge_prod["id"],
                "invoice_reference": f"INV-{run_id}-CLASH",
                "serials": [serial_1],
            },
            headers=staff_headers,
        )
        assert clash_batch_res.status_code == 400
        detail_msg = clash_batch_res.json()["detail"]
        assert serial_1 in detail_msg
        assert "Samsung" in detail_msg  # Informs staff of the model it's already registered under!

        # 9. List inward batches
        list_res = await client.get(f"/api/v1/inward/batches?product_id={tv_prod_id}", headers=staff_headers)
        assert list_res.status_code == 200
        batch_list = list_res.json()
        assert any(b["id"] == batch_id for b in batch_list)

        # 10. Get batch details by ID includes full serials list
        get_batch_res = await client.get(f"/api/v1/inward/batches/{batch_id}", headers=staff_headers)
        assert get_batch_res.status_code == 200
        batch_details = get_batch_res.json()
        assert batch_details["quantity"] == 3
        assert sorted(batch_details["serials"]) == sorted([serial_1, serial_2, serial_3])