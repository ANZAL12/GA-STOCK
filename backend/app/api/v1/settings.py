from typing import Annotated, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.api.deps import get_current_user, require_admin
from app.core.app_settings import get_app_settings, update_app_settings
from app.core.websocket_manager import ws_manager
from app.models.user import User

router = APIRouter(prefix="/settings", tags=["settings"])


class AppSettingsResponse(BaseModel):
    bill_edit_delete_enabled: bool = False


class AppSettingsUpdateRequest(BaseModel):
    bill_edit_delete_enabled: Optional[bool] = None


@router.get("", response_model=AppSettingsResponse)
async def read_app_settings(
    current_user: Annotated[User, Depends(get_current_user)],
) -> AppSettingsResponse:
    """Return runtime portal feature settings."""
    return AppSettingsResponse(**get_app_settings())


@router.patch("", response_model=AppSettingsResponse)
async def patch_app_settings(
    req: AppSettingsUpdateRequest,
    admin: Annotated[User, Depends(require_admin)],
) -> AppSettingsResponse:
    """Admin only: update runtime portal feature settings and notify connected clients."""
    updated = update_app_settings(req.model_dump(exclude_none=True))
    await ws_manager.broadcast("settings_updated", updated)
    return AppSettingsResponse(**updated)

