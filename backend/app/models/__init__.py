# Import every model here so Alembic autogenerate can discover the full metadata.
from app.models.base import Base
from app.models.enums import UserRole, SerialStatus, HistoryAction, InspectionResult
from app.models.user import User
from app.models.device import Device
from app.models.category import Category
from app.models.shop import Shop
from app.models.product import Product
from app.models.serial import SerialNumber
from app.models.inward import InwardBatch, InwardLine
from app.models.outward import OutwardBatch, OutwardLine
from app.models.return_ import Return
from app.models.history import SerialHistory
from app.models.audit import AuditLog

__all__ = [
    "Base",
    "UserRole", "SerialStatus", "HistoryAction", "InspectionResult",
    "User", "Device", "Category", "Shop", "Product",
    "SerialNumber",
    "InwardBatch", "InwardLine",
    "OutwardBatch", "OutwardLine",
    "Return",
    "SerialHistory",
    "AuditLog",
]
