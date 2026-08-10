import assert from "node:assert/strict";
import test from "node:test";

import {
  buildFirebaseMessage,
  classifyFirebaseMessagingError,
} from "../src/firebase_adapters.js";

test("Firebase messages collapse provider retries by terminal event", () => {
  const data = {
    eventId: "event_123456",
    conversationId: "conversation_123",
    title: "Remote coding completed",
    body: "Your remote coding task completed.",
  };

  const message = buildFirebaseMessage({ token: "fcm-token", data });

  assert.equal(message.android.collapseKey, data.eventId);
  assert.equal(
    message.android.notification.channelId,
    "remote_coding_completion",
  );
  assert.equal(message.android.notification.tag, data.eventId);
  assert.equal(message.apns.headers["apns-collapse-id"], data.eventId);
  assert.equal(message.apns.payload.aps["thread-id"], data.conversationId);
});

test("Firebase messaging errors distinguish invalid tokens from outages", () => {
  const invalidToken = classifyFirebaseMessagingError({
    code: "messaging/registration-token-not-registered",
  });
  assert.equal(invalidToken.retryable, false);
  assert.equal(invalidToken.invalidatesToken, true);

  const unavailable = classifyFirebaseMessagingError({
    code: "messaging/server-unavailable",
  });
  assert.equal(unavailable.retryable, true);
  assert.equal(unavailable.invalidatesToken, false);
});
