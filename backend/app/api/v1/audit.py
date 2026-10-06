from datetime import date
from typing import Annotated, Optional
import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_admin
from app.database import get_db
from app.models.audit import AuditLog
from app.models.device import Device
from app.models.user import User
from app.schemas.audit import AuditLogResponse
from app.services.exporter import export_to_csv, export_to_excel
from fastapi import Response

router = APIRouter(prefix="/audit", tags=["audit"])


@router.get("")
async def list_audit_logs(
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    user_id: Optional[uuid.UUID] = Query(None, description="Filter by user"),
    action: Optional[str] = Query(None, description="Filter by action string"),
    entity_type: Optional[str] = Query(None, description="Filter by entity type (product, shop, inward_batch, etc.)"),
    date_from: Optional[date] = Query(None, description="Filter from date"),
    date_to: Optional[date] = Query(None, description="Filter to date"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    export: Optional[str] = Query(None, pattern="^(csv|xlsx)$"),
):
    """
    Admin only: query the system audit trail.
    Tracks all administrative and inventory actions with before/after details,
    user identities, and devices.
    """
    query = (
        select(
            AuditLog,
            User.full_name.label("user_name"),
            Device.label.label("device_label"),
        )
        .outerjoin(User, AuditLog.user_id == User.id)
        .outerjoin(Device, AuditLog.device_id == Device.id)
        .order_by(AuditLog.created_at.desc())
    )

    if user_id:
        query = query.where(AuditLog.user_id == user_id)
    if action:
        query = query.where(AuditLog.action == action.strip().upper())
    if entity_type:
        query = query.where(AuditLog.entity_type == entity_type.strip().lower())
    if date_from:
        query = query.where(AuditLog.created_at >= date_from)
    if date_to:
        query = query.where(AuditLog.created_at <= date_to)

    if not export:
        query = query.limit(limit).offset(offset)

    result = await db.execute(query)
    rows = result.all()

    items = []
    export_rows = []
    for log, u_name, d_label in rows:
        items.append(
            AuditLogResponse(
                id=log.id,
                created_at=log.created_at,
                user_id=log.user_id,
                user_name=u_name,
                device_id=log.device_id,
                device_label=d_label,
                action=log.action,
                entity_type=log.entity_type,
                entity_id=log.entity_id,
                details=log.details,
                ip_address=log.ip_address,
            )
        )
        if export:
            export_rows.append(
                [
                    log.created_at.strftime("%Y-%m-%d %H:%M:%S"),
                    u_name or "System",
                    log.action,
                    log.entity_type,
                    log.entity_id or "-",
                    d_label or "-",
                    str(log.details) if log.details else "-",
                ]
            )

    if export == "csv":
        headers = ["Timestamp", "User", "Action", "Entity Type", "Entity ID", "Device", "Details"]
        csv_bytes = export_to_csv(headers, export_rows)
        return Response(
            content=csv_bytes,
            media_type="text/csv",
            headers={"Content-Disposition": f"attachment; filename=audit_log_{date.today()}.csv"},
        )
    elif export == "xlsx":
        headers = ["Timestamp", "User", "Action", "Entity Type", "Entity ID", "Device", "Details"]
        xlsx_bytes = export_to_excel("Audit Log", headers, export_rows)
        return Response(
            content=xlsx_bytes,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f"attachment; filename=audit_log_{date.today()}.xlsx"},
        )

    return items