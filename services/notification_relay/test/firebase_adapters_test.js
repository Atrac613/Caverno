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

test("an approval push takes its own channel, collapse key and category", () => {
  // A completion and a blocked turn must not share a channel: silencing "your
  // task finished" would otherwise silence "your Mac is waiting on you".
  const message = buildFirebaseMessage({
    token: "fcm-token",
    data: {
      kind: "remote_coding_approval_requested",
      eventId: "event_654321",
      approvalId: "approval_1234567",
      conversationId: "conversation_123",
      title: "Caverno needs your approval",
      body: "Your Mac is waiting on a shell command.",
    },
  });

  assert.equal(message.android.notification.channelId, "approval_required");
  assert.equal(
    message.apns.payload.aps.category,
    "caverno_approval_push",
  );
  // Collapsed on the approval, so re-raising the same request replaces its
  // notification rather than stacking a second answerable copy.
  assert.equal(message.android.collapseKey, "approval_1234567");
  assert.equal(message.apns.headers["apns-collapse-id"], "approval_1234567");
});

test("a completion push keeps its channel and carries no approval category", () => {
  const message = buildFirebaseMessage({
    token: "fcm-token",
    data: {
      kind: "remote_coding_run_terminal",
      eventId: "event_123456",
      conversationId: "conversation_123",
      title: "Remote coding completed",
      body: "Your remote coding task completed.",
    },
  });

  assert.equal(
    message.android.notification.channelId,
    "remote_coding_completion",
  );
  assert.equal(message.apns.payload.aps.category, undefined);
  assert.equal(message.android.collapseKey, "event_123456");
});

test("an approval withdrawal is silent on both platforms", () => {
  const message = buildFirebaseMessage({
    token: "fcm-token",
    data: {
      kind: "remote_coding_approval_resolved",
      eventId: "event_987654",
      approvalId: "approval_1234567",
      conversationId: "conversation_123",
      resolvedAt: "2026-09-09T14:00:00.000Z",
    },
  });

  // It removes a notification; showing one would be the opposite of the point.
  // An `android.notification` block, even an empty one, makes FCM render a
  // blank notification instead of waking the app.
  assert.equal(message.notification, undefined);
  assert.equal(message.android.notification, undefined);
  assert.equal(message.apns.headers["apns-push-type"], "background");
  assert.equal(message.apns.payload.aps["content-available"], 1);
  assert.equal(message.apns.payload.aps.alert, undefined);
  assert.equal(message.apns.payload.aps.sound, undefined);

  // Collapsing on the approval id would make two withdrawals for different
  // approvals evict each other, and cannot replace an already-delivered alert
  // in any case.
  assert.equal(message.apns.headers["apns-collapse-id"], "event_987654");
  assert.equal(message.android.collapseKey, "event_987654");
});
