import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app


@pytest.mark.asyncio
async def test_shops_flow():
    run_id = uuid.uuid4().hex[:6]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Login as Admin
        admin_res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "Admin@12345"})
        assert admin_res.status_code == 200
        admin_headers = {"Authorization": f"Bearer {admin_res.json()['access_token']}"}

        # 2. Login as Staff
        staff_res = await client.post("/api/v1/auth/login", json={"username": "staff_test", "password": "Staff@12345"})
        assert staff_res.status_code == 200
        staff_headers = {"Authorization": f"Bearer {staff_res.json()['access_token']}"}

        # 3. Staff and admin can list shops
        res = await client.get("/api/v1/shops", headers=staff_headers)
        assert res.status_code == 200
        shops = res.json()
        assert len(shops) >= 3
        shop_names = [s["name"] for s in shops]
        assert "Sree Electronics" in shop_names
        assert "City Home Appliances" in shop_names

        # 4. Search shops by city
        res = await client.get("/api/v1/shops?q=kozhikode", headers=staff_headers)
        assert res.status_code == 200
        search_res = res.json()
        assert len(search_res) == 1
        assert search_res[0]["name"] == "City Home Appliances"

        # 5. Staff cannot create shop (403 Forbidden)
        shop_name = f"Modern-{run_id}"
        res = await client.post("/api/v1/shops", json={
            "name": shop_name,
            "city": "Tirur",
            "phone": "+91 98473 45678"
        }, headers=staff_headers)
        assert res.status_code == 403

        # 6. Admin can create shop
        res = await client.post("/api/v1/shops", json={
            "name": shop_name,
            "city": "Tirur",
            "phone": "+91 98473 45678"
        }, headers=admin_headers)
        assert res.status_code == 201
        created_shop = res.json()
        assert created_shop["name"] == shop_name
        assert created_shop["city"] == "Tirur"
        assert created_shop["is_active"] is True
        shop_id = created_shop["id"]

        # 7. Duplicate shop in same city rejected (400)
        res = await client.post("/api/v1/shops", json={
            "name": shop_name,
            "city": "Tirur",
            "phone": "+91 98473 45678"
        }, headers=admin_headers)
        assert res.status_code == 400

        # 8. Admin updates shop
        res = await client.put(f"/api/v1/shops/{shop_id}", json={
            "phone": "+91 98473 99999"
        }, headers=admin_headers)
        assert res.status_code == 200
        assert res.json()["phone"] == "+91 98473 99999"

        # 9. Get shop dispatched serials (currently 0)
        res = await client.get(f"/api/v1/shops/{shop_id}/dispatched-serials", headers=staff_headers)
        assert res.status_code == 200
        assert res.json() == []

        # 10. Admin soft-deactivates shop
        res = await client.delete(f"/api/v1/shops/{shop_id}", headers=admin_headers)
        assert res.status_code == 200
        assert res.json()["is_active"] is False

        # 11. Deactivated shop is filtered out when active_only=True
        res = await client.get("/api/v1/shops?active_only=true", headers=staff_headers)
        active_shop_ids = [s["id"] for s in res.json()]
        assert shop_id not in active_shop_ids

        # 12. Deactivated shop visible to admin with active_only=False
        res = await client.get("/api/v1/shops?active_only=false", headers=admin_headers)
        all_shop_ids = [s["id"] for s in res.json()]
        assert shop_id in all_shop_ids