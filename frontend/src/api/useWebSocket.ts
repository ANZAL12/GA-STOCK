import { useEffect, useRef } from "react";

type WsCallback = (event: string, data: any) => void;

class WebSocketManager {
  private socket: WebSocket | null = null;
  private listeners: Set<WsCallback> = new Set();
  private reconnectTimer: any = null;
  private pingTimer: any = null;

  connect() {
    if (this.socket && (this.socket.readyState === WebSocket.OPEN || this.socket.readyState === WebSocket.CONNECTING)) {
      return;
    }

    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const host = window.location.host;
    const wsUrl = `${protocol}//${host}/api/v1/ws`;

    try {
      this.socket = new WebSocket(wsUrl);

      this.socket.onopen = () => {
        // Ping every 25 seconds
        if (this.pingTimer) clearInterval(this.pingTimer);
        this.pingTimer = setInterval(() => {
          if (this.socket?.readyState === WebSocket.OPEN) {
            this.socket.send("ping");
          }
        }, 25000);
      };

      this.socket.onmessage = (e) => {
        if (e.data === "pong") return;
        try {
          const parsed = JSON.parse(e.data);
          if (parsed && parsed.event) {
            this.listeners.forEach((listener) => listener(parsed.event, parsed.data));
          }
        } catch {
          // ignore non-json
        }
      };

      this.socket.onclose = () => {
        this.scheduleReconnect();
      };

      this.socket.onerror = () => {
        if (this.socket) {
          this.socket.close();
        }
      };
    } catch {
      this.scheduleReconnect();
    }
  }

  private scheduleReconnect() {
    if (this.pingTimer) clearInterval(this.pingTimer);
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = setTimeout(() => {
      this.connect();
    }, 3000);
  }

  subscribe(callback: WsCallback) {
    this.listeners.add(callback);
    this.connect();
    return () => {
      this.listeners.delete(callback);
    };
  }
}

export const wsClient = new WebSocketManager();

export function useWebSocket(callback: WsCallback) {
  const cbRef = useRef(callback);
  cbRef.current = callback;

  useEffect(() => {
    const unsubscribe = wsClient.subscribe((event, data) => {
      cbRef.current(event, data);
    });
    return () => {
      unsubscribe();
    };
  }, []);
}
