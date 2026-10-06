import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_health():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        res = await client.get("/health")
        assert res.status_code == 200
        assert res.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_auth_and_device_flow():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Login with incorrect password
        res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "WrongPassword"})
        assert res.status_code == 401

        # 2. Login with correct admin credentials (web desktop - no device header)
        res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "Admin@12345"})
        assert res.status_code == 200
        login_data = res.json()
        assert "access_token" in login_data
        assert "refresh_token" in login_data
        assert login_data["user"]["role"] == "admin"
        admin_token = login_data["access_token"]
        refresh_token = login_data["refresh_token"]

        # 3. Test /me endpoint
        headers = {"Authorization": f"Bearer {admin_token}"}
        res = await client.get("/api/v1/auth/me", headers=headers)
        assert res.status_code == 200
        assert res.json()["username"] == "admin"

        # 4. Test refresh token endpoint
        res = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
        assert res.status_code == 200
        assert "access_token" in res.json()

        # 5. Device registration (phone sends hardware UID)
        test_device_uid = "android-hw-uid-test-001"
        res = await client.post("/api/v1/devices/register", json={
            "device_uid": test_device_uid,
            "label": "Warehouse Scanner 1"
        })
        assert res.status_code == 200
        device_data = res.json()
        assert device_data["device_uid"] == test_device_uid
        assert device_data["is_active"] is False  # Pending
        device_id = device_data["id"]

        # 6. Try to login from unapproved phone -> should get 403 Forbidden!
        phone_headers = {"X-Device-Id": test_device_uid}
        res = await client.post(
            "/api/v1/auth/login",
            json={"username": "admin", "password": "Admin@12345"},
            headers=phone_headers,
        )
        assert res.status_code == 403
        assert "awaiting administrator approval" in res.json()["detail"].lower()

        # 7. Admin lists devices
        res = await client.get("/api/v1/devices", headers=headers)
        assert res.status_code == 200
        devices = res.json()
        assert any(d["device_uid"] == test_device_uid for d in devices)

        # 8. Admin approves the device
        res = await client.patch(f"/api/v1/devices/{device_id}/approve", headers=headers)
        assert res.status_code == 200
        assert res.json()["is_active"] is True

        # 9. Now login from the approved phone -> should succeed!
        res = await client.post(
            "/api/v1/auth/login",
            json={"username": "admin", "password": "Admin@12345"},
            headers=phone_headers,
        )
        assert res.status_code == 200
        assert "access_token" in res.json()

        # 10. Admin deactivates device -> phone blocked again
        res = await client.patch(f"/api/v1/devices/{device_id}/deactivate", headers=headers)
        assert res.status_code == 200
        assert res.json()["is_active"] is False

        res = await client.post(
            "/api/v1/auth/login",
            json={"username": "admin", "password": "Admin@12345"},
            headers=phone_headers,
        )
        assert res.status_code == 403