import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.database import AsyncSessionLocal
from app.models.enums import UserRole
from app.models.user import User
from app.core.security import get_password_hash
from sqlalchemy import select


async def ensure_staff_user():
    async with AsyncSessionLocal() as session:
        res = await session.execute(select(User).where(User.username == "staff_test"))
        staff = res.scalar_one_or_none()
        if not staff:
            staff = User(
                username="staff_test",
                full_name="Godown Staff",
                password_hash=get_password_hash("Staff@12345"),
                role=UserRole.staff,
                is_active=True,
            )
            session.add(staff)
            await session.commit()


@pytest.mark.asyncio
async def test_products_and_categories_flow():
    await ensure_staff_user()
    run_id = uuid.uuid4().hex[:6]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Login as Admin
        admin_res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "Admin@12345"})
        assert admin_res.status_code == 200
        admin_token = admin_res.json()["access_token"]
        admin_headers = {"Authorization": f"Bearer {admin_token}"}

        # 2. Login as Staff
        staff_res = await client.post("/api/v1/auth/login", json={"username": "staff_test", "password": "Staff@12345"})
        assert staff_res.status_code == 200
        staff_token = staff_res.json()["access_token"]
        staff_headers = {"Authorization": f"Bearer {staff_token}"}

        # 3. List categories (both staff and admin can view)
        res = await client.get("/api/v1/categories", headers=staff_headers)
        assert res.status_code == 200
        cats = res.json()
        assert len(cats) >= 4
        cat_names = [c["name"] for c in cats]
        assert "Television" in cat_names
        tv_cat = next(c for c in cats if c["name"] == "Television")
        assert tv_cat["product_count"] >= 1

        # 4. Staff cannot create category (403 Forbidden)
        res = await client.post("/api/v1/categories", json={"name": f"Audio-{run_id}"}, headers=staff_headers)
        assert res.status_code == 403

        # 5. Admin can create category
        cat_name = f"Microwave-{run_id}"
        res = await client.post("/api/v1/categories", json={"name": cat_name}, headers=admin_headers)
        assert res.status_code == 201
        new_cat = res.json()
        new_cat_id = new_cat["id"]

        # 6. Admin can update category
        updated_cat_name = f"Ovens-{run_id}"
        res = await client.put(f"/api/v1/categories/{new_cat_id}", json={"name": updated_cat_name}, headers=admin_headers)
        assert res.status_code == 200
        assert res.json()["name"] == updated_cat_name

        # 7. Staff can list products and search
        res = await client.get("/api/v1/products?q=samsung", headers=staff_headers)
        assert res.status_code == 200
        search_res = res.json()
        assert len(search_res) >= 1
        assert "Samsung" in search_res[0]["name"]

        # 8. Staff cannot create product (403 Forbidden)
        res = await client.post("/api/v1/products", json={
            "name": f"Sony TV {run_id}",
            "category_id": tv_cat["id"],
            "brand": "Sony",
            "model": "KD-55X74K",
            "size_capacity": "55 inch",
            "opening_stock_qty": 5
        }, headers=staff_headers)
        assert res.status_code == 403

        # 9. Admin creates product
        res = await client.post("/api/v1/products", json={
            "name": f"Sony TV {run_id}",
            "category_id": tv_cat["id"],
            "brand": "Sony",
            "model": f"KD-{run_id}",
            "size_capacity": "55 inch",
            "sku": f"SONY-{run_id}",
            "opening_stock_qty": 5
        }, headers=admin_headers)
        assert res.status_code == 201
        created_prod = res.json()
        assert created_prod["opening_stock_qty"] == 5
        assert created_prod["current_stock_qty"] == 5
        assert created_prod["has_had_inward"] is False
        assert created_prod["out_of_stock_reminder"] is False
        assert "5 in stock" in created_prod["stock_status_label"]
        prod_id = created_prod["id"]

        # 10. Admin updates product
        res = await client.put(f"/api/v1/products/{prod_id}", json={
            "description": "4K Ultra HD Smart LED Google TV",
            "opening_stock_qty": 7
        }, headers=admin_headers)
        assert res.status_code == 200
        updated_prod = res.json()
        assert updated_prod["current_stock_qty"] == 7
        assert updated_prod["description"] == "4K Ultra HD Smart LED Google TV"

        # 11. Admin deactivates product (soft delete)
        res = await client.delete(f"/api/v1/products/{prod_id}", headers=admin_headers)
        assert res.status_code == 200
        assert res.json()["is_active"] is False

        # 12. Deactivated product does not appear in active search
        res = await client.get("/api/v1/products?is_active=true", headers=staff_headers)
        active_ids = [p["id"] for p in res.json()]
        assert prod_id not in active_ids

        # 13. Admin deactivates category
        res = await client.delete(f"/api/v1/categories/{new_cat_id}", headers=admin_headers)
        assert res.status_code == 200
        assert res.json()["is_active"] is False