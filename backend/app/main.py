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

# Serve built React frontend if dist folder exists (spec §9)
frontend_dist = Path(__file__).resolve().parent.parent.parent / "frontend" / "dist"
if frontend_dist.exists() and (frontend_dist / "index.html").exists():
    app.mount("/", StaticFiles(directory=str(frontend_dist), html=True), name="frontend")