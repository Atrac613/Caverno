import { RelayError, sha256 } from "./security.js";

export class MemoryRelayStore {
  constructor() {
    this.registrations = new Map();
    this.credentials = new Map();
    this.delegations = new Map();
    this.replays = new Map();
    this.deliveries = new Map();
  }

  async createRegistration(registration, credential) {
    if (this.registrations.has(registration.deliveryHandle)) {
      throw new RelayError("conflict", 409);
    }
    this.registrations.set(registration.deliveryHandle, structuredClone(registration));
    this.credentials.set(credential.keyId, structuredClone(credential));
  }

  async getRegistration(deliveryHandle) {
    return clone(this.registrations.get(deliveryHandle));
  }

  async getCredential(deliveryHandle, keyId) {
    const credential = this.credentials.get(keyId);
    return credential?.deliveryHandle === deliveryHandle ? clone(credential) : null;
  }

  async rotateToken(deliveryHandle, fcmRegistrationToken, updatedAt) {
    const registration = this.registrations.get(deliveryHandle);
    if (!registration || registration.revoked) {
      throw new RelayError("not_found", 404);
    }
    registration.fcmRegistrationToken = fcmRegistrationToken;
    registration.updatedAt = updatedAt;
  }

  async invalidateFcmToken(deliveryHandle, updatedAt) {
    const registration = this.registrations.get(deliveryHandle);
    if (!registration) {
      return;
    }
    registration.fcmRegistrationToken = null;
    registration.updatedAt = updatedAt;
  }

  async revokeRegistration(deliveryHandle, revokedAt) {
    const registration = this.registrations.get(deliveryHandle);
    if (!registration) {
      throw new RelayError("not_found", 404);
    }
    registration.revoked = true;
    registration.revokedAt = revokedAt;
    registration.fcmRegistrationToken = null;
    for (const credential of this.credentials.values()) {
      if (credential.deliveryHandle === deliveryHandle) {
        credential.revoked = true;
        credential.revokedAt = revokedAt;
      }
    }
    for (const delegation of this.delegations.values()) {
      if (delegation.deliveryHandle === deliveryHandle) {
        delegation.state = "revoked";
      }
    }
  }

  async createDelegation(delegation) {
    if (this.delegations.has(delegation.delegationId)) {
      throw new RelayError("conflict", 409);
    }
    const registration = this.registrations.get(delegation.deliveryHandle);
    if (!registration || registration.revoked) {
      throw new RelayError("not_found", 404);
    }
    this.delegations.set(delegation.delegationId, structuredClone(delegation));
  }

  async redeemDelegation({
    delegationId,
    challengeId,
    challengeSecret,
    targetDeviceId,
    idempotencyKey,
    now,
    credential,
  }) {
    const delegation = this.delegations.get(delegationId);
    if (!delegation) {
      throw new RelayError("not_found", 404);
    }
    if (new Date(delegation.expiresAt) <= now) {
      delegation.state = "expired";
      throw new RelayError("delegation_expired", 409);
    }
    if (
      delegation.challengeId !== challengeId ||
      delegation.targetDeviceId !== targetDeviceId ||
      delegation.challengeDigest !== sha256(challengeSecret)
    ) {
      throw new RelayError("delegation_rejected", 409);
    }
    if (delegation.state === "redeemed") {
      if (delegation.idempotencyKey === idempotencyKey) {
        return clone(delegation.redemptionResponse);
      }
      throw new RelayError("delegation_redeemed", 409);
    }
    if (delegation.state !== "pending") {
      throw new RelayError("delegation_rejected", 409);
    }
    const response = {
      schemaVersion: 2,
      delegationId,
      deliveryHandle: delegation.deliveryHandle,
      deliveryKeyId: credential.keyId,
      deliverySecret: credential.secret,
      expiresAt: credential.expiresAt,
    };
    credential.deliveryHandle = delegation.deliveryHandle;
    this.credentials.set(credential.keyId, structuredClone(credential));
    delegation.state = "redeemed";
    delegation.deliveryKeyId = credential.keyId;
    delegation.idempotencyKey = idempotencyKey;
    delegation.redemptionResponse = structuredClone(response);
    return clone(response);
  }

  async activateDelegation(delegationId, deliveryKeyId, activatedAt) {
    const delegation = this.delegations.get(delegationId);
    if (!delegation || delegation.deliveryKeyId !== deliveryKeyId) {
      throw new RelayError("delegation_rejected", 409);
    }
    if (delegation.state === "active") {
      return;
    }
    if (new Date(delegation.expiresAt) <= new Date(activatedAt)) {
      delegation.state = "expired";
      throw new RelayError("delegation_expired", 409);
    }
    if (delegation.state !== "redeemed") {
      throw new RelayError("delegation_rejected", 409);
    }
    delegation.state = "active";
    delegation.activatedAt = activatedAt;
    const credential = this.credentials.get(deliveryKeyId);
    credential.active = true;
  }

  async revokeDeliveryCredential(deliveryHandle, deliveryKeyId, revokedAt) {
    const credential = this.credentials.get(deliveryKeyId);
    if (!credential || credential.deliveryHandle !== deliveryHandle) {
      throw new RelayError("not_found", 404);
    }
    credential.revoked = true;
    credential.revokedAt = revokedAt;
    const delegation = this.delegations.get(credential.delegationId);
    if (delegation) {
      delegation.state = "revoked";
    }
  }

  async consumeReplay({
    keyId,
    nonce,
    eventId,
    deliveryHandle,
    expiresAt,
    now,
  }) {
    for (const [key, expiry] of this.replays) {
      if (expiry <= now) {
        this.replays.delete(key);
      }
    }
    const keys = [`nonce:${sha256(`${keyId}:${nonce}`)}`];
    if (eventId) {
      keys.push(`event:${deliveryStorageKey(deliveryHandle, eventId)}`);
    }
    if (keys.some((key) => this.replays.has(key))) {
      throw new RelayError("replay", 409);
    }
    for (const key of keys) {
      this.replays.set(key, expiresAt);
    }
  }

  async enqueueDelivery(delivery) {
    const key = deliveryStorageKey(delivery.deliveryHandle, delivery.eventId);
    if (this.deliveries.has(key)) {
      throw new RelayError("replay", 409);
    }
    this.deliveries.set(key, structuredClone(delivery));
  }

  async acceptDelivery({ replay, delivery }) {
    await this.consumeReplay(replay);
    await this.enqueueDelivery(delivery);
  }

  async getDelivery(deliveryHandle, eventId) {
    return clone(
      this.deliveries.get(deliveryStorageKey(deliveryHandle, eventId)),
    );
  }

  async markDeliveryDelivered(deliveryHandle, eventId, deliveredAt) {
    const delivery = this.deliveries.get(
      deliveryStorageKey(deliveryHandle, eventId),
    );
    if (!delivery) {
      throw new RelayError("not_found", 404);
    }
    delivery.state = "delivered";
    delivery.deliveredAt = deliveredAt;
    delivery.lastError = null;
    delivery.leaseUntil = null;
  }

  async markDeliveryPending(deliveryHandle, eventId, nextAttemptAt) {
    const delivery = this.deliveries.get(
      deliveryStorageKey(deliveryHandle, eventId),
    );
    if (!delivery) {
      throw new RelayError("not_found", 404);
    }
    delivery.state = "pending";
    delivery.attemptCount += 1;
    delivery.nextAttemptAt = nextAttemptAt;
    delivery.leaseUntil = null;
  }

  async markDeliveryFailed(
    deliveryHandle,
    eventId,
    failedAt,
    failureReason,
  ) {
    const delivery = this.deliveries.get(
      deliveryStorageKey(deliveryHandle, eventId),
    );
    if (!delivery) {
      throw new RelayError("not_found", 404);
    }
    delivery.state = "failed";
    delivery.attemptCount += 1;
    delivery.failedAt = failedAt;
    delivery.failureReason = failureReason;
    delivery.leaseUntil = null;
  }

  async claimDelivery(deliveryHandle, eventId, now, leaseUntil) {
    const delivery = this.deliveries.get(
      deliveryStorageKey(deliveryHandle, eventId),
    );
    if (
      !delivery ||
      delivery.state !== "pending" ||
      new Date(delivery.nextAttemptAt) > now ||
      (delivery.leaseUntil && new Date(delivery.leaseUntil) > now)
    ) {
      return false;
    }
    delivery.leaseUntil = leaseUntil;
    return true;
  }

  async listPendingDeliveries(now, limit) {
    return [...this.deliveries.values()]
      .filter(
        (delivery) =>
          delivery.state === "pending" && new Date(delivery.nextAttemptAt) <= now,
      )
      .slice(0, limit)
      .map((delivery) => structuredClone(delivery));
  }
}

function deliveryStorageKey(deliveryHandle, eventId) {
  if (!deliveryHandle || !eventId) {
    throw new RelayError("invalid_request");
  }
  return sha256(`${deliveryHandle}:${eventId}`);
}

function clone(value) {
  return value === undefined || value === null ? null : structuredClone(value);
}
