import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { AppleServerGateway } from "./apple.js";
import { loadConfiguration } from "./config.js";
import { OfferCodeCipher } from "./crypto.js";
import { ReferralDatabase } from "./database.js";
import { ReferralService, ReferralServiceError } from "./service.js";

const configuration = loadConfiguration();
const database = new ReferralDatabase(configuration.databasePath);
const service = new ReferralService(
  database,
  new AppleServerGateway(configuration),
  configuration,
  new OfferCodeCipher(configuration.codeEncryptionKey)
);

const server = createServer(async (request, response) => {
  try {
    await route(request, response);
  } catch (error) {
    if (error instanceof ReferralServiceError) {
      sendJSON(response, error.status, { error: error.code, message: error.message });
      return;
    }
    console.error(error);
    sendJSON(response, 500, {
      error: "internal_error",
      message: "The referral service could not complete the request"
    });
  }
});

async function route(request: IncomingMessage, response: ServerResponse): Promise<void> {
  const method = request.method ?? "GET";
  const url = new URL(request.url ?? "/", "http://localhost");
  if (method === "GET" && url.pathname === "/health") {
    sendJSON(response, 200, { status: "ok" });
    return;
  }

  if (method === "POST" && url.pathname === "/v1/admin/offer-codes/import") {
    requireAdmin(request);
    const body = await readJSON(request) as { codes?: unknown; offerIdentifier?: unknown };
    if (!Array.isArray(body.codes) || !body.codes.every((value) => typeof value === "string") ||
        typeof body.offerIdentifier !== "string") {
      throw new ReferralServiceError("invalid_request", "A string code list and offer identifier are required", 400);
    }
    const imported = service.importFirstRewardCodes(body.codes, body.offerIdentifier);
    sendJSON(response, 200, { imported });
    return;
  }

  const identity = authenticateRequest(request);
  if (method === "POST" && url.pathname === "/v1/referrals/invite") {
    sendJSON(response, 200, service.createInvite(identity));
    return;
  }
  if (method === "POST" && url.pathname === "/v1/referrals/accept") {
    const body = await readJSON(request) as { code?: unknown };
    if (typeof body.code !== "string") {
      throw new ReferralServiceError("invalid_request", "A valid referral code is required", 400);
    }
    sendJSON(response, 200, service.acceptInvite(identity, body.code));
    return;
  }
  if (method === "POST" && url.pathname === "/v1/transactions/verify") {
    const body = await readJSON(request) as {
      signedTransaction?: unknown;
      referralCode?: unknown;
    };
    if (typeof body.signedTransaction !== "string") {
      throw new ReferralServiceError("invalid_request", "A signed App Store transaction is required", 400);
    }
    const result = await service.verifyTransaction(
      identity,
      body.signedTransaction,
      typeof body.referralCode === "string" ? body.referralCode : undefined
    );
    sendJSON(response, 200, result);
    return;
  }
  if (method === "GET" && url.pathname === "/v1/referrals/status") {
    sendJSON(response, 200, service.status(identity));
    return;
  }
  if (method === "POST" && url.pathname === "/v1/rewards/claim") {
    sendJSON(response, 200, await service.claimReward(identity));
    return;
  }
  sendJSON(response, 404, { error: "not_found", message: "Route not found" });
}

function authenticateRequest(request: IncomingMessage): {
  appAccountToken: string;
  credential: string;
} {
  const appAccountToken = request.headers["x-speakit-app-account-token"];
  const authorization = request.headers.authorization;
  if (typeof appAccountToken !== "string" || !authorization?.startsWith("Bearer ")) {
    throw new ReferralServiceError("unauthorized", "Referral authentication is required", 401);
  }
  return { appAccountToken, credential: authorization.slice("Bearer ".length) };
}

function requireAdmin(request: IncomingMessage): void {
  const supplied = request.headers.authorization?.replace(/^Bearer /, "") ?? "";
  const actual = Buffer.from(supplied);
  const expected = Buffer.from(configuration.adminToken);
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    throw new ReferralServiceError("unauthorized", "Administrator authentication is required", 401);
  }
}

async function readJSON(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let byteCount = 0;
  for await (const chunk of request) {
    const buffer = Buffer.from(chunk);
    byteCount += buffer.length;
    if (byteCount > 1_000_000) {
      throw new ReferralServiceError("request_too_large", "The request is too large", 413);
    }
    chunks.push(buffer);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
  } catch {
    throw new ReferralServiceError("invalid_json", "The request body must be valid JSON", 400);
  }
}

function sendJSON(response: ServerResponse, status: number, value: unknown): void {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains"
  });
  response.end(body);
}

server.listen(configuration.port, configuration.host, () => {
  console.log(`Speak It referral service listening on ${configuration.host}:${configuration.port}`);
});

function shutdown(): void {
  server.close(() => {
    database.close();
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
