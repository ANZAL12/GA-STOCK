import logging
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.core.websocket_manager import ws_manager

logger = logging.getLogger("ga.websocket")
router = APIRouter(tags=["websocket"])


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    """
    Real-time push notification stream for Godown mobile scanners and Web Dashboard.
    Pushes instant updates when models are created, stock counts change, or dispatches occur.
    """
    await ws_manager.connect(websocket)
    try:
        # Keep connection open and respond to client heartbeats
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)
    except Exception as e:
        logger.warning(f"WebSocket connection error: {e}")
        ws_manager.disconnect(websocket)
