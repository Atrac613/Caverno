import { FieldValue } from "firebase-admin/firestore";

import { RelayError, sha256 } from "./security.js";

const ROOT = "notificationRelayV2";

export class FirestoreRelayStore {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async createRegistration(registration, credential) {
    const registrationRef = this.#registration(registration.deliveryHandle);
    const credentialRef = this.#credential(credential.keyId);
    await this.firestore.runTransaction(async (transaction) => {
      const [registrationSnapshot, credentialSnapshot] = await Promise.all([
        transaction.get(registrationRef),
        transaction.get(credentialRef),
      ]);
      if (registrationSnapshot.exists || credentialSnapshot.exists) {
        throw new RelayError("conflict", 409);
      }
      transaction.set(registrationRef, encodeDates(registration));
      transaction.set(credentialRef, encodeDates(credential));
    });
  }

  async getRegistration(deliveryHandle) {
    const snapshot = await this.#registration(deliveryHandle).get();
    return snapshot.exists ? decodeDates(snapshot.data()) : null;
  }

  async getCredential(deliveryHandle, keyId) {
    const [credentialSnapshot, registrationSnapshot] = await Promise.all([
      this.#credential(keyId).get(),
      this.#registration(deliveryHandle).get(),
    ]);
    if (!credentialSnapshot.exists || !registrationSnapshot.exists) {
      return null;
    }
    const credential = decodeDates(credentialSnapshot.data());
    if (credential.deliveryHandle !== deliveryHandle) {
      return null;
    }
    if (registrationSnapshot.data().revoked === true) {
      credential.revoked = true;
    }
    return credential;
  }

  async rotateToken(deliveryHandle, fcmRegistrationToken, updatedAt) {
    const reference = this.#registration(deliveryHandle);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists || snapshot.data().revoked === true) {
        throw new RelayError("not_found", 404);
      }
      transaction.update(reference, {
        fcmRegistrationToken,
        updatedAt: new Date(updatedAt),
      });
    });
  }

  async invalidateFcmToken(deliveryHandle, updatedAt) {
    const reference = this.#registration(deliveryHandle);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        return;
      }
      transaction.update(reference, {
        fcmRegistrationToken: null,
        updatedAt: new Date(updatedAt),
      });
    });
  }

  async revokeRegistration(deliveryHandle, revokedAt) {
    const reference = this.#registration(deliveryHandle);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw new RelayError("not_found", 404);
      }
      transaction.update(reference, {
        revoked: true,
        revokedAt: new Date(revokedAt),
        fcmRegistrationToken: null,
      });
    });
  }

  async createDelegation(delegation) {
    const delegationRef = this.#delegation(delegation.delegationId);
    const registrationRef = this.#registration(delegation.deliveryHandle);
    await this.firestore.runTransaction(async (transaction) => {
      const [delegationSnapshot, registrationSnapshot] = await Promise.all([
        transaction.get(delegationRef),
        transaction.get(registrationRef),
      ]);
      if (delegationSnapshot.exists) {
        throw new RelayError("conflict", 409);
      }
      if (!registrationSnapshot.exists || registrationSnapshot.data().revoked) {
        throw new RelayError("not_found", 404);
      }
      transaction.set(delegationRef, encodeDates(delegation));
    });
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
    const delegationRef = this.#delegation(delegationId);
    return this.firestore.runTransaction(async (transaction) => {
      const delegationSnapshot = await transaction.get(delegationRef);
      if (!delegationSnapshot.exists) {
        throw new RelayError("not_found", 404);
      }
      const delegation = decodeDates(delegationSnapshot.data());
      if (new Date(delegation.expiresAt) <= now) {
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
          return delegation.redemptionResponse;
        }
        throw new RelayError("delegation_redeemed", 409);
      }
      if (delegation.state !== "pending") {
        throw new RelayError("delegation_rejected", 409);
      }
      credential.deliveryHandle = delegation.deliveryHandle;
      const credentialRef = this.#credential(credential.keyId);
      const credentialSnapshot = await transaction.get(credentialRef);
      if (credentialSnapshot.exists) {
        throw new RelayError("conflict", 409);
      }
      const response = {
        schemaVersion: 2,
        delegationId,
        deliveryHandle: delegation.deliveryHandle,
        deliveryKeyId: credential.keyId,
        deliverySecret: credential.secret,
        expiresAt: credential.expiresAt,
      };
      transaction.set(credentialRef, encodeDates(credential));
      transaction.update(delegationRef, {
        state: "redeemed",
        deliveryKeyId: credential.keyId,
        idempotencyKey,
        redemptionResponse: encodeDates(response),
      });
      return response;
    });
  }

  async activateDelegation(delegationId, deliveryKeyId, activatedAt) {
    const delegationRef = this.#delegation(delegationId);
    const credentialRef = this.#credential(deliveryKeyId);
    await this.firestore.runTransaction(async (transaction) => {
      const [delegationSnapshot, credentialSnapshot] = await Promise.all([
        transaction.get(delegationRef),
        transaction.get(credentialRef),
      ]);
      if (!delegationSnapshot.exists || !credentialSnapshot.exists) {
        throw new RelayError("delegation_rejected", 409);
      }
      const delegation = delegationSnapshot.data();
      if (delegation.deliveryKeyId !== deliveryKeyId) {
        throw new RelayError("delegation_rejected", 409);
      }
      if (delegation.state === "active") {
        return;
      }
      if (delegation.expiresAt.toDate() <= new Date(activatedAt)) {
        throw new RelayError("delegation_expired", 409);
      }
      if (delegation.state !== "redeemed") {
        throw new RelayError("delegation_rejected", 409);
      }
      transaction.update(delegationRef, {
        state: "active",
        activatedAt: new Date(activatedAt),
      });
      transaction.update(credentialRef, { active: true });
    });
  }

  async revokeDeliveryCredential(deliveryHandle, deliveryKeyId, revokedAt) {
    const credentialRef = this.#credential(deliveryKeyId);
    await this.firestore.runTransaction(async (transaction) => {
      const credentialSnapshot = await transaction.get(credentialRef);
      if (
        !credentialSnapshot.exists ||
        credentialSnapshot.data().deliveryHandle !== deliveryHandle
      ) {
        throw new RelayError("not_found", 404);
      }
      transaction.update(credentialRef, {
        revoked: true,
        revokedAt: new Date(revokedAt),
      });
      const delegationId = credentialSnapshot.data().delegationId;
      if (delegationId) {
        transaction.update(this.#delegation(delegationId), { state: "revoked" });
      }
    });
  }

  async consumeReplay(replay) {
    await this.firestore.runTransaction(async (transaction) => {
      await consumeReplayTransaction(transaction, this.#replays(), replay);
    });
  }

  async acceptDelivery({ replay, delivery }) {
    const deliveryRef = this.#delivery(
      delivery.deliveryHandle,
      delivery.eventId,
    );
    await this.firestore.runTransaction(async (transaction) => {
      const deliverySnapshot = await transaction.get(deliveryRef);
      if (deliverySnapshot.exists) {
        throw new RelayError("replay", 409);
      }
      await consumeReplayTransaction(transaction, this.#replays(), replay);
      transaction.set(deliveryRef, encodeDates(delivery));
    });
  }

  async markDeliveryDelivered(deliveryHandle, eventId, deliveredAt) {
    await this.#delivery(deliveryHandle, eventId).update({
      state: "delivered",
      deliveredAt: new Date(deliveredAt),
      lastError: null,
      leaseUntil: null,
    });
  }

  async markDeliveryPending(deliveryHandle, eventId, nextAttemptAt) {
    await this.#delivery(deliveryHandle, eventId).update({
      state: "pending",
      attemptCount: FieldValue.increment(1),
      nextAttemptAt: new Date(nextAttemptAt),
      leaseUntil: null,
    });
  }

  async markDeliveryFailed(
    deliveryHandle,
    eventId,
    failedAt,
    failureReason,
  ) {
    await this.#delivery(deliveryHandle, eventId).update({
      state: "failed",
      attemptCount: FieldValue.increment(1),
      failedAt: new Date(failedAt),
      failureReason,
      leaseUntil: null,
    });
  }

  async claimDelivery(deliveryHandle, eventId, now, leaseUntil) {
    const reference = this.#delivery(deliveryHandle, eventId);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        return false;
      }
      const delivery = decodeDates(snapshot.data());
      if (
        delivery.state !== "pending" ||
        new Date(delivery.nextAttemptAt) > now ||
        (delivery.leaseUntil && new Date(delivery.leaseUntil) > now)
      ) {
        return false;
      }
      transaction.update(reference, { leaseUntil: new Date(leaseUntil) });
      return true;
    });
  }

  async listPendingDeliveries(now, limit) {
    const snapshot = await this.#deliveries()
      .where("state", "==", "pending")
      .where("nextAttemptAt", "<=", now)
      .orderBy("nextAttemptAt")
      .limit(limit)
      .get();
    return snapshot.docs.map((document) => decodeDates(document.data()));
  }

  #root() {
    return this.firestore.collection(ROOT).doc("state");
  }

  #registrations() {
    return this.#root().collection("registrations");
  }

  #registration(deliveryHandle) {
    return this.#registrations().doc(deliveryHandle);
  }

  #credentials() {
    return this.#root().collection("credentials");
  }

  #credential(keyId) {
    return this.#credentials().doc(keyId);
  }

  #delegations() {
    return this.#root().collection("delegations");
  }

  #delegation(delegationId) {
    return this.#delegations().doc(delegationId);
  }

  #replays() {
    return this.#root().collection("replays");
  }

  #deliveries() {
    return this.#root().collection("deliveries");
  }

  #delivery(deliveryHandle, eventId) {
    return this.#deliveries().doc(deliveryStorageKey(deliveryHandle, eventId));
  }
}

async function consumeReplayTransaction(transaction, collection, replay) {
  const keys = [`nonce:${sha256(`${replay.keyId}:${replay.nonce}`)}`];
  if (replay.eventId) {
    keys.push(
      `event:${deliveryStorageKey(replay.deliveryHandle, replay.eventId)}`,
    );
  }
  const references = keys.map((key) => collection.doc(key));
  const snapshots = await Promise.all(
    references.map((reference) => transaction.get(reference)),
  );
  for (const snapshot of snapshots) {
    if (snapshot.exists && snapshot.data().expiresAt.toDate() > replay.now) {
      throw new RelayError("replay", 409);
    }
  }
  for (const reference of references) {
    transaction.set(reference, {
      expiresAt: replay.expiresAt,
      createdAt: replay.now,
    });
  }
}

function deliveryStorageKey(deliveryHandle, eventId) {
  if (!deliveryHandle || !eventId) {
    throw new RelayError("invalid_request");
  }
  return sha256(`${deliveryHandle}:${eventId}`);
}

function encodeDates(value) {
  return Object.fromEntries(
    Object.entries(value).map(([key, field]) => {
      if (key.endsWith("At") && typeof field === "string") {
        return [key, new Date(field)];
      }
      if (field && typeof field === "object" && !Array.isArray(field)) {
        return [key, encodeDates(field)];
      }
      return [key, field];
    }),
  );
}

function decodeDates(value) {
  return Object.fromEntries(
    Object.entries(value).map(([key, field]) => {
      if (field && typeof field.toDate === "function") {
        return [key, field.toDate().toISOString()];
      }
      if (field && typeof field === "object" && !Array.isArray(field)) {
        return [key, decodeDates(field)];
      }
      return [key, field];
    }),
  );
}
