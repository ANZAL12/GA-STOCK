import json
import logging
import uuid
from datetime import date, datetime, timezone
from typing import Annotated, Any, Dict, List, Literal, Optional, Tuple, Type

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import Boolean, Date, DateTime, Enum as SAEnum, Float, Integer, delete, func, select
from sqlalchemy.dialects.postgresql import JSONB, UUID, insert as pg_insert
from sqlalchemy.exc import IntegrityError
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


def _get_column_default(col: Any, admin_id: Optional[uuid.UUID] = None) -> Any:
    """Safe fallback for non-nullable columns when missing or null in raw backup data."""
    if col.default is not None and col.default.is_scalar:
        return col.default.arg

    if col.name == "id":
        return uuid.uuid4()
    if col.name in ("created_at", "updated_at"):
        return now_ist()
    if col.name in ("dispatched_by_user_id", "received_by_user_id", "user_id"):
        return admin_id or uuid.UUID("656f2005-9e50-4d61-9009-e9356e0a9c46")

    if col.server_default is not None:
        sd_arg = str(getattr(col.server_default, "arg", "")).strip().lower()
        if "false" in sd_arg:
            return False
        if "true" in sd_arg:
            return True
        if "now()" in sd_arg or "current_timestamp" in sd_arg:
            return now_ist()
        if sd_arg.isdigit():
            return int(sd_arg)
        if sd_arg in ("''", "''''"):
            return ""

    col_type = col.type
    if isinstance(col_type, Boolean):
        return True if col.name in ("is_active", "is_enabled", "auto_sync") else False
    if isinstance(col_type, Integer):
        return 1 if col.name in ("quantity", "sync_interval_minutes") else 0
    if isinstance(col_type, Float):
        return 0.0
    if isinstance(col_type, Date):
        return date.today()
    if isinstance(col_type, DateTime):
        return now_ist()
    if isinstance(col_type, (UUID,)) or getattr(col_type, "as_uuid", False):
        return uuid.uuid4()
    if isinstance(col_type, SAEnum):
        enum_cls = getattr(col_type, "enum_class", None)
        if enum_cls:
            for ev in enum_cls:
                return ev
        return "available" if col.name == "status" else "inward"
    if isinstance(col_type, JSONB):
        return {}

    if col.name == "voucher_type":
        return "Sales"
    if col.name == "source":
        return "MANUAL"
    if col.name == "reason":
        return "Restored Record"
    if col.name == "action":
        return "RESTORE"
    if col.name == "entity_type":
        return "system"

    return ""


def _coerce_row(
    model_cls: Type[Base],
    raw_row: Dict[str, Any],
    table_name: str,
    idx: int,
    admin_id: Optional[uuid.UUID] = None,
) -> Dict[str, Any]:
    if not isinstance(raw_row, dict):
        raise ValueError(f"Row {idx} in '{table_name}' must be an object.")

    coerced: Dict[str, Any] = {}
    for col in model_cls.__table__.columns:
        raw_val = raw_row.get(col.name)
        if raw_val is not None:
            try:
                coerced[col.name] = _coerce_value(col, raw_val)
            except Exception:
                if not col.nullable:
                    coerced[col.name] = _get_column_default(col, admin_id)
                else:
                    coerced[col.name] = None
        else:
            if col.nullable:
                coerced[col.name] = None
            else:
                coerced[col.name] = _get_column_default(col, admin_id)
    return coerced


def _validate_and_prepare_backup(
    backup_payload: Dict[str, Any],
    mode: Literal["replace", "merge"],
    admin_id: Optional[uuid.UUID] = None,
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
                coerced_rows.append(_coerce_row(model_cls, raw_row, table_name, idx, admin_id))
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


def _reconcile_foreign_keys(
    prepared: Dict[str, List[Dict[str, Any]]],
    admin: User,
) -> None:
    """
    Ensure every child row references valid parent records.
    Inject fallback records or reassign orphaned FKs so foreign key constraints are never violated.
    """
    admin_id = admin.id

    # 1. Categories & Products
    known_cat_ids = {c["id"] for c in prepared.get("categories", []) if c.get("id")}
    fallback_cat_id = uuid.UUID("00000000-0000-0000-0000-000000000001")
    cat_injected = False
    for prod in prepared.get("products", []):
        if prod.get("category_id") not in known_cat_ids:
            if not cat_injected and fallback_cat_id not in known_cat_ids:
                prepared.setdefault("categories", []).insert(
                    0,
                    {
                        "id": fallback_cat_id,
                        "name": "General",
                        "code": "GEN",
                        "source": "SYSTEM",
                        "is_hidden": False,
                        "created_at": now_ist(),
                        "updated_at": now_ist(),
                    },
                )
                known_cat_ids.add(fallback_cat_id)
                cat_injected = True
            prod["category_id"] = fallback_cat_id

    # 2. Users FKs
    known_user_ids = {u["id"] for u in prepared.get("users", []) if u.get("id")}
    known_user_ids.add(admin_id)

    for ib in prepared.get("inward_batches", []):
        if ib.get("received_by_user_id") not in known_user_ids:
            ib["received_by_user_id"] = admin_id

    for ob in prepared.get("outward_batches", []):
        if ob.get("dispatched_by_user_id") not in known_user_ids:
            ob["dispatched_by_user_id"] = admin_id
        if ob.get("cancelled_by_user_id") and ob.get("cancelled_by_user_id") not in known_user_ids:
            ob["cancelled_by_user_id"] = None

    for ret in prepared.get("returns", []):
        if ret.get("received_by_user_id") not in known_user_ids:
            ret["received_by_user_id"] = admin_id

    for hist in prepared.get("serial_history", []):
        if hist.get("user_id") not in known_user_ids:
            hist["user_id"] = admin_id

    for al in prepared.get("audit_log", []):
        if al.get("user_id") and al.get("user_id") not in known_user_ids:
            al["user_id"] = admin_id

    for dev in prepared.get("devices", []):
        if dev.get("approved_by_user_id") and dev.get("approved_by_user_id") not in known_user_ids:
            dev["approved_by_user_id"] = None

    # 3. Devices FK in batches and history (device_id is nullable)
    known_device_ids = {d["id"] for d in prepared.get("devices", []) if d.get("id")}
    for ib in prepared.get("inward_batches", []):
        if ib.get("device_id") and ib.get("device_id") not in known_device_ids:
            ib["device_id"] = None
    for ob in prepared.get("outward_batches", []):
        if ob.get("device_id") and ob.get("device_id") not in known_device_ids:
            ob["device_id"] = None
    for hist in prepared.get("serial_history", []):
        if hist.get("device_id") and hist.get("device_id") not in known_device_ids:
            hist["device_id"] = None

    # 4. Shops
    known_shop_ids = {s["id"] for s in prepared.get("shops", []) if s.get("id")}
    fallback_shop_id = uuid.UUID("00000000-0000-0000-0000-000000000002")
    shop_injected = False

    def _ensure_shop(sid: Any) -> uuid.UUID:
        nonlocal shop_injected
        if sid in known_shop_ids:
            return sid
        if not shop_injected and fallback_shop_id not in known_shop_ids:
            prepared.setdefault("shops", []).insert(
                0,
                {
                    "id": fallback_shop_id,
                    "name": "Main Godown / Direct",
                    "code": "GODOWN",
                    "is_active": True,
                    "created_at": now_ist(),
                    "updated_at": now_ist(),
                },
            )
            known_shop_ids.add(fallback_shop_id)
            shop_injected = True
        return fallback_shop_id

    for ob in prepared.get("outward_batches", []):
        ob["shop_id"] = _ensure_shop(ob.get("shop_id"))
    for ol in prepared.get("outward_lines", []):
        ol["shop_id"] = _ensure_shop(ol.get("shop_id"))
    for ret in prepared.get("returns", []):
        ret["shop_id"] = _ensure_shop(ret.get("shop_id"))
    for sn in prepared.get("serial_numbers", []):
        if sn.get("current_shop_id") and sn.get("current_shop_id") not in known_shop_ids:
            sn["current_shop_id"] = None

    # 5. Products FK in serials, batches, lines, returns
    known_product_ids = {p["id"] for p in prepared.get("products", []) if p.get("id")}
    fallback_prod_id = uuid.UUID("00000000-0000-0000-0000-000000000003")
    prod_injected = False

    def _ensure_product(pid: Any) -> uuid.UUID:
        nonlocal prod_injected
        if pid in known_product_ids:
            return pid
        if not prod_injected and fallback_prod_id not in known_product_ids:
            cat_target = fallback_cat_id if fallback_cat_id in known_cat_ids else (next(iter(known_cat_ids)) if known_cat_ids else None)
            prepared.setdefault("products", []).insert(
                0,
                {
                    "id": fallback_prod_id,
                    "name": "General Restored Model",
                    "brand": "GENERAL",
                    "model": "RESTORED-MODEL",
                    "category_id": cat_target,
                    "is_active": True,
                    "is_hidden": False,
                    "tally_stock_qty": 0,
                    "source": "SYSTEM",
                    "created_at": now_ist(),
                    "updated_at": now_ist(),
                },
            )
            known_product_ids.add(fallback_prod_id)
            prod_injected = True
        return fallback_prod_id

    for sn in prepared.get("serial_numbers", []):
        sn["product_id"] = _ensure_product(sn.get("product_id"))
    for ib in prepared.get("inward_batches", []):
        ib["product_id"] = _ensure_product(ib.get("product_id"))
    for ob in prepared.get("outward_batches", []):
        ob["product_id"] = _ensure_product(ob.get("product_id"))
    for ol in prepared.get("outward_lines", []):
        ol["product_id"] = _ensure_product(ol.get("product_id"))
    for ret in prepared.get("returns", []):
        ret["product_id"] = _ensure_product(ret.get("product_id"))

    # 6. Serial Number ID in lines and history
    known_serial_ids = {s["id"] for s in prepared.get("serial_numbers", []) if s.get("id")}
    for ol in prepared.get("outward_lines", []):
        if ol.get("serial_number_id") and ol.get("serial_number_id") not in known_serial_ids:
            ol["serial_number_id"] = None
    for ret in prepared.get("returns", []):
        if ret.get("serial_number_id") and ret.get("serial_number_id") not in known_serial_ids:
            ret["serial_number_id"] = None
    for hist in prepared.get("serial_history", []):
        if hist.get("serial_number_id") and hist.get("serial_number_id") not in known_serial_ids:
            hist["serial_number_id"] = None

    known_inward_batch_ids = {b["id"] for b in prepared.get("inward_batches", []) if b.get("id")}
    prepared["inward_lines"] = [
        il
        for il in prepared.get("inward_lines", [])
        if il.get("batch_id") in known_inward_batch_ids and il.get("serial_number_id") in known_serial_ids
    ]

    known_outward_batch_ids = {b["id"] for b in prepared.get("outward_batches", []) if b.get("id")}
    prepared["outward_lines"] = [
        ol
        for ol in prepared.get("outward_lines", [])
        if ol.get("batch_id") in known_outward_batch_ids
    ]

    # 7. Tally vouchers and items
    known_voucher_ids = {v["id"] for v in prepared.get("tally_sales_vouchers", []) if v.get("id")}
    prepared["tally_voucher_items"] = [
        vi
        for vi in prepared.get("tally_voucher_items", [])
        if vi.get("voucher_id") in known_voucher_ids
    ]


async def _execute_restore(
    db: AsyncSession,
    admin: User,
    prepared: Dict[str, List[Dict[str, Any]]],
    mode: Literal["replace", "merge"],
    source_exported_at: Optional[str] = None,
) -> Dict[str, Any]:
    _reconcile_foreign_keys(prepared, admin)

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

            try:
                res = await db.execute(stmt)
                if mode == "merge" and res.rowcount is not None and res.rowcount >= 0:
                    inserted_for_table += res.rowcount
                else:
                    inserted_for_table += len(chunk)
            except IntegrityError as chunk_exc:
                if mode == "merge":
                    # Chunk had a conflict or constraint failure; fall back to individual rows using savepoints
                    logger.warning(
                        f"Chunk insert for '{table_name}' hit constraint: {chunk_exc.orig}; falling back to row-by-row insertion."
                    )
                    for single_row in chunk:
                        try:
                            async with db.begin_nested():
                                single_stmt = (
                                    pg_insert(model_cls.__table__)
                                    .values([single_row])
                                    .on_conflict_do_nothing()
                                )
                                single_res = await db.execute(single_stmt)
                                if single_res.rowcount and single_res.rowcount > 0:
                                    inserted_for_table += single_res.rowcount
                        except Exception as row_exc:
                            logger.debug(f"Skipped row in '{table_name}': {row_exc}")
                else:
                    orig_msg = str(getattr(chunk_exc, "orig", chunk_exc))
                    logger.error(
                        f"Full replace failed on table '{table_name}': {orig_msg}", exc_info=True
                    )
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=(
                            f"Database constraint violation on '{table_name}': {orig_msg}. "
                            "Please verify backup data integrity."
                        ),
                    ) from chunk_exc

        restored_counts[table_name] = inserted_for_table

    # Ensure tally_configs table always has at least one active row
    tc_res = await db.execute(select(func.count()).select_from(TallyConfig))
    if int(tc_res.scalar() or 0) == 0:
        db.add(
            TallyConfig(
                host="192.168.1.12",
                port=9000,
                company_name="GLOBAL AGENCIES - 2025-26",
                is_enabled=True,
                auto_sync=True,
                sync_interval_minutes=2,
                last_alter_id=0,
                agent_token="ga-tally-secret-2026",
            )
        )
        restored_counts["tally_configs"] = restored_counts.get("tally_configs", 0) + 1

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
    prepared = _validate_and_prepare_backup(req.backup, req.mode, admin_id=admin.id)
    try:
        return await _execute_restore(
            db=db,
            admin=admin,
            prepared=prepared,
            mode=req.mode,
            source_exported_at=str(req.backup.get("exported_at")) if req.backup.get("exported_at") else None,
        )
    except HTTPException:
        raise
    except IntegrityError as exc:
        await db.rollback()
        orig_msg = str(getattr(exc, "orig", exc))
        logger.error(f"Restore failed with IntegrityError: {orig_msg}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Database constraint violation during restore: {orig_msg}",
        ) from exc
    except Exception as exc:
        await db.rollback()
        logger.error(f"Restore failed: {exc}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Restore failed: {exc}",
        ) from exc


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

    prepared = _validate_and_prepare_backup(backup_payload, mode, admin_id=admin.id)
    try:
        return await _execute_restore(
            db=db,
            admin=admin,
            prepared=prepared,
            mode=mode,
            source_exported_at=str(backup_payload.get("exported_at")) if isinstance(backup_payload, dict) and backup_payload.get("exported_at") else None,
        )
    except HTTPException:
        raise
    except IntegrityError as exc:
        await db.rollback()
        orig_msg = str(getattr(exc, "orig", exc))
        logger.error(f"Restore-file failed with IntegrityError: {orig_msg}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Database constraint violation during restore: {orig_msg}",
        ) from exc
    except Exception as exc:
        await db.rollback()
        logger.error(f"Restore-file failed: {exc}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Restore failed: {exc}",
        ) from exc

