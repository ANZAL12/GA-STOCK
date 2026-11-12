import json
import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app


@pytest.mark.asyncio
async def test_backup_summary_export_and_restore():
    run_id = uuid.uuid4().hex[:6]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # 1. Staff cannot access backup endpoints
        staff_res = await client.post("/api/v1/auth/login", json={"username": "staff_test", "password": "Staff@12345"})
        assert staff_res.status_code == 200
        staff_headers = {"Authorization": f"Bearer {staff_res.json()['access_token']}"}

        assert (await client.get("/api/v1/backup/summary", headers=staff_headers)).status_code == 403
        assert (await client.get("/api/v1/backup/export", headers=staff_headers)).status_code == 403
        assert (
            await client.post("/api/v1/backup/restore", json={"backup": {"data": {}}, "mode": "merge"}, headers=staff_headers)
        ).status_code == 403

        # 2. Admin logs in
        admin_res = await client.post("/api/v1/auth/login", json={"username": "admin", "password": "Admin@12345"})
        assert admin_res.status_code == 200
        admin_headers = {"Authorization": f"Bearer {admin_res.json()['access_token']}"}

        # 3. Get summary
        sum_res = await client.get("/api/v1/backup/summary", headers=admin_headers)
        assert sum_res.status_code == 200
        summary = sum_res.json()
        assert "counts" in summary
        assert summary["counts"]["users"] >= 2

        # 4. Export full backup
        exp_res = await client.get("/api/v1/backup/export", headers=admin_headers)
        assert exp_res.status_code == 200
        backup = exp_res.json()
        assert backup["backup_version"] == 1
        assert "data" in backup
        assert len(backup["data"]["users"]) >= 2

        # 5. Export downloadable file attachment
        dl_res = await client.get("/api/v1/backup/export?download=true", headers=admin_headers)
        assert dl_res.status_code == 200
        assert "attachment; filename=" in dl_res.headers.get("content-disposition", "")
        dl_json = json.loads(dl_res.text)
        assert dl_json["backup_version"] == 1

        # 6. Reject invalid backup or replace-without-admin
        bad_res = await client.post(
            "/api/v1/backup/restore",
            json={"backup": {"data": {"users": []}}, "mode": "replace"},
            headers=admin_headers,
        )
        assert bad_res.status_code == 400

        # 7. Merge restore with a synthetic shop record
        new_shop_id = str(uuid.uuid4())
        merge_payload = {
            "backup_version": 1,
            "data": {
                "shops": [
                    {
                        "id": new_shop_id,
                        "name": f"Backup Test Shop {run_id}",
                        "city": "Kochi",
                        "source": "MANUAL",
                        "is_active": True,
                    }
                ]
            },
        }
        merge_res = await client.post(
            "/api/v1/backup/restore",
            json={"backup": merge_payload, "mode": "merge"},
            headers=admin_headers,
        )
        assert merge_res.status_code == 200
        assert merge_res.json()["counts"]["shops"] == 1

        # 8. Full replace restore using the earlier exported snapshot removes the synthetic shop
        replace_res = await client.post(
            "/api/v1/backup/restore",
            json={"backup": backup, "mode": "replace"},
            headers=admin_headers,
        )
        assert replace_res.status_code == 200
        assert replace_res.json()["mode"] == "replace"

        # Verify synthetic shop was removed by full replace restore
        shops_res = await client.get("/api/v1/shops", headers=admin_headers)
        assert shops_res.status_code == 200
        assert all(s["id"] != new_shop_id for s in shops_res.json())

