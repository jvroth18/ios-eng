import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const adminToken = "test-admin-token-at-least-32-bytes";

interface Provisioning {
  channelID: string;
  phoneToken: string;
  bridgeToken: string;
}

describe("Eng Cloudflare relay", () => {
  it("exposes only a compact health response", async () => {
    const response = await SELF.fetch("https://eng.test/healthz");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok", service: "eng-relay" });
    expect(response.headers.get("cache-control")).toBe("no-store");
  });

  it("requires the admin secret and returns role-scoped one-time credentials", async () => {
    expect((await SELF.fetch("https://eng.test/v1/channels", { method: "POST" })).status)
      .toBe(401);
    const first = await provision();
    const second = await provision();
    expect(first.channelID).not.toBe(second.channelID);
    expect(first.phoneToken).not.toBe(first.bridgeToken);
    expect(first.phoneToken.length).toBeGreaterThanOrEqual(43);
    expect(first.bridgeToken.length).toBeGreaterThanOrEqual(43);
  });

  it("isolates channels and prevents a phone credential from impersonating a bridge", async () => {
    const first = await provision();
    const second = await provision();
    expect((await connect(first.channelID, "bridge", first.phoneToken)).status).toBe(401);
    expect((await connect(second.channelID, "phone", first.phoneToken)).status).toBe(401);
    expect((await connect(first.channelID, "phone", "invalid")).status).toBe(401);
  });

  it("routes binary ciphertext between paired roles without echoing it", async () => {
    const channel = await provision();
    const bridgeResponse = await connect(channel.channelID, "bridge", channel.bridgeToken);
    const phoneResponse = await connect(channel.channelID, "phone", channel.phoneToken);
    expect(bridgeResponse.status).toBe(101);
    expect(phoneResponse.status).toBe(101);
    const bridge = bridgeResponse.webSocket!;
    const phone = phoneResponse.webSocket!;
    bridge.binaryType = "arraybuffer";
    phone.binaryType = "arraybuffer";
    bridge.accept();
    phone.accept();
    await nextMessage(bridge); // relay.ready
    await nextMessage(phone); // relay.ready
    expect(await nextMessage(bridge)).toBe('{"type":"relay.peer","connected":true}');

    const received = nextMessage(bridge);
    const ciphertext = new Uint8Array([1, 7, 19, 42]).buffer;
    phone.send(ciphertext);
    const message = await received;
    expect(message).toBeInstanceOf(ArrayBuffer);
    expect(Array.from(new Uint8Array(message as ArrayBuffer))).toEqual([1, 7, 19, 42]);
    bridge.close(1000, "test complete");
    phone.close(1000, "test complete");
  });
});

async function provision(): Promise<Provisioning> {
  const response = await SELF.fetch("https://eng.test/v1/channels", {
    method: "POST",
    headers: { authorization: `Bearer ${adminToken}` },
  });
  expect(response.status).toBe(201);
  return response.json<Provisioning>();
}

function connect(channel: string, role: "phone" | "bridge", token: string): Promise<Response> {
  return SELF.fetch(`https://eng.test/v1/connect?channel=${channel}&role=${role}`, {
    headers: { authorization: `Bearer ${token}`, upgrade: "websocket" },
  });
}

function nextMessage(socket: WebSocket): Promise<ArrayBuffer | string> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Timed out waiting for relay frame")), 2_000);
    socket.addEventListener("message", (event) => {
      clearTimeout(timeout);
      resolve(event.data as ArrayBuffer | string);
    }, { once: true });
  });
}
