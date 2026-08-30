import { ChannelRelay } from "./channel";
import {
  bearer,
  constantTimeEqual,
  digest,
  isPeerRole,
  json,
  randomToken,
  type ChannelProvisioning,
  type StoredChannelConfiguration,
} from "./protocol";

export { ChannelRelay };

interface Env {
  CHANNELS: DurableObjectNamespace<ChannelRelay>;
  ADMIN_TOKEN: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/healthz") {
      return json({ status: "ok", service: "eng-relay" });
    }
    if (request.method === "POST" && url.pathname === "/v1/channels") {
      return provision(request, env);
    }
    if (request.method === "DELETE" && url.pathname.startsWith("/v1/channels/")) {
      return revoke(request, env, url.pathname.slice("/v1/channels/".length));
    }
    if (request.method === "GET" && url.pathname === "/v1/connect") {
      return connect(request, env, url);
    }
    return json({ error: "not_found" }, 404);
  },
} satisfies ExportedHandler<Env>;

async function provision(request: Request, env: Env): Promise<Response> {
  if (!(await authorizedAdmin(request, env))) {
    return json({ error: "unauthorized" }, 401);
  }
  const channelID = crypto.randomUUID();
  const phoneToken = randomToken();
  const bridgeToken = randomToken();
  const createdAt = new Date().toISOString();
  const configuration: StoredChannelConfiguration = {
    phoneTokenDigest: await digest(phoneToken),
    bridgeTokenDigest: await digest(bridgeToken),
    createdAt,
  };
  const id = env.CHANNELS.idFromName(channelID);
  const response = await env.CHANNELS.get(id).fetch("https://channel/internal/configure", {
    method: "POST",
    body: JSON.stringify(configuration),
    headers: { "content-type": "application/json" },
  });
  if (!response.ok) return json({ error: "provisioning_failed" }, 500);
  const result: ChannelProvisioning = { channelID, phoneToken, bridgeToken, createdAt };
  return json(result, 201);
}

async function revoke(request: Request, env: Env, channelID: string): Promise<Response> {
  if (!(await authorizedAdmin(request, env))) return json({ error: "unauthorized" }, 401);
  if (!isUUID(channelID)) return json({ error: "invalid_channel" }, 400);
  return env.CHANNELS.get(env.CHANNELS.idFromName(channelID)).fetch(
    "https://channel/internal/revoke",
    { method: "DELETE" },
  );
}

async function authorizedAdmin(request: Request, env: Env): Promise<boolean> {
  const token = bearer(request);
  if (!token || !env.ADMIN_TOKEN || env.ADMIN_TOKEN.length < 32) return false;
  return constantTimeEqual(await digest(token), await digest(env.ADMIN_TOKEN));
}

async function connect(request: Request, env: Env, url: URL): Promise<Response> {
  const channelID = url.searchParams.get("channel");
  const role = url.searchParams.get("role");
  if (!channelID || !isPeerRole(role) || !isUUID(channelID)) {
    return json({ error: "invalid_connection" }, 400);
  }
  const target = new URL("https://channel/connect");
  target.searchParams.set("role", role);
  return env.CHANNELS.get(env.CHANNELS.idFromName(channelID)).fetch(
    new Request(target, request),
  );
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(value);
}
