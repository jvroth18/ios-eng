import { chmod, mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const [baseURLValue, outputValue = "./provisioned-channel"] = process.argv.slice(2);
const adminToken = process.env.ENG_RELAY_ADMIN_TOKEN;
if (!baseURLValue || !adminToken) {
  fail("Usage: ENG_RELAY_ADMIN_TOKEN=... npm run provision -- https://relay.example.com [output-directory]");
}
const baseURL = new URL(baseURLValue);
if (baseURL.protocol !== "https:" && !["localhost", "127.0.0.1", "::1"].includes(baseURL.hostname)) {
  fail("The relay URL must use HTTPS outside loopback development.");
}
const response = await fetch(new URL("/v1/channels", baseURL), {
  method: "POST",
  headers: { authorization: `Bearer ${adminToken}` },
});
if (!response.ok) fail(`Provisioning failed with HTTP ${response.status}.`);
const result = await response.json();
for (const key of ["channelID", "phoneToken", "bridgeToken"]) {
  if (typeof result[key] !== "string" || result[key].length === 0) fail("Relay returned an invalid credential.");
}

const output = resolve(outputValue);
await mkdir(output, { recursive: true, mode: 0o700 });
const files = [
  ["phone-channel.json", result.phoneToken],
  ["bridge-channel.json", result.bridgeToken],
];
for (const [name, token] of files) {
  const path = resolve(output, name);
  await writeFile(path, `${JSON.stringify({ relayURL: baseURL.origin, channelID: result.channelID, token }, null, 2)}\n`, { mode: 0o600 });
  await chmod(path, 0o600);
}
console.log(`Provisioned channel ${result.channelID}`);
console.log(`Phone credential: ${resolve(output, "phone-channel.json")}`);
console.log(`Bridge credential: ${resolve(output, "bridge-channel.json")}`);
console.log("Tokens were not printed. Transfer the phone credential through a trusted local path.");

function fail(message) {
  console.error(message);
  process.exit(1);
}
