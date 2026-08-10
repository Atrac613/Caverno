import {
  APP_CHECK_HEADER,
  MAX_EVENT_AGE_MS,
  MAX_EVENT_FUTURE_MS,
  MAX_SIGNED_CLOCK_SKEW_MS,
  REPLAY_RETENTION_MS,
  RelayError,
  SCHEMA_VERSION,
  constantTimeEqual,
  expectedSignature,
  headerValue,
  parseSignedHeaders,
  randomToken,
  requireDigest,
  requireExactKeys,
  requireFreshTimestamp,
  requireIdentifier,
  requireObject,
  requireSchema,
  requireSecret,
  requireString,
  requireTimestamp,
} from "./security.js";

const MANAGEMENT_LIFETIME_MS = 90 * 24 * 60 * 60 * 1000;
const DELIVERY_LIFETIME_MS = 90 * 24 * 60 * 60 * 1000;
const DELEGATION_LIFETIME_MS = 5 * 60 * 1000;
const DELIVERY_RETRY_DELAYS_MS = [
  60 * 1000,
  5 * 60 * 1000,
  15 * 60 * 1000,
  60 * 60 * 1000,
];
const MAX_DELIVERY_ATTEMPTS = DELIVERY_RETRY_DELAYS_MS.length + 1;

export class RelayService {
  constructor({ store, appCheckVerifier, provider, clock = () => new Date() }) {
    this.store = store;
    this.appCheckVerifier = appCheckVerifier;
    this.provider = provider;
    this.clock = clock;
  }

  async register({ headers, body, rawBody }) {
    const appCheckToken = headerValue(headers, APP_CHECK_HEADER);
    if (!appCheckToken) {
      throw new RelayError("unauthorized", 401);
    }
    try {
      await this.appCheckVerifier.verify(appCheckToken);
    } catch {
      throw new RelayError("unauthorized", 401);
    }
    const request = parseRegistration(body ?? parseRawBody(rawBody));
    const now = this.clock();
    requireFreshTimestamp(request.requestedAt, now, MAX_SIGNED_CLOCK_SKEW_MS);
    const deliveryHandle = randomToken(24);
    const managementKeyId = randomToken(18);
    const managementSecret = randomToken(32);
    const expiresAt = new Date(now.getTime() + MANAGEMENT_LIFETIME_MS);
    await this.store.createRegistration(
      {
        deliveryHandle,
        installationId: request.installationId,
        platform: request.platform,
        fcmRegistrationToken: request.fcmRegistrationToken,
        createdAt: now.toISOString(),
        updatedAt: now.toISOString(),
        expiresAt: expiresAt.toISOString(),
        revoked: false,
      },
      {
        keyId: managementKeyId,
        deliveryHandle,
        scope: "management",
        secret: managementSecret,
        expiresAt: expiresAt.toISOString(),
        active: true,
        revoked: false,
      },
    );
    return {
      schemaVersion: SCHEMA_VERSION,
      deliveryHandle,
      managementKeyId,
      managementSecret,
      expiresAt: expiresAt.toISOString(),
    };
  }

  async rotateToken(context) {
    await this.#authenticate(context, "management");
    const request = parseTokenRotation(context.body);
    await this.store.rotateToken(
      context.deliveryHandle,
      request.fcmRegistrationToken,
      this.clock().toISOString(),
    );
  }

  async revokeRegistration(context) {
    await this.#authenticate(context, "management", { allowRevoked: true });
    parseEmptyRevocation(context.body);
    await this.store.revokeRegistration(
      context.deliveryHandle,
      this.clock().toISOString(),
    );
  }

  async createDelegation(context) {
    await this.#authenticate(context, "management");
    const request = parseDelegationCreation(context.body);
    const now = this.clock();
    requireFreshTimestamp(request.requestedAt, now, MAX_SIGNED_CLOCK_SKEW_MS);
    const expiresAt = new Date(now.getTime() + DELEGATION_LIFETIME_MS);
    const delegationId = randomToken(24);
    await this.store.createDelegation({
      delegationId,
      deliveryHandle: context.deliveryHandle,
      targetDeviceId: request.targetDeviceId,
      challengeId: request.challengeId,
      challengeDigest: request.challengeDigest,
      expiresAt: expiresAt.toISOString(),
      state: "pending",
      createdAt: now.toISOString(),
    });
    return {
      schemaVersion: SCHEMA_VERSION,
      delegationId,
      challengeId: request.challengeId,
      targetDeviceId: request.targetDeviceId,
      expiresAt: expiresAt.toISOString(),
    };
  }

  async redeemDelegation({ delegationId, body }) {
    const request = parseDelegationRedemption(body);
    const now = this.clock();
    requireFreshTimestamp(request.requestedAt, now, MAX_SIGNED_CLOCK_SKEW_MS);
    const credentialExpiresAt = new Date(now.getTime() + DELIVERY_LIFETIME_MS);
    return this.store.redeemDelegation({
      delegationId,
      ...request,
      now,
      credential: {
        keyId: randomToken(18),
        deliveryHandle: null,
        delegationId,
        scope: "delivery",
        secret: randomToken(32),
        expiresAt: credentialExpiresAt.toISOString(),
        active: false,
        revoked: false,
      },
    });
  }

  async activateDelegation(context) {
    await this.#authenticate(context, "delivery", { allowInactive: true });
    const request = parseDelegationActivation(context.body);
    if (context.signed.keyId !== request.deliveryKeyId) {
      throw new RelayError("unauthorized", 401);
    }
    const now = this.clock();
    requireFreshTimestamp(request.activatedAt, now, MAX_SIGNED_CLOCK_SKEW_MS);
    await this.store.activateDelegation(
      context.delegationId,
      request.deliveryKeyId,
      now.toISOString(),
    );
  }

  async revokeDeliveryCredential(context) {
    await this.#authenticate(context, "delivery", {
      allowInactive: true,
      allowRevoked: true,
    });
    const request = parseDeliveryCredentialRevocation(context.body);
    if (context.signed.keyId !== context.deliveryKeyId) {
      throw new RelayError("unauthorized", 401);
    }
    const now = this.clock();
    requireFreshTimestamp(request.requestedAt, now, MAX_SIGNED_CLOCK_SKEW_MS);
    await this.store.revokeDeliveryCredential(
      context.deliveryHandle,
      context.deliveryKeyId,
      now.toISOString(),
    );
  }

  async deliver(context) {
    const now = this.clock();
    await this.#authenticate(context, "delivery", { consumeReplay: false });
    const notification = parseDelivery(context.body);
    requireFreshTimestamp(
      notification.completedAt,
      now,
      MAX_EVENT_AGE_MS,
      MAX_EVENT_FUTURE_MS,
    );
    const registration = await this.store.getRegistration(
      context.deliveryHandle,
    );
    if (!registration || registration.revoked || !registration.fcmRegistrationToken) {
      throw new RelayError("not_found", 404);
    }
    const delivery = {
      eventId: notification.eventId,
      deliveryHandle: context.deliveryHandle,
      notification: notification.data,
      platform: registration.platform,
      state: "pending",
      attemptCount: 0,
      acceptedAt: now.toISOString(),
      nextAttemptAt: now.toISOString(),
    };
    await this.store.acceptDelivery({
      replay: this.#replayRecord(
        context.signed,
        notification.eventId,
        now,
        context.deliveryHandle,
      ),
      delivery,
    });
    await this.#attemptDelivery(delivery);
  }

  async retryPendingDeliveries({ limit = 100 } = {}) {
    const now = this.clock();
    const deliveries = await this.store.listPendingDeliveries(now, limit);
    for (const delivery of deliveries) {
      await this.#attemptDelivery(delivery);
    }
    return deliveries.length;
  }

  async #authenticate(
    context,
    requiredScope,
    { allowInactive = false, allowRevoked = false, consumeReplay = true } = {},
  ) {
    const signed = parseSignedHeaders(context.headers);
    context.signed = signed;
    const now = this.clock();
    const signedAt = new Date(signed.timestampSeconds * 1000);
    requireFreshTimestamp(signedAt, now, MAX_SIGNED_CLOCK_SKEW_MS);
    const credential = await this.store.getCredential(
      context.deliveryHandle,
      signed.keyId,
    );
    const registration = await this.store.getRegistration(
      context.deliveryHandle,
    );
    if (
      !credential ||
      !registration ||
      credential.scope !== requiredScope ||
      (!allowInactive && !credential.active) ||
      (!allowRevoked && credential.revoked) ||
      (!allowRevoked && registration.revoked) ||
      new Date(registration.expiresAt) <= now ||
      new Date(credential.expiresAt) <= now
    ) {
      throw new RelayError("unauthorized", 401);
    }
    const expected = expectedSignature({
      method: context.method,
      path: context.path,
      body: context.rawBody,
      keyId: signed.keyId,
      timestampSeconds: signed.timestampSeconds,
      nonce: signed.nonce,
      secret: credential.secret,
    });
    if (!constantTimeEqual(expected, signed.signature)) {
      throw new RelayError("unauthorized", 401);
    }
    if (consumeReplay) {
      await this.store.consumeReplay(this.#replayRecord(signed, null, now));
    }
  }

  #replayRecord(signed, eventId, now, deliveryHandle = null) {
    return {
      keyId: signed.keyId,
      nonce: signed.nonce,
      eventId,
      deliveryHandle,
      now,
      expiresAt: new Date(now.getTime() + REPLAY_RETENTION_MS),
    };
  }

  async #attemptDelivery(delivery) {
    const attemptStartedAt = this.clock();
    const claimed = await this.store.claimDelivery(
      delivery.deliveryHandle,
      delivery.eventId,
      attemptStartedAt,
      new Date(attemptStartedAt.getTime() + 60 * 1000).toISOString(),
    );
    if (!claimed) {
      return;
    }
    const registration = await this.store.getRegistration(
      delivery.deliveryHandle,
    );
    if (!registration || registration.revoked || !registration.fcmRegistrationToken) {
      await this.store.markDeliveryFailed(
        delivery.deliveryHandle,
        delivery.eventId,
        this.clock().toISOString(),
        "registration_unavailable",
      );
      return;
    }
    try {
      await this.provider.send({
        token: registration.fcmRegistrationToken,
        platform: registration.platform,
        data: delivery.notification,
      });
      await this.store.markDeliveryDelivered(
        delivery.deliveryHandle,
        delivery.eventId,
        this.clock().toISOString(),
      );
    } catch (error) {
      const failedAttemptCount = delivery.attemptCount + 1;
      if (error?.invalidatesToken === true) {
        await this.store.invalidateFcmToken(
          delivery.deliveryHandle,
          this.clock().toISOString(),
        );
      }
      if (
        error?.retryable === false ||
        failedAttemptCount >= MAX_DELIVERY_ATTEMPTS
      ) {
        await this.store.markDeliveryFailed(
          delivery.deliveryHandle,
          delivery.eventId,
          this.clock().toISOString(),
          error?.retryable === false
            ? "permanent_provider_rejection"
            : "retry_exhausted",
        );
        return;
      }
      const retryDelayMs = DELIVERY_RETRY_DELAYS_MS[delivery.attemptCount];
      await this.store.markDeliveryPending(
        delivery.deliveryHandle,
        delivery.eventId,
        new Date(this.clock().getTime() + retryDelayMs).toISOString(),
      );
    }
  }
}

function parseRegistration(body) {
  const value = requireObject(body);
  requireExactKeys(value, [
    "schemaVersion",
    "installationId",
    "platform",
    "fcmRegistrationToken",
    "requestedAt",
  ]);
  requireSchema(value);
  const platform = requireString(value, "platform", { maxLength: 16 });
  if (platform !== "ios" && platform !== "android") {
    throw new RelayError("invalid_request");
  }
  return {
    installationId: requireString(value, "installationId", { maxLength: 256 }),
    platform,
    fcmRegistrationToken: requireString(value, "fcmRegistrationToken", {
      maxLength: 4096,
    }),
    requestedAt: requireTimestamp(value, "requestedAt"),
  };
}

function parseRawBody(rawBody) {
  try {
    return requireObject(JSON.parse(rawBody || "{}"));
  } catch (error) {
    if (error instanceof RelayError) {
      throw error;
    }
    throw new RelayError("invalid_request");
  }
}

function parseTokenRotation(body) {
  const value = requireObject(body);
  requireExactKeys(value, ["schemaVersion", "fcmRegistrationToken"]);
  requireSchema(value);
  return {
    fcmRegistrationToken: requireString(value, "fcmRegistrationToken", {
      maxLength: 4096,
    }),
  };
}

function parseEmptyRevocation(body) {
  const value = requireObject(body);
  requireExactKeys(value, ["schemaVersion"]);
  requireSchema(value);
}

function parseDelegationCreation(body) {
  const value = requireObject(body);
  requireExactKeys(value, [
    "schemaVersion",
    "challengeId",
    "challengeDigest",
    "targetDeviceId",
    "requestedAt",
  ]);
  requireSchema(value);
  return {
    challengeId: requireIdentifier(value, "challengeId"),
    challengeDigest: requireDigest(value, "challengeDigest"),
    targetDeviceId: requireIdentifier(value, "targetDeviceId"),
    requestedAt: requireTimestamp(value, "requestedAt"),
  };
}

function parseDelegationRedemption(body) {
  const value = requireObject(body);
  requireExactKeys(value, [
    "schemaVersion",
    "challengeId",
    "challengeSecret",
    "targetDeviceId",
    "idempotencyKey",
    "requestedAt",
  ]);
  requireSchema(value);
  return {
    challengeId: requireIdentifier(value, "challengeId"),
    challengeSecret: requireSecret(value, "challengeSecret"),
    targetDeviceId: requireIdentifier(value, "targetDeviceId"),
    idempotencyKey: requireIdentifier(value, "idempotencyKey"),
    requestedAt: requireTimestamp(value, "requestedAt"),
  };
}

function parseDelegationActivation(body) {
  const value = requireObject(body);
  requireExactKeys(value, ["schemaVersion", "deliveryKeyId", "activatedAt"]);
  requireSchema(value);
  return {
    deliveryKeyId: requireIdentifier(value, "deliveryKeyId"),
    activatedAt: requireTimestamp(value, "activatedAt"),
  };
}

function parseDeliveryCredentialRevocation(body) {
  const value = requireObject(body);
  requireExactKeys(value, ["schemaVersion", "requestedAt"]);
  requireSchema(value);
  return { requestedAt: requireTimestamp(value, "requestedAt") };
}

function parseDelivery(body) {
  const value = requireObject(body);
  requireExactKeys(value, ["schemaVersion", "notification"]);
  requireSchema(value);
  const data = requireObject(value.notification);
  requireExactKeys(data, [
    "kind",
    "schemaVersion",
    "eventId",
    "turnId",
    "conversationId",
    "outcome",
    "title",
    "body",
    "completedAt",
  ]);
  if (
    requireString(data, "kind", { maxLength: 64 }) !==
      "remote_coding_run_terminal" ||
    requireString(data, "schemaVersion", { maxLength: 4 }) !== "1"
  ) {
    throw new RelayError("invalid_request");
  }
  const outcome = requireString(data, "outcome", { maxLength: 16 });
  if (outcome !== "completed" && outcome !== "failed") {
    throw new RelayError("invalid_request");
  }
  const normalized = {
    kind: "remote_coding_run_terminal",
    schemaVersion: "1",
    eventId: requireIdentifier(data, "eventId"),
    turnId: requireIdentifier(data, "turnId"),
    conversationId: requireIdentifier(data, "conversationId"),
    outcome,
    title: requireString(data, "title", { maxLength: 120 }),
    body: requireString(data, "body", { maxLength: 240 }),
    completedAt: requireString(data, "completedAt", { maxLength: 64 }),
  };
  return {
    eventId: normalized.eventId,
    completedAt: requireTimestamp(normalized, "completedAt"),
    data: normalized,
  };
}
