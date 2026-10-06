import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app


@pytest.mark.asyncio
async def test_users_and_audit_flow():
    run_id = uuid.uuid4().hex[:6]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Login as Staff
        staff_res = await client.post("/api/v1/auth/login", json={"username": "staff_test", "password": "Staff@12345"})
        assert staff_res.status_code == 200
        staff_headers = {"Authorization": f"Bearer {staff_res.json()['access_token']}"}

        # 2. Login as Admin
        admin_res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "Admin@12345"})
        assert admin_res.status_code == 200
        admin_data = admin_res.json()
        admin_headers = {"Authorization": f"Bearer {admin_data['access_token']}"}
        admin_id = admin_data["user"]["id"]

        # 3. Staff cannot access user management (403 Forbidden)
        res = await client.get("/api/v1/users", headers=staff_headers)
        assert res.status_code == 403

        # 4. Staff cannot access audit log (403 Forbidden)
        res = await client.get("/api/v1/audit", headers=staff_headers)
        assert res.status_code == 403

        # 5. Admin lists users
        res = await client.get("/api/v1/users", headers=admin_headers)
        assert res.status_code == 200
        users_list = res.json()
        assert len(users_list) >= 2  # admin + staff_test

        # 6. Admin creates a new staff user
        staff_username = f"worker_{run_id}"
        create_res = await client.post(
            "/api/v1/users",
            json={
                "username": staff_username,
                "full_name": "Godown Assistant",
                "password": "WorkerPass123!",
                "role": "staff",
            },
            headers=admin_headers,
        )
        assert create_res.status_code == 201
        new_staff = create_res.json()
        assert new_staff["username"] == staff_username
        assert new_staff["role"] == "staff"
        assert new_staff["is_active"] is True
        worker_id = new_staff["id"]

        # 7. Duplicate username rejected (400)
        dup_res = await client.post(
            "/api/v1/users",
            json={
                "username": staff_username,
                "full_name": "Another Worker",
                "password": "WorkerPass123!",
                "role": "staff",
            },
            headers=admin_headers,
        )
        assert dup_res.status_code == 400

        # 8. Admin updates staff user
        upd_res = await client.put(
            f"/api/v1/users/{worker_id}",
            json={"full_name": "Senior Godown Assistant"},
            headers=admin_headers,
        )
        assert upd_res.status_code == 200
        assert upd_res.json()["full_name"] == "Senior Godown Assistant"

        # 9. Admin deactivates staff user
        deact_res = await client.delete(f"/api/v1/users/{worker_id}", headers=admin_headers)
        assert deact_res.status_code == 200
        assert deact_res.json()["is_active"] is False

        # 10. Admin cannot deactivate own administrator account
        self_deact_res = await client.delete(f"/api/v1/users/{admin_id}", headers=admin_headers)
        assert self_deact_res.status_code == 400
        assert "cannot deactivate your own" in self_deact_res.json()["detail"].lower()

        # 11. Query audit log
        audit_res = await client.get("/api/v1/audit?action=USER_CREATED", headers=admin_headers)
        assert audit_res.status_code == 200
        audit_records = audit_res.json()
        assert len(audit_records) >= 1
        assert any(r["entity_id"] == str(worker_id) for r in audit_records)

        # 12. Export audit log to CSV
        csv_audit = await client.get("/api/v1/audit?export=csv", headers=admin_headers)
        assert csv_audit.status_code == 200
        assert "text/csv" in csv_audit.headers["content-type"]
        assert len(csv_audit.content) > 100