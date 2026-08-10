import { RelayError, requireObject } from "./security.js";

const routePatterns = {
  rotation: /^\/v2\/registrations\/([A-Za-z0-9_-]{8,256})\/token$/,
  registration: /^\/v2\/registrations\/([A-Za-z0-9_-]{8,256})$/,
  deliveries:
    /^\/v2\/registrations\/([A-Za-z0-9_-]{8,256})\/deliveries$/,
  delegationCreation:
    /^\/v2\/registrations\/([A-Za-z0-9_-]{8,256})\/delegations$/,
  delegationRedemption:
    /^\/v2\/delegations\/([A-Za-z0-9_-]{8,256})\/redeem$/,
  delegationActivation:
    /^\/v2\/registrations\/([A-Za-z0-9_-]{8,256})\/delegations\/([A-Za-z0-9_-]{8,256})\/activate$/,
  credentialRevocation:
    /^\/v2\/registrations\/([A-Za-z0-9_-]{8,256})\/delivery-credentials\/([A-Za-z0-9_-]{8,256})$/,
};

export function createHttpHandler({ service, logger = console }) {
  return async function notificationRelayHandler(request, response) {
    const startedAt = Date.now();
    let operation = "unknown";
    try {
      response.set("Cache-Control", "no-store");
      response.set("Content-Type", "application/json; charset=utf-8");
      if (request.method === "GET" && request.path === "/health") {
        operation = "health";
        response.status(200).json({ ok: true, schemaVersion: 2 });
        return;
      }
      const rawBody = readRawBody(request);
      const context = {
        method: request.method,
        path: request.path,
        headers: request.headers,
        rawBody,
      };
      if (request.method === "POST" && request.path === "/v2/registrations") {
        operation = "registration";
        const result = await service.register(context);
        response.status(201).json(result);
        return;
      }
      const body = parseBody(rawBody);
      context.body = body;
      let match = routePatterns.rotation.exec(request.path);
      if (request.method === "PUT" && match) {
        operation = "token_rotation";
        await service.rotateToken({ ...context, deliveryHandle: match[1] });
        response.status(204).send();
        return;
      }
      match = routePatterns.registration.exec(request.path);
      if (request.method === "DELETE" && match) {
        operation = "registration_revocation";
        await service.revokeRegistration({
          ...context,
          deliveryHandle: match[1],
        });
        response.status(204).send();
        return;
      }
      match = routePatterns.delegationCreation.exec(request.path);
      if (request.method === "POST" && match) {
        operation = "delegation_creation";
        const result = await service.createDelegation({
          ...context,
          deliveryHandle: match[1],
        });
        response.status(201).json(result);
        return;
      }
      match = routePatterns.delegationRedemption.exec(request.path);
      if (request.method === "POST" && match) {
        operation = "delegation_redemption";
        const result = await service.redeemDelegation({
          delegationId: match[1],
          body,
        });
        response.status(200).json(result);
        return;
      }
      match = routePatterns.delegationActivation.exec(request.path);
      if (request.method === "POST" && match) {
        operation = "delegation_activation";
        await service.activateDelegation({
          ...context,
          deliveryHandle: match[1],
          delegationId: match[2],
        });
        response.status(204).send();
        return;
      }
      match = routePatterns.credentialRevocation.exec(request.path);
      if (request.method === "DELETE" && match) {
        operation = "credential_revocation";
        await service.revokeDeliveryCredential({
          ...context,
          deliveryHandle: match[1],
          deliveryKeyId: match[2],
        });
        response.status(204).send();
        return;
      }
      match = routePatterns.deliveries.exec(request.path);
      if (request.method === "POST" && match) {
        operation = "delivery";
        await service.deliver({ ...context, deliveryHandle: match[1] });
        response.status(202).json({ accepted: true });
        return;
      }
      throw new RelayError("not_found", 404);
    } catch (error) {
      const relayError = error instanceof RelayError
        ? error
        : new RelayError("internal_error", 500);
      const publicCode = relayError.status === 401
        ? "unauthorized"
        : relayError.code;
      response.status(relayError.status).json({ error: publicCode });
    } finally {
      logger.info?.("notification_relay_request", {
        operation,
        status: response.statusCode,
        latencyMs: Date.now() - startedAt,
      });
    }
  };
}

function readRawBody(request) {
  const raw = request.rawBody;
  const body = Buffer.isBuffer(raw)
    ? raw.toString("utf8")
    : typeof raw === "string"
      ? raw
      : request.body === undefined
        ? ""
        : JSON.stringify(request.body);
  if (Buffer.byteLength(body, "utf8") > 16 * 1024) {
    throw new RelayError("request_too_large", 413);
  }
  return body;
}

function parseBody(rawBody) {
  try {
    return requireObject(JSON.parse(rawBody || "{}"));
  } catch (error) {
    if (error instanceof RelayError) {
      throw error;
    }
    throw new RelayError("invalid_request");
  }
}
