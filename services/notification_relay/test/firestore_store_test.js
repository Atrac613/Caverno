import assert from "node:assert/strict";
import test, { after, before } from "node:test";

import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import { FirestoreRelayStore } from "../src/firestore_store.js";
import { RelayError, sha256 } from "../src/security.js";

const projectId = process.env.GCLOUD_PROJECT || "demo-caverno-relay";
if (getApps().length === 0) {
  initializeApp({ projectId });
}
const firestore = getFirestore();
const store = new FirestoreRelayStore(firestore);
const root = firestore.collection("notificationRelayV2").doc("state");

before(async () => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "Firestore emulator is required for this test.",
  );
  await firestore.recursiveDelete(root);
});

after(async () => {
  await firestore.recursiveDelete(root);
  await firestore.terminate();
});

test("Firestore transactions atomically enforce replay and redemption", async () => {
  const now = new Date("2026-08-10T12:00:00.000Z");
  const expiresAt = new Date("2026-08-10T12:20:00.000Z");
  await store.createRegistration(
    {
      deliveryHandle: "delivery_handle_123",
      installationId: "installation_123",
      platform: "ios",
      fcmRegistrationToken: "fcm-token",
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
      expiresAt: new Date("2026-09-10T12:00:00.000Z").toISOString(),
      revoked: false,
    },
    {
      keyId: "management_key_123",
      deliveryHandle: "delivery_handle_123",
      scope: "management",
      secret: "management-secret",
      expiresAt: new Date("2026-09-10T12:00:00.000Z").toISOString(),
      active: true,
      revoked: false,
    },
  );

  const replayAttempts = await Promise.allSettled([
    store.consumeReplay({
      keyId: "management_key_123",
      nonce: "nonce_12345678",
      eventId: null,
      now,
      expiresAt,
    }),
    store.consumeReplay({
      keyId: "management_key_123",
      nonce: "nonce_12345678",
      eventId: null,
      now,
      expiresAt,
    }),
  ]);
  assert.equal(
    replayAttempts.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(
    replayAttempts.filter(
      (result) =>
        result.status === "rejected" &&
        result.reason instanceof RelayError &&
        result.reason.code === "replay",
    ).length,
    1,
  );

  const challengeSecret = Buffer.alloc(32, 3).toString("base64url");
  await store.createDelegation({
    delegationId: "delegation_123",
    deliveryHandle: "delivery_handle_123",
    targetDeviceId: "device_123456",
    challengeId: "challenge_123",
    challengeDigest: sha256(challengeSecret),
    expiresAt: new Date("2026-08-10T12:05:00.000Z").toISOString(),
    state: "pending",
    createdAt: now.toISOString(),
  });
  const commonRedemption = {
    delegationId: "delegation_123",
    challengeId: "challenge_123",
    challengeSecret,
    targetDeviceId: "device_123456",
    now,
  };
  const redemptions = await Promise.allSettled([
    store.redeemDelegation({
      ...commonRedemption,
      idempotencyKey: "idempotency_first",
      credential: deliveryCredential("delivery_key_first"),
    }),
    store.redeemDelegation({
      ...commonRedemption,
      idempotencyKey: "idempotency_second",
      credential: deliveryCredential("delivery_key_second"),
    }),
  ]);
  assert.equal(
    redemptions.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(
    redemptions.filter(
      (result) =>
        result.status === "rejected" && result.reason.code === "delegation_redeemed",
    ).length,
    1,
  );
  const accepted = redemptions.find((result) => result.status === "fulfilled");
  await assert.rejects(
    store.activateDelegation(
      "delegation_123",
      accepted.value.deliveryKeyId,
      "2026-08-10T12:05:00.000Z",
    ),
    (error) => error instanceof RelayError && error.code === "delegation_expired",
  );
});

test("delivery replay ledger and outbox are committed together", async () => {
  const now = new Date("2026-08-10T12:00:00.000Z");
  const replay = {
    keyId: "delivery_key_123",
    nonce: "delivery_nonce_123",
    eventId: "event_12345678",
    deliveryHandle: "delivery_handle_123",
    now,
    expiresAt: new Date("2026-08-10T12:20:00.000Z"),
  };
  const delivery = {
    eventId: "event_12345678",
    deliveryHandle: "delivery_handle_123",
    notification: { kind: "remote_coding_run_terminal" },
    platform: "ios",
    state: "pending",
    attemptCount: 0,
    acceptedAt: now.toISOString(),
    nextAttemptAt: now.toISOString(),
  };
  const attempts = await Promise.allSettled([
    store.acceptDelivery({ replay, delivery }),
    store.acceptDelivery({
      replay: { ...replay, nonce: "delivery_nonce_456" },
      delivery,
    }),
  ]);

  assert.equal(
    attempts.filter((result) => result.status === "fulfilled").length,
    1,
  );
  const pending = await store.listPendingDeliveries(now, 10);
  assert.equal(pending.length, 1);
  assert.equal(pending[0].eventId, "event_12345678");

  await store.acceptDelivery({
    replay: {
      ...replay,
      nonce: "delivery_nonce_second_device",
      deliveryHandle: "delivery_handle_456",
    },
    delivery: {
      ...delivery,
      deliveryHandle: "delivery_handle_456",
    },
  });
  const pendingForBothDevices = await store.listPendingDeliveries(now, 10);
  assert.equal(pendingForBothDevices.length, 2);
  assert.deepEqual(
    new Set(
      pendingForBothDevices.map((candidate) => candidate.deliveryHandle),
    ),
    new Set(["delivery_handle_123", "delivery_handle_456"]),
  );
});

function deliveryCredential(keyId) {
  return {
    keyId,
    deliveryHandle: null,
    delegationId: "delegation_123",
    scope: "delivery",
    secret: Buffer.alloc(32, 5).toString("base64url"),
    expiresAt: new Date("2026-09-10T12:00:00.000Z").toISOString(),
    active: false,
    revoked: false,
  };
}
