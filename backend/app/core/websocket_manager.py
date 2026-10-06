import json
import logging
from typing import Any, Dict, Set
from fastapi import WebSocket

logger = logging.getLogger("ga.websocket")


class ConnectionManager:
    """
    Manages active WebSocket connections from both the Web Dashboard
    and Mobile Android scanners for instant real-time synchronization.
    """

    def __init__(self) -> None:
        self.active_connections: Set[WebSocket] = set()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active_connections.add(websocket)
        logger.info(f"WebSocket client connected. Total active: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket) -> None:
        self.active_connections.discard(websocket)
        logger.info(f"WebSocket client disconnected. Total active: {len(self.active_connections)}")

    async def broadcast(self, event: str, data: Dict[str, Any]) -> None:
        """
        Broadcasts an event message to all connected clients.
        Payload format: {"event": "product_created", "data": {...}}
        """
        if not self.active_connections:
            return

        payload = json.dumps({"event": event, "data": data})
        stale_connections = []

        for connection in list(self.active_connections):
            try:
                await connection.send_text(payload)
            except Exception as e:
                logger.warning(f"Failed to send to client: {e}. Scheduling for removal.")
                stale_connections.append(connection)

        for stale in stale_connections:
            self.disconnect(stale)


# Singleton instance
ws_manager = ConnectionManager()
