import { getAppCheck } from "firebase-admin/app-check";
import { getMessaging } from "firebase-admin/messaging";

export class FirebaseAppCheckVerifier {
  constructor({ logger = console } = {}) {
    this.logger = logger;
  }

  async verify(token) {
    try {
      const result = await getAppCheck().verifyToken(token, { consume: true });
      if (result.alreadyConsumed === true) {
        throw new Error("App Check token was already consumed.");
      }
    } catch (error) {
      // The caller collapses every failure into 401, which hides whether a
      // registration was rejected for an unregistered app, a consumed token,
      // or a misconfigured project. Record the provider reason without the
      // token itself.
      this.logger.warn?.("app_check_verification_failed", {
        code: typeof error?.code === "string" ? error.code : null,
        reason:
          typeof error?.message === "string"
            ? error.message.slice(0, 300)
            : null,
      });
      throw error;
    }
  }
}

export class FirebaseMessagingProvider {
  async send({ token, data }) {
    try {
      await getMessaging().send(buildFirebaseMessage({ token, data }));
    } catch (error) {
      throw classifyFirebaseMessagingError(error);
    }
  }
}

export function buildFirebaseMessage({ token, data }) {
  return {
    token,
    data,
    notification: {
      title: data.title,
      body: data.body,
    },
    android: {
      priority: "high",
      collapseKey: data.eventId,
      notification: {
        channelId: "remote_coding_completion",
        tag: data.eventId,
      },
    },
    apns: {
      headers: {
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": data.eventId,
      },
      payload: {
        aps: {
          sound: "default",
          "thread-id": data.conversationId,
        },
      },
    },
  };
}

export class NotificationProviderError extends Error {
  constructor({ retryable, invalidatesToken = false }) {
    super("Notification provider delivery failed.");
    this.name = "NotificationProviderError";
    this.retryable = retryable;
    this.invalidatesToken = invalidatesToken;
  }
}

export function classifyFirebaseMessagingError(error) {
  const code = typeof error?.code === "string" ? error.code : "";
  const invalidatesToken = new Set([
    "messaging/invalid-registration-token",
    "messaging/registration-token-not-registered",
  ]).has(code);
  const permanent =
    invalidatesToken ||
    new Set([
      "messaging/invalid-argument",
      "messaging/mismatched-credential",
      "messaging/authentication-error",
      "messaging/third-party-auth-error",
    ]).has(code);
  return new NotificationProviderError({
    retryable: !permanent,
    invalidatesToken,
  });
}
