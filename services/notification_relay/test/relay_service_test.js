import assert from "node:assert/strict";
import test from "node:test";

import { MemoryRelayStore } from "../src/memory_store.js";
import { RelayService } from "../src/relay_service.js";
import {
  RelayError,
  expectedSignature,
  sha256,
} from "../src/security.js";

test("full delegation lifecycle delivers once and retries provider failures", async () => {
  let now = new Date("2026-08-10T12:00:00.000Z");
  const store = new MemoryRelayStore();
  const provider = new FakeProvider();
  const appCheckVerifier = new FakeAppCheckVerifier();
  const service = new RelayService({
    store,
    provider,
    appCheckVerifier,
    clock: () => new Date(now),
  });

  const registration = await service.register({
    headers: { "x-firebase-appcheck": "valid-app-check-token" },
    body: {
      schemaVersion: 2,
      installationId: "installation-123",
      platform: "ios",
      fcmRegistrationToken: "fcm-registration-token",
      requestedAt: now.toISOString(),
    },
  });
  assert.equal(appCheckVerifier.verificationCount, 1);
  assert.equal(registration.deliverySecret, undefined);

  const challengeSecret = Buffer.alloc(32, 7).toString("base64url");
  const creationBody = {
    schemaVersion: 2,
    challengeId: "challenge_123",
    challengeDigest: sha256(challengeSecret),
    targetDeviceId: "device_123",
    requestedAt: now.toISOString(),
  };
  const delegation = await service.createDelegation(
    signedContext({
      method: "POST",
      path: `/v2/registrations/${registration.deliveryHandle}/delegations`,
      body: creationBody,
      deliveryHandle: registration.deliveryHandle,
      keyId: registration.managementKeyId,
      secret: registration.managementSecret,
      now,
      nonce: "nonce_creation_123",
    }),
  );

  const redemptionBody = {
    schemaVersion: 2,
    challengeId: "challenge_123",
    challengeSecret,
    targetDeviceId: "device_123",
    idempotencyKey: "idempotency_123",
    requestedAt: now.toISOString(),
  };
  const credential = await service.redeemDelegation({
    delegationId: delegation.delegationId,
    body: redemptionBody,
  });
  const retryCredential = await service.redeemDelegation({
    delegationId: delegation.delegationId,
    body: redemptionBody,
  });
  assert.deepEqual(retryCredential, credential);

  const activationBody = {
    schemaVersion: 2,
    deliveryKeyId: credential.deliveryKeyId,
    activatedAt: now.toISOString(),
  };
  await service.activateDelegation(
    signedContext({
      method: "POST",
      path: `/v2/registrations/${registration.deliveryHandle}/delegations/${delegation.delegationId}/activate`,
      body: activationBody,
      deliveryHandle: registration.deliveryHandle,
      delegationId: delegation.delegationId,
      keyId: credential.deliveryKeyId,
      secret: credential.deliverySecret,
      now,
      nonce: "nonce_activation_123",
    }),
  );

  provider.failuresRemaining = 1;
  const deliveryBody = terminalDeliveryBody(now);
  const deliveryContext = signedContext({
    method: "POST",
    path: `/v2/registrations/${registration.deliveryHandle}/deliveries`,
    body: deliveryBody,
    deliveryHandle: registration.deliveryHandle,
    keyId: credential.deliveryKeyId,
    secret: credential.deliverySecret,
    now,
    nonce: "nonce_delivery_123",
  });
  await service.deliver(deliveryContext);
  assert.equal(
    (await store.getDelivery(registration.deliveryHandle, "event_123456")).state,
    "pending",
  );
  assert.equal(provider.attemptCount, 1);

  await assert.rejects(
    service.deliver(
      signedContext({
        ...deliveryContext,
        body: deliveryBody,
        keyId: credential.deliveryKeyId,
        secret: credential.deliverySecret,
        now,
        nonce: "nonce_delivery_fresh",
      }),
    ),
    (error) => error instanceof RelayError && error.code === "replay",
  );

  now = new Date("2026-08-10T12:01:01.000Z");
  await Promise.all([
    service.retryPendingDeliveries(),
    service.retryPendingDeliveries(),
  ]);
  assert.equal(
    (await store.getDelivery(registration.deliveryHandle, "event_123456")).state,
    "delivered",
  );
  assert.equal(provider.attemptCount, 2);
  assert.equal(provider.messages[0].token, "fcm-registration-token");
  assert.equal(provider.messages[0].data.outcome, "completed");
});

test("the same event is delivered once to each registered device", async () => {
  const now = new Date("2026-08-10T12:00:00.000Z");
  const store = new MemoryRelayStore();
  const provider = new FakeProvider();
  const service = new RelayService({
    store,
    provider,
    appCheckVerifier: new FakeAppCheckVerifier(),
    clock: () => new Date(now),
  });
  const first = await createActiveCredential(service, now, "first");
  const second = await createActiveCredential(service, now, "second");
  const body = terminalDeliveryBody(now);

  await Promise.all([
    service.deliver(deliveryContext(first, body, now, "nonce_delivery_first")),
    service.deliver(deliveryContext(second, body, now, "nonce_delivery_second")),
  ]);

  assert.equal(provider.messages.length, 2);
  assert.ok(
    await store.getDelivery(first.registration.deliveryHandle, "event_123456"),
  );
  assert.ok(
    await store.getDelivery(second.registration.deliveryHandle, "event_123456"),
  );
  await assert.rejects(
    service.deliver(
      deliveryContext(first, body, now, "nonce_delivery_first_replay"),
    ),
    (error) => error instanceof RelayError && error.code === "replay",
  );
});

test("permanent provider rejection invalidates the token without retry", async () => {
  const fixture = await activeCredentialFixture();
  fixture.provider.nextError = Object.assign(new Error("invalid token"), {
    retryable: false,
    invalidatesToken: true,
  });

  await fixture.service.deliver(
    deliveryContext(
      fixture,
      terminalDeliveryBody(fixture.now),
      fixture.now,
      "nonce_permanent_rejection",
    ),
  );

  const delivery = await fixture.store.getDelivery(
    fixture.registration.deliveryHandle,
    "event_123456",
  );
  assert.equal(delivery.state, "failed");
  assert.equal(delivery.failureReason, "permanent_provider_rejection");
  assert.equal(
    (await fixture.store.getRegistration(fixture.registration.deliveryHandle))
      .fcmRegistrationToken,
    null,
  );
  assert.equal(await fixture.service.retryPendingDeliveries(), 0);
  assert.equal(fixture.provider.attemptCount, 1);
});

test("transient provider failures stop after five attempts", async () => {
  let now = new Date("2026-08-10T12:00:00.000Z");
  const store = new MemoryRelayStore();
  const provider = new FakeProvider();
  provider.failuresRemaining = 10;
  const service = new RelayService({
    store,
    provider,
    appCheckVerifier: new FakeAppCheckVerifier(),
    clock: () => new Date(now),
  });
  const credentialFixture = await createActiveCredential(
    service,
    now,
    "bounded_retry",
  );
  const body = terminalDeliveryBody(now);

  await service.deliver(
    deliveryContext(
      credentialFixture,
      body,
      now,
      "nonce_bounded_retry_initial",
    ),
  );
  const expectedRetryDelays = [60, 5 * 60, 15 * 60, 60 * 60];
  for (let index = 0; index < expectedRetryDelays.length; index += 1) {
    const pending = await store.getDelivery(
      credentialFixture.registration.deliveryHandle,
      "event_123456",
    );
    assert.equal(pending.state, "pending");
    assert.equal(
      new Date(pending.nextAttemptAt).getTime() - now.getTime(),
      expectedRetryDelays[index] * 1000,
    );
    now = new Date(new Date(pending.nextAttemptAt).getTime() + 1);
    await service.retryPendingDeliveries();
  }

  const failed = await store.getDelivery(
    credentialFixture.registration.deliveryHandle,
    "event_123456",
  );
  assert.equal(failed.state, "failed");
  assert.equal(failed.failureReason, "retry_exhausted");
  assert.equal(failed.attemptCount, 5);
  assert.equal(provider.attemptCount, 5);
  assert.equal(await service.retryPendingDeliveries(), 0);
});

test("registration fails closed before body processing without App Check", async () => {
  const service = new RelayService({
    store: new MemoryRelayStore(),
    provider: new FakeProvider(),
    appCheckVerifier: new FakeAppCheckVerifier(),
    clock: () => new Date("2026-08-10T12:00:00.000Z"),
  });

  await assert.rejects(
    service.register({ headers: {}, rawBody: "{malformed-sensitive-body" }),
    (error) => error instanceof RelayError && error.status === 401,
  );
});

test("delivery rejects fields outside the privacy allowlist", async () => {
  const fixture = await activeCredentialFixture();
  const body = terminalDeliveryBody(fixture.now);
  body.notification.prompt = "private prompt";

  await assert.rejects(
    fixture.service.deliver(
      signedContext({
        method: "POST",
        path: `/v2/registrations/${fixture.registration.deliveryHandle}/deliveries`,
        body,
        deliveryHandle: fixture.registration.deliveryHandle,
        keyId: fixture.credential.deliveryKeyId,
        secret: fixture.credential.deliverySecret,
        now: fixture.now,
        nonce: "nonce_private_field",
      }),
    ),
    (error) => error instanceof RelayError && error.code === "invalid_request",
  );
  assert.equal(fixture.provider.attemptCount, 0);
});

async function activeCredentialFixture() {
  const now = new Date("2026-08-10T12:00:00.000Z");
  const store = new MemoryRelayStore();
  const provider = new FakeProvider();
  const service = new RelayService({
    store,
    provider,
    appCheckVerifier: new FakeAppCheckVerifier(),
    clock: () => new Date(now),
  });
  const credentialFixture = await createActiveCredential(
    service,
    now,
    "fixture",
  );
  return { service, provider, store, now, ...credentialFixture };
}

async function createActiveCredential(service, now, suffix) {
  const registration = await service.register({
    headers: { "x-firebase-appcheck": "valid-app-check-token" },
    body: {
      schemaVersion: 2,
      installationId: `installation-${suffix}`,
      platform: "ios",
      fcmRegistrationToken: `fcm-registration-token-${suffix}`,
      requestedAt: now.toISOString(),
    },
  });
  const challengeSecret = Buffer.alloc(32, 7).toString("base64url");
  const challengeId = `challenge_${suffix}`;
  const targetDeviceId = `device_${suffix}`;
  const delegation = await service.createDelegation(
    signedContext({
      method: "POST",
      path: `/v2/registrations/${registration.deliveryHandle}/delegations`,
      body: {
        schemaVersion: 2,
        challengeId,
        challengeDigest: sha256(challengeSecret),
        targetDeviceId,
        requestedAt: now.toISOString(),
      },
      deliveryHandle: registration.deliveryHandle,
      keyId: registration.managementKeyId,
      secret: registration.managementSecret,
      now,
      nonce: `nonce_creation_${suffix}`,
    }),
  );
  const credential = await service.redeemDelegation({
    delegationId: delegation.delegationId,
    body: {
      schemaVersion: 2,
      challengeId,
      challengeSecret,
      targetDeviceId,
      idempotencyKey: `idempotency_${suffix}`,
      requestedAt: now.toISOString(),
    },
  });
  await service.activateDelegation(
    signedContext({
      method: "POST",
      path: `/v2/registrations/${registration.deliveryHandle}/delegations/${delegation.delegationId}/activate`,
      body: {
        schemaVersion: 2,
        deliveryKeyId: credential.deliveryKeyId,
        activatedAt: now.toISOString(),
      },
      deliveryHandle: registration.deliveryHandle,
      delegationId: delegation.delegationId,
      keyId: credential.deliveryKeyId,
      secret: credential.deliverySecret,
      now,
      nonce: `nonce_activation_${suffix}`,
    }),
  );
  return { registration, credential };
}

function deliveryContext(fixture, body, now, nonce) {
  return signedContext({
    method: "POST",
    path: `/v2/registrations/${fixture.registration.deliveryHandle}/deliveries`,
    body,
    deliveryHandle: fixture.registration.deliveryHandle,
    keyId: fixture.credential.deliveryKeyId,
    secret: fixture.credential.deliverySecret,
    now,
    nonce,
  });
}

function signedContext({
  method,
  path,
  body,
  deliveryHandle,
  delegationId,
  deliveryKeyId,
  keyId,
  secret,
  now,
  nonce,
}) {
  const rawBody = JSON.stringify(body);
  const timestampSeconds = Math.floor(now.getTime() / 1000);
  const signature = expectedSignature({
    method,
    path,
    body: rawBody,
    keyId,
    timestampSeconds,
    nonce,
    secret,
  });
  return {
    method,
    path,
    rawBody,
    body,
    deliveryHandle,
    delegationId,
    deliveryKeyId,
    headers: {
      "x-caverno-relay-key-id": keyId,
      "x-caverno-relay-timestamp": String(timestampSeconds),
      "x-caverno-relay-nonce": nonce,
      "x-caverno-relay-signature": signature,
    },
  };
}

function terminalDeliveryBody(now) {
  return {
    schemaVersion: 2,
    notification: {
      kind: "remote_coding_run_terminal",
      schemaVersion: "1",
      eventId: "event_123456",
      turnId: "turn_1234567",
      conversationId: "conversation_123",
      outcome: "completed",
      title: "Remote coding completed",
      body: "Your remote coding task completed.",
      completedAt: now.toISOString(),
    },
  };
}

class FakeAppCheckVerifier {
  verificationCount = 0;

  async verify(token) {
    this.verificationCount += 1;
    if (token !== "valid-app-check-token") {
      throw new Error("invalid token");
    }
  }
}

class FakeProvider {
  failuresRemaining = 0;
  attemptCount = 0;
  messages = [];
  nextError = null;

  async send(message) {
    this.attemptCount += 1;
    if (this.nextError != null) {
      const error = this.nextError;
      this.nextError = null;
      throw error;
    }
    if (this.failuresRemaining > 0) {
      this.failuresRemaining -= 1;
      throw new Error("provider unavailable");
    }
    this.messages.push(structuredClone(message));
  }
}
