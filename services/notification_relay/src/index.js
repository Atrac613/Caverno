import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  FirebaseAppCheckVerifier,
  FirebaseMessagingProvider,
} from "./firebase_adapters.js";
import { FirestoreRelayStore } from "./firestore_store.js";
import { createHttpHandler } from "./http_handler.js";
import { RelayService } from "./relay_service.js";

if (getApps().length === 0) {
  initializeApp();
}

const region = "asia-northeast1";
const store = new FirestoreRelayStore(getFirestore());
const service = new RelayService({
  store,
  appCheckVerifier: new FirebaseAppCheckVerifier(),
  provider: new FirebaseMessagingProvider(),
});

export const notificationRelay = onRequest(
  {
    region,
    cors: false,
    timeoutSeconds: 30,
    memory: "256MiB",
    maxInstances: 20,
  },
  createHttpHandler({ service, logger }),
);

export const retryNotificationDeliveries = onSchedule(
  {
    region,
    schedule: "every 1 minutes",
    timeoutSeconds: 60,
    memory: "256MiB",
    maxInstances: 1,
  },
  async () => {
    const attempted = await service.retryPendingDeliveries({ limit: 100 });
    logger.info("notification_relay_retry", { attempted });
  },
);
