export type PeerRole = "phone" | "bridge";

export interface ChannelProvisioning {
  channelID: string;
  phoneToken: string;
  bridgeToken: string;
  createdAt: string;
}

export interface StoredChannelConfiguration {
  phoneTokenDigest: string;
  bridgeTokenDigest: string;
  createdAt: string;
}

export interface SocketAttachment {
  role: PeerRole;
  connectedAt: string;
}

export const MAX_FRAME_BYTES = 2 * 1024 * 1024;

export function isPeerRole(value: string | null): value is PeerRole {
  return value === "phone" || value === "bridge";
}

export function opposite(role: PeerRole): PeerRole {
  return role === "phone" ? "bridge" : "phone";
}

export function bearer(request: Request): string | null {
  const value = request.headers.get("authorization");
  return value?.startsWith("Bearer ") ? value.slice(7) : null;
}

export function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

export function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export async function digest(token: string): Promise<string> {
  const bytes = new TextEncoder().encode(token);
  return base64URL(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}

export function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export function randomToken(): string {
  return base64(crypto.getRandomValues(new Uint8Array(32)));
}

export function json(value: unknown, status = 200): Response {
  return Response.json(value, {
    status,
    headers: {
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'",
      "x-content-type-options": "nosniff",
    },
  });
}
