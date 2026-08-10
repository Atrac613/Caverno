import assert from "node:assert/strict";
import test from "node:test";

import { createHttpHandler } from "../src/http_handler.js";
import { MemoryRelayStore } from "../src/memory_store.js";
import { RelayService } from "../src/relay_service.js";

test("HTTP registration verifies App Check before parsing a malformed body", async () => {
  const logs = [];
  const handler = createHttpHandler({
    service: testService(),
    logger: { info: (...values) => logs.push(values) },
  });
  const response = responseRecorder();

  await handler(
    {
      method: "POST",
      path: "/v2/registrations",
      headers: {},
      rawBody: Buffer.from("{private-malformed-body", "utf8"),
    },
    response,
  );

  assert.equal(response.statusCode, 401);
  assert.deepEqual(response.jsonBody, { error: "unauthorized" });
  assert.doesNotMatch(JSON.stringify(logs), /private-malformed-body/);
});

test("HTTP registration returns only the management credential", async () => {
  const logs = [];
  const handler = createHttpHandler({
    service: testService(),
    logger: { info: (...values) => logs.push(values) },
  });
  const response = responseRecorder();
  const requestBody = {
    schemaVersion: 2,
    installationId: "installation-sensitive-123",
    platform: "ios",
    fcmRegistrationToken: "fcm-sensitive-token",
    requestedAt: "2026-08-10T12:00:00.000Z",
  };

  await handler(
    {
      method: "POST",
      path: "/v2/registrations",
      headers: { "x-firebase-appcheck": "valid-app-check-token" },
      rawBody: Buffer.from(JSON.stringify(requestBody), "utf8"),
    },
    response,
  );

  assert.equal(response.statusCode, 201);
  assert.equal(response.jsonBody.schemaVersion, 2);
  assert.ok(response.jsonBody.managementSecret);
  assert.equal(response.jsonBody.deliverySecret, undefined);
  const serializedLogs = JSON.stringify(logs);
  assert.doesNotMatch(serializedLogs, /installation-sensitive-123/);
  assert.doesNotMatch(serializedLogs, /fcm-sensitive-token/);
  assert.doesNotMatch(serializedLogs, /valid-app-check-token/);
});

function testService() {
  return new RelayService({
    store: new MemoryRelayStore(),
    appCheckVerifier: {
      async verify(token) {
        if (token !== "valid-app-check-token") {
          throw new Error("invalid token");
        }
      },
    },
    provider: { async send() {} },
    clock: () => new Date("2026-08-10T12:00:00.000Z"),
  });
}

function responseRecorder() {
  return {
    statusCode: 200,
    headers: {},
    jsonBody: null,
    set(name, value) {
      this.headers[name] = value;
      return this;
    },
    status(value) {
      this.statusCode = value;
      return this;
    },
    json(value) {
      this.jsonBody = value;
      return this;
    },
    send() {
      return this;
    },
  };
}
