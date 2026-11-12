import json
import logging
import uuid
from datetime import date, datetime, timezone
from typing import Annotated, Any, Dict, List, Literal, Optional, Tuple, Type

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import Boolean, Date, DateTime, Enum as SAEnum, Float, Integer, delete, func, select
from sqlalchemy.dialects.postgresql import JSONB, UUID, insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_admin
from app.core.timezone import now_ist
from app.core.websocket_manager import ws_manager
from app.database import get_db
from app.models.audit import AuditLog
from app.models.base import Base
from app.models.category import Category
from app.models.device import Device
from app.models.history import SerialHistory
from app.models.inward import InwardBatch, InwardLine
from app.models.outward import OutwardBatch, OutwardLine
from app.models.product import Product
from app.models.return_ import Return
from app.models.serial import SerialNumber
from app.models.shop import Shop
from app.models.tally import (
    TallyConfig,
    TallySalesVoucher,
    TallySyncHistory,
    TallyVoucherItem,
)
from app.models.user import User

logger = logging.getLogger("ga.backup")

router = APIRouter(prefix="/backup", tags=["backup"])

# Ordered strictly parent-before-child for safe FK insertion.
# Deletion for full replace runs in reverse order.
BACKUP_TABLES: List[Tuple[str, Type[Base]]] = [
    ("users", User),
    ("devices", Device),
    ("categories", Category),
    ("shops", Shop),
    ("products", Product),
    ("serial_numbers", SerialNumber),
    ("inward_batches", InwardBatch),
    ("inward_lines", InwardLine),
    ("outward_batches", OutwardBatch),
    ("outward_lines", OutwardLine),
    ("returns", Return),
    ("serial_history", SerialHistory),
    ("audit_log", AuditLog),
    ("tally_configs", TallyConfig),
    ("tally_sales_vouchers", TallySalesVoucher),
    ("tally_voucher_items", TallyVoucherItem),
    ("tally_sync_histories", TallySyncHistory),
]

TABLE_NAME_SET = {name for name, _ in BACKUP_TABLES}


class RestoreRequest(BaseModel):
    backup: Dict[str, Any]
    mode: Literal["replace", "merge"] = "replace"


def _serialize_value(val: Any) -> Any:
    if val is None:
        return None
    if isinstance(val, uuid.UUID):
        return str(val)
    if isinstance(val, datetime):
        return val.isoformat()
    if isinstance(val, date):
        return val.isoformat()
    if hasattr(val, "value"):  # Enum
        return val.value
    return val


def _serialize_row(model_cls: Type[Base], row_obj: Any) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    for col in model_cls.__table__.columns:
        out[col.name] = _serialize_value(getattr(row_obj, col.name))
    return out


def _coerce_value(col: Any, val: Any) -> Any:
    if val is None:
        return None

    col_type = col.type

    if isinstance(col_type, UUID) or getattr(col_type, "as_uuid", False):
        return val if isinstance(val, uuid.UUID) else uuid.UUID(str(val))

    if isinstance(col_type, SAEnum):
        enum_cls = getattr(col_type, "enum_class", None)
        if enum_cls is not None:
            if isinstance(val, enum_cls):
                return val
            return enum_cls(str(val))
        return str(val)

    if isinstance(col_type, DateTime):
        if isinstance(val, datetime):
            return val if val.tzinfo is not None else val.replace(tzinfo=timezone.utc)
        dt = datetime.fromisoformat(str(val).replace("Z", "+00:00"))
        return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)

    if isinstance(col_type, Date):
        if isinstance(val, date) and not isinstance(val, datetime):
            return val
        return date.fromisoformat(str(val)[:10])

    if isinstance(col_type, Boolean):
        if isinstance(val, bool):
            return val
        if isinstance(val, (int, float)):
            return bool(val)
        return str(val).strip().lower() in ("true", "1", "yes", "t", "y")

    if isinstance(col_type, Integer):
        return int(val)

    if isinstance(col_type, Float):
        return float(val)

    if isinstance(col_type, JSONB):
        if isinstance(val, str):
            return json.loads(val)
        return val

    return str(val)


def _coerce_row(model_cls: Type[Base], raw_row: Dict[str, Any], table_name: str, idx: int) -> Dict[str, Any]:
    if not isinstance(raw_row, dict):
        raise ValueError(f"Row {idx} in '{table_name}' must be an object.")

    coerced: Dict[str, Any] = {}
    for col in model_cls.__table__.columns:
        if col.name in raw_row:
            try:
                coerced[col.name] = _coerce_value(col, raw_row[col.name])
            except Exception as exc:
                raise ValueError(
                    f"Invalid value for '{table_name}.{col.name}' at row {idx}: {exc}"
                ) from exc
        else:
            if col.nullable:
                coerced[col.name] = None
            elif col.default is not None and col.default.is_scalar:
                coerced[col.name] = col.default.arg
            elif col.name in ("created_at", "updated_at"):
                coerced[col.name] = now_ist()
            elif col.name == "id":
                coerced[col.name] = uuid.uuid4()
            else:
                coerced[col.name] = None
    return coerced


def _validate_and_prepare_backup(
    backup_payload: Dict[str, Any],
    mode: Literal["replace", "merge"],
) -> Dict[str, List[Dict[str, Any]]]:
    if not isinstance(backup_payload, dict):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Backup payload must be a JSON object.",
        )

    data_section = backup_payload.get("data")
    if not isinstance(data_section, dict):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid backup format: missing 'data' object.",
        )

    matched_tables = [k for k in data_section.keys() if k in TABLE_NAME_SET]
    if not matched_tables:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid backup file: no recognized GA STOCK database tables found in 'data'.",
        )

    prepared: Dict[str, List[Dict[str, Any]]] = {}
    for table_name, model_cls in BACKUP_TABLES:
        raw_rows = data_section.get(table_name, [])
        if raw_rows is None:
            raw_rows = []
        if not isinstance(raw_rows, list):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid backup format: 'data.{table_name}' must be an array.",
            )

        coerced_rows: List[Dict[str, Any]] = []
        for idx, raw_row in enumerate(raw_rows):
            try:
                coerced_rows.append(_coerce_row(model_cls, raw_row, table_name, idx))
            except ValueError as err:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=str(err),
                ) from err
        prepared[table_name] = coerced_rows

    if mode == "replace":
        users_rows = prepared.get("users", [])
        has_active_admin = any(
            str(getattr(u.get("role"), "value", u.get("role"))).lower() == "admin"
            and bool(u.get("is_active", False))
            for u in users_rows
        )
        if not has_active_admin:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "Full Replace restore blocked: backup must contain at least one active admin user "
                    "in 'data.users' so you are not locked out."
                ),
            )

    return prepared


async def _execute_restore(
    db: AsyncSession,
    admin: User,
    prepared: Dict[str, List[Dict[str, Any]]],
    mode: Literal["replace", "merge"],
    source_exported_at: Optional[str] = None,
) -> Dict[str, Any]:
    restored_counts: Dict[str, int] = {}

    if mode == "replace":
        # Delete children before parents to satisfy all foreign key constraints
        for table_name, model_cls in reversed(BACKUP_TABLES):
            await db.execute(delete(model_cls))

    # Insert parents before children in safe batch sizes below asyncpg's 32,767 bind-param limit
    for table_name, model_cls in BACKUP_TABLES:
        rows = prepared.get(table_name, [])
        if not rows:
            restored_counts[table_name] = 0
            continue

        num_cols = max(1, len(model_cls.__table__.columns))
        chunk_size = max(50, min(500, 20000 // num_cols))

        inserted_for_table = 0
        for start in range(0, len(rows), chunk_size):
            chunk = rows[start : start + chunk_size]
            stmt = pg_insert(model_cls.__table__).values(chunk)
            if mode == "merge":
                stmt = stmt.on_conflict_do_nothing()
            res = await db.execute(stmt)
            if mode == "merge" and res.rowcount is not None and res.rowcount >= 0:
                inserted_for_table += res.rowcount
            else:
                inserted_for_table += len(chunk)

        restored_counts[table_name] = inserted_for_table

    # Check if current admin user still exists after restore so AuditLog FK is valid
    restored_user_ids = {u.get("id") for u in prepared.get("users", [])}
    audit_user_id: Optional[uuid.UUID] = None
    if mode == "merge" or admin.id in restored_user_ids:
        audit_user_id = admin.id

    db.add(
        AuditLog(
            user_id=audit_user_id,
            action="BACKUP_RESTORED",
            entity_type="system_backup",
            entity_id=mode,
            details={
                "mode": mode,
                "source_exported_at": source_exported_at,
                "restored_by": admin.username,
                "counts": restored_counts,
            },
        )
    )

    await db.commit()

    await ws_manager.broadcast(
        "backup_restored",
        {
            "mode": mode,
            "restored_at": now_ist().isoformat(),
            "total_records": sum(restored_counts.values()),
        },
    )

    return {
        "status": "success",
        "mode": mode,
        "restored_at": now_ist().isoformat(),
        "total_records": sum(restored_counts.values()),
        "counts": restored_counts,
    }


@router.get("/summary")
async def get_backup_summary(
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Dict[str, Any]:
    """Admin only: return live row counts for every table in the database."""
    counts: Dict[str, int] = {}
    for table_name, model_cls in BACKUP_TABLES:
        res = await db.execute(select(func.count()).select_from(model_cls))
        counts[table_name] = int(res.scalar() or 0)

    return {
        "generated_at": now_ist().isoformat(),
        "total_records": sum(counts.values()),
        "counts": counts,
    }


@router.get("/export")
async def export_full_backup(
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    download: bool = False,
):
    """
    Admin only: export all database tables into a versioned JSON backup snapshot.
    Pass ?download=true to receive a downloadable .json file attachment.
    """
    exported_at = now_ist()
    data: Dict[str, List[Dict[str, Any]]] = {}
    counts: Dict[str, int] = {}

    for table_name, model_cls in BACKUP_TABLES:
        cols = model_cls.__table__.columns
        order_col = cols["created_at"] if "created_at" in cols else cols["id"]
        result = await db.execute(select(model_cls).order_by(order_col.asc()))
        rows = result.scalars().all()
        serialized = [_serialize_row(model_cls, r) for r in rows]
        data[table_name] = serialized
        counts[table_name] = len(serialized)

    payload = {
        "backup_version": 1,
        "app": "GA STOCK",
        "exported_at": exported_at.isoformat(),
        "exported_by": admin.username,
        "total_records": sum(counts.values()),
        "counts": counts,
        "data": data,
    }

    db.add(
        AuditLog(
            user_id=admin.id,
            action="BACKUP_EXPORTED",
            entity_type="system_backup",
            entity_id="full",
            details={"total_records": payload["total_records"], "counts": counts},
        )
    )
    await db.commit()

    if download:
        filename = f"ga-stock-backup-{exported_at.strftime('%Y-%m-%d_%H-%M-%S')}.json"
        return Response(
            content=json.dumps(payload, indent=2),
            media_type="application/json",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"',
            },
        )

    return payload


@router.post("/restore")
async def restore_from_json_payload(
    req: RestoreRequest,
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Dict[str, Any]:
    """
    Admin only: restore all database tables from a pasted or parsed JSON backup payload.
    mode='replace' wipes existing records and restores the exact snapshot atomically.
    mode='merge' inserts only non-conflicting records while preserving existing data.
    """
    prepared = _validate_and_prepare_backup(req.backup, req.mode)
    return await _execute_restore(
        db=db,
        admin=admin,
        prepared=prepared,
        mode=req.mode,
        source_exported_at=str(req.backup.get("exported_at")) if req.backup.get("exported_at") else None,
    )


@router.post("/restore-file")
async def restore_from_uploaded_file(
    admin: Annotated[User, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    file: UploadFile = File(...),
    mode: Literal["replace", "merge"] = Form("replace"),
) -> Dict[str, Any]:
    """
    Admin only: restore database from an uploaded .json backup file.
    """
    raw_bytes = await file.read()
    try:
        backup_payload = json.loads(raw_bytes.decode("utf-8"))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid JSON backup file: {exc}",
        ) from exc

    prepared = _validate_and_prepare_backup(backup_payload, mode)
    return await _execute_restore(
        db=db,
        admin=admin,
        prepared=prepared,
        mode=mode,
        source_exported_at=str(backup_payload.get("exported_at")) if isinstance(backup_payload, dict) and backup_payload.get("exported_at") else None,
    )

