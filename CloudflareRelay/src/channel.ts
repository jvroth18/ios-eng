import { DurableObject } from "cloudflare:workers";
import {
  MAX_FRAME_BYTES,
  bearer,
  digest,
  constantTimeEqual,
  isPeerRole,
  json,
  opposite,
  type SocketAttachment,
  type StoredChannelConfiguration,
} from "./protocol";

interface Env {
  CHANNELS: DurableObjectNamespace<ChannelRelay>;
  ADMIN_TOKEN: string;
}

export class ChannelRelay extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/internal/configure") {
      return this.configure(request);
    }
    if (request.method === "DELETE" && url.pathname === "/internal/revoke") {
      for (const socket of this.ctx.getWebSockets()) socket.close(4003, "Channel revoked");
      await this.ctx.storage.deleteAll();
      return json({ revoked: true });
    }
    if (request.method !== "GET" || url.pathname !== "/connect") {
      return json({ error: "not_found" }, 404);
    }
    return this.acceptConnection(request, url);
  }

  async webSocketMessage(socket: WebSocket, message: ArrayBuffer | string): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (!attachment || typeof message === "string") {
      socket.close(1003, "Binary frames only");
      return;
    }
    if (message.byteLength === 0 || message.byteLength > MAX_FRAME_BYTES) {
      socket.close(1009, "Frame exceeds limit");
      return;
    }
    const recipients = this.ctx.getWebSockets(opposite(attachment.role));
    if (recipients.length === 0) {
      socket.send(JSON.stringify({ type: "relay.peer_unavailable" }));
      return;
    }
    for (const recipient of recipients) recipient.send(message);
  }

  async webSocketClose(
    socket: WebSocket,
    code: number,
    reason: string,
    wasClean: boolean,
  ): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment) this.notify(opposite(attachment.role), false);
    socket.close(code, reason);
    void wasClean;
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as SocketAttachment | null;
    if (attachment) this.notify(opposite(attachment.role), false);
    socket.close(1011, "Relay socket error");
  }

  private async configure(request: Request): Promise<Response> {
    const existing = await this.ctx.storage.get<StoredChannelConfiguration>("configuration");
    if (existing) return json({ error: "already_configured" }, 409);
    const configuration = await request.json<StoredChannelConfiguration>();
    if (
      !configuration.phoneTokenDigest ||
      !configuration.bridgeTokenDigest ||
      configuration.phoneTokenDigest === configuration.bridgeTokenDigest
    ) {
      return json({ error: "invalid_configuration" }, 400);
    }
    await this.ctx.storage.put("configuration", configuration);
    return json({ configured: true }, 201);
  }

  private async acceptConnection(request: Request, url: URL): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return json({ error: "upgrade_required" }, 426);
    }
    const roleValue = url.searchParams.get("role");
    const token = bearer(request);
    const configuration = await this.ctx.storage.get<StoredChannelConfiguration>("configuration");
    if (!isPeerRole(roleValue) || !token || !configuration) {
      return json({ error: "unauthorized" }, 401);
    }
    const expected = roleValue === "phone"
      ? configuration.phoneTokenDigest
      : configuration.bridgeTokenDigest;
    if (!constantTimeEqual(await digest(token), expected)) {
      return json({ error: "unauthorized" }, 401);
    }

    for (const existing of this.ctx.getWebSockets(roleValue)) {
      existing.close(4001, "Replaced by a newer connection");
    }
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    const attachment: SocketAttachment = { role: roleValue, connectedAt: new Date().toISOString() };
    server.serializeAttachment(attachment);
    this.ctx.acceptWebSocket(server, [roleValue]);
    const peerConnected = this.ctx.getWebSockets(opposite(roleValue)).length > 0;
    server.send(JSON.stringify({ type: "relay.ready", peerConnected }));
    this.notify(opposite(roleValue), true);
    return new Response(null, { status: 101, webSocket: client });
  }

  private notify(role: "phone" | "bridge", connected: boolean): void {
    for (const socket of this.ctx.getWebSockets(role)) {
      socket.send(JSON.stringify({ type: "relay.peer", connected }));
    }
  }
}
