import os
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1 import api_router
from app.api.v1.websocket import router as websocket_router
from app.config import settings

app = FastAPI(
    title="Godown Management System — Global Agencies",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health endpoint for Windows Task Scheduler / NSSM monitoring
@app.get("/health", tags=["system"])
async def health() -> dict:
    return {"status": "ok"}


# Mount WebSocket directly at root /ws and also under /api/v1
app.include_router(websocket_router)
app.include_router(api_router, prefix="/api")

from starlette.exceptions import HTTPException as StarletteHTTPException

# SPA StaticFiles handler to allow page refreshes on React routes (e.g. /bills, /inventory)
class SPAStaticFiles(StaticFiles):
    async def get_response(self, path: str, scope):
        try:
            return await super().get_response(path, scope)
        except StarletteHTTPException as exc:
            req_path = scope.get("path", "")
            if exc.status_code == 404 and not req_path.startswith(("/api", "/ws", "/health", "/docs", "/redoc", "/openapi.json")):
                return await super().get_response("index.html", scope)
            raise exc

# Serve built React frontend if dist folder exists (spec §9)
frontend_dist = Path(__file__).resolve().parent.parent.parent / "frontend" / "dist"
if frontend_dist.exists() and (frontend_dist / "index.html").exists():
    app.mount("/", SPAStaticFiles(directory=str(frontend_dist), html=True), name="frontend")