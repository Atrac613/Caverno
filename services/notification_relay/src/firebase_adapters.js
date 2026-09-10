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

// A completion can wait; a blocked turn is the desktop standing still until
// the person answers. They are separate Android channels so that silencing the
// first does not silence the second, and the app creates both before it
// registers for delivery — a channel that does not exist yet when a push
// arrives at a terminated app is dropped to the manifest default.
const NOTIFICATION_CHANNELS = {
  remote_coding_run_terminal: "remote_coding_completion",
  remote_coding_approval_requested: "approval_required",
};

export function buildFirebaseMessage({ token, data }) {
  const channelId =
    NOTIFICATION_CHANNELS[data.kind] ?? "remote_coding_completion";
  // Collapse on the approval rather than the event, so a re-raise of the same
  // request replaces its notification instead of stacking a second one the
  // person could answer twice.
  const collapseId = data.approvalId ?? data.eventId;
  if (data.kind === "remote_coding_approval_resolved") {
    return buildApprovalWithdrawalMessage({ token, data });
  }
  return {
    token,
    data,
    notification: {
      title: data.title,
      body: data.body,
    },
    android: {
      priority: "high",
      collapseKey: collapseId,
      notification: {
        channelId,
        tag: collapseId,
      },
    },
    apns: {
      headers: {
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": collapseId,
      },
      payload: {
        aps: {
          sound: "default",
          "thread-id": data.conversationId,
          // Lets the app answer from the notification itself. Its actions
          // launch the app in the foreground, unlike the category the app uses
          // for its own local notifications: a push arrives when the app is not
          // running, and a background action then makes iOS cold-launch a
          // Flutter app headless, which crashes it. iOS shows no buttons when
          // the category is absent, which is the correct degradation for a
          // build that predates it.
          ...(data.kind === "remote_coding_approval_requested"
            ? { category: "caverno_approval_push" }
            : {}),
        },
      },
    },
  };
}

// Removes a notification rather than showing one, so it must not carry an
// alert: no `notification` block, `content-available` instead of an alert
// push type, and normal priority because nothing here is time-critical to the
// person -- the decision it refers to is already made.
//
// The collapse id deliberately does NOT match the request it withdraws. APNs
// collapse replaces an *undelivered* alert; the notification this exists to
// remove has already been delivered, and reusing the id would only make two
// withdrawals for different approvals evict each other.
function buildApprovalWithdrawalMessage({ token, data }) {
  return {
    token,
    data,
    // Data-only on both platforms. An `android.notification` block -- even an
    // empty one -- makes FCM render a blank notification instead of waking the
    // app to remove one.
    android: {
      priority: "high",
      collapseKey: data.eventId,
    },
    apns: {
      headers: {
        "apns-push-type": "background",
        "apns-priority": "5",
        "apns-collapse-id": data.eventId,
      },
      payload: {
        aps: {
          "content-available": 1,
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
