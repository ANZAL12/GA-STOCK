import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.mark.asyncio
async def test_bills_pagination_api():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Admin login
        login_res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "Admin@12345"})
        assert login_res.status_code == 200, f"Login failed: {login_res.text}"
        token = login_res.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # 1. Test GET /api/v1/outward/bills/paginated (default limit 50)
        res = await client.get("/api/v1/outward/bills/paginated?limit=50&offset=0", headers=headers)
        assert res.status_code == 200, f"Status {res.status_code}: {res.text}"
        data = res.json()
        assert data["limit"] == 50
        assert data["offset"] == 0
        assert data["total"] >= 0
        assert data["total_all"] >= 0
        assert data["total_active"] >= 0
        assert data["total_cancelled"] >= 0
        assert data["total_all"] == data["total_active"] + data["total_cancelled"]
        assert len(data["items"]) <= 50

        # 2. Test Pagination slice (limit 2, offset 0 vs offset 2)
        res_p1 = await client.get("/api/v1/outward/bills/paginated?limit=2&offset=0", headers=headers)
        assert res_p1.status_code == 200
        p1_data = res_p1.json()
        assert len(p1_data["items"]) <= 2

        if data["total"] > 2:
            res_p2 = await client.get("/api/v1/outward/bills/paginated?limit=2&offset=2", headers=headers)
            assert res_p2.status_code == 200
            p2_data = res_p2.json()
            assert len(p2_data["items"]) <= 2
            p1_keys = [b["bill_number"] for b in p1_data["items"]]
            p2_keys = [b["bill_number"] for b in p2_data["items"]]
            assert set(p1_keys).isdisjoint(set(p2_keys))

        # 3. Test Status Filter: active
        res_act = await client.get("/api/v1/outward/bills/paginated?status=active", headers=headers)
        assert res_act.status_code == 200
        act_data = res_act.json()
        assert act_data["total"] == data["total_active"]
        for b in act_data["items"]:
            assert not b["is_cancelled"]

        # 4. Test Status Filter: cancelled
        res_can = await client.get("/api/v1/outward/bills/paginated?status=cancelled", headers=headers)
        assert res_can.status_code == 200
        can_data = res_can.json()
        assert can_data["total"] == data["total_cancelled"]
        for b in can_data["items"]:
            assert b["is_cancelled"]

        # 5. Test Non-paginated mobile endpoint: /api/v1/outward/bills?limit=50&offset=0
        res_mob = await client.get("/api/v1/outward/bills?limit=50&offset=0", headers=headers)
        assert res_mob.status_code == 200
        mob_items = res_mob.json()
        assert isinstance(mob_items, list)
        assert len(mob_items) <= 50
