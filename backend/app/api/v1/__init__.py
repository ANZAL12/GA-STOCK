from fastapi import APIRouter

from app.api.v1.audit import router as audit_router
from app.api.v1.auth import router as auth_router
from app.api.v1.categories import router as categories_router
from app.api.v1.devices import router as devices_router
from app.api.v1.inward import router as inward_router
from app.api.v1.outward import router as outward_router
from app.api.v1.products import router as products_router
from app.api.v1.reports import router as reports_router
from app.api.v1.returns import router as returns_router
from app.api.v1.serials import router as serials_router
from app.api.v1.shops import router as shops_router
from app.api.v1.users import router as users_router
from app.api.v1.websocket import router as websocket_router

api_router = APIRouter(prefix="/v1")
api_router.include_router(auth_router)
api_router.include_router(users_router)
api_router.include_router(devices_router)
api_router.include_router(categories_router)
api_router.include_router(products_router)
api_router.include_router(shops_router)
api_router.include_router(inward_router)
api_router.include_router(outward_router)
api_router.include_router(returns_router)
api_router.include_router(serials_router)
api_router.include_router(reports_router)
api_router.include_router(audit_router)
api_router.include_router(websocket_router)