# Enterprise GCP Pub/Sub Architecture & Delivery Playbook

This reference playbook details architectural patterns, subscription selection matrices, ordering guarantees, dead-letter queue (DLQ) resilience, and zero-trust OIDC authentication for scaling event-driven workloads on **Google Cloud Platform (GCP)**.

#---

## ── SUBSCRIPTION ARCHITECTURAL PATTERNS ──

Google Cloud Pub/Sub decouples event producers from consumers using three primary delivery mechanisms: **Pull**, **Push**, and **Export** subscriptions.

### 1. Pull Subscriptions
* **Mechanism:** The subscriber application actively initiates requests to the Pub/Sub service to retrieve messages via unary RPCs or persistent bidirectional gRPC streams (**StreamingPull**).
* **Operational Advantage:** Provides strict client-side flow control and backpressure management. Workers pull messages only when local CPU, memory, and downstream connection pools have capacity.
* **Constraint:** Requires long-running compute infrastructure (GKE pods or Compute Engine VMs) and Google Cloud client libraries.

### 2. Push Subscriptions
* **Mechanism:** The Pub/Sub service initiates outbound HTTPS `POST` requests to deliver messages directly to a registered webhook or serverless endpoint as soon as messages arrive.
* **Operational Advantage:** Eliminates polling overhead and enables scale-to-zero architectures. Pub/Sub dynamically manages delivery concurrency using slow-start algorithms based on endpoint HTTP response codes (`200 OK` vs. `429`/`5xx`).
* **Constraint:** Requires a publicly routable HTTPS endpoint with a valid SSL certificate and enforces a maximum acknowledgment deadline of 10 minutes.

### 3. Export Subscriptions
* **Mechanism:** Pub/Sub writes messages directly to native GCP storage sinks (**BigQuery**, **Cloud Storage**, or **Cloud Bigtable**) without intermediate subscriber compute.
* **Operational Advantage:** Zero-code ingestion pipelines with reduced infrastructure cost and operational overhead.

#---

## ── DECISION MATRIX: SERVICE, VOLUME & USE CASE ──

### 1. Selection by Target Compute & Storage Service

| Target Service | Recommended Pattern | Architectural Rationale |
| :--- | :--- | :--- |
| **Cloud Run & Cloud Functions** | **Push** (or Eventarc) | Scales automatically from zero on incoming HTTP requests without maintaining idle polling workers. |
| **GKE & Compute Engine (VMs)** | **Pull (StreamingPull)** | Persistent containers/VMs maintain long-lived gRPC connections for maximum throughput and granular flow control. |
| **Dataflow (Apache Beam)** | **Pull** | Native Dataflow Pub/Sub connectors leverage managed pull streams for stateful windowing and high-throughput ETL. |
| **App Engine** | **Push** | Standard App Engine environments process HTTP webhook requests natively without background worker threads. |
| **External Webhooks / 3rd-Party APIs** | **Push** | Delivers JSON payloads over standard HTTPS without requiring external systems to install Google Cloud SDKs. |
| **On-Premises / Private VPCs** | **Pull** | Subscribers initiate outbound connections over Cloud Interconnect/VPN, avoiding inbound firewall rules or public ingress. |
| **BigQuery, Cloud Storage, & Bigtable** | **Export** | Streams raw event data directly into analytical tables or object buckets with zero consumer compute. |

### 2. Selection by Traffic Volume & Workload Profile

* **Low or Sporadic Volume (0 to hundreds of msg/sec):** Use **Push** with Cloud Run. Eliminates idle compute charges during zero-traffic windows.
* **Spiky or Unpredictable Bursts:** Use **Push** when downstream services scale horizontally on HTTP concurrency. Use **Pull** when downstream databases have fixed connection limits and require strict backpressure.
* **Sustained High Throughput (Thousands to millions of msg/sec):** Use **Pull (StreamingPull)** on GKE. Persistent gRPC streams eliminate per-message HTTP handshake overhead.
* **Long-Running Batch or Heavy Compute (ML inference, media processing):** Use **Pull**. Workers can batch messages and dynamically extend acknowledgment deadlines beyond the 10-minute Push cap.
* **Multi-Topic Fan-In:** Use **Push**. Multiple topics can route events to a single HTTPS microservice endpoint without managing multiple client listener threads.

#---

## ── RELIABILITY: MESSAGE ORDERING & DEAD-LETTER QUEUES ──

### 1. Strict Message Ordering
* **Mechanism:** Publishers attach an `ordering_key` (e.g., `order_id`, `customer_id`) to messages. Pub/Sub guarantees sequential delivery for all messages sharing the same key.
* **Pull vs. Push Execution:** In **Pull**, client libraries deliver messages per key sequentially. In **Push**, Pub/Sub halts delivery of subsequent messages for a given key until the endpoint acknowledges the in-flight message with an HTTP `200 OK`.
* **Critical Constraint:** Both publishers and subscribers **must** use a **regional Pub/Sub endpoint** (e.g., `://googleapis.com`) rather than the global endpoint to preserve ordering guarantees.

### 2. Dead-Letter Queues (DLQs)
* **Mechanism:** When a message fails processing repeatedly and reaches the configured `max_delivery_attempts` threshold (5 to 100), Pub/Sub forwards the message to a dedicated Dead-Letter Topic to prevent infinite retry loops.
* **Ordering Interaction:** When ordering is enabled, forwarding a poison-pill message to the DLQ unblocks the ordering key so subsequent healthy messages can proceed.
* **IAM Prerequisite:** The Google-managed Pub/Sub service agent (`service-<PROJECT_NUMBER>@://gserviceaccount.com`) requires `roles/pubsub.publisher` on the DLQ topic and `roles/pubsub.subscriber` on the source subscription.

#---

## ── SECURITY: ZERO-TRUST OIDC PUSH AUTHENTICATION ──

To invoke private Cloud Run services (`--no-allow-unauthenticated`) from a Push subscription without exposing public endpoints:

```text
[ Pub/Sub Push Subscription ]
       │
       ├──► Mints OIDC JWT as (pubsub-invoker@PROJECT.iam)
       │
       ▼  HTTPS POST + Authorization: Bearer <JWT>
[ Cloud Run IAM Proxy ] ──► Validates Token & Audience ──► [ Private Container ]
```

1. **Dedicated Invoker Identity:** Provision a custom service account (`pubsub-invoker`) with `roles/run.invoker` on the target Cloud Run service.
2. **Token Minting:** Grant the Google-managed Pub/Sub service agent `roles/iam.serviceAccountTokenCreator` on the `pubsub-invoker` service account.
3. **Audience Matching Rule:** Always configure the OIDC token audience (`--push-auth-token-audience`) to match the **root URL** of the Cloud Run service (e.g., `https://run.app`), omitting any sub-paths like `/pubsub/push`.

#---

## ── IMPLEMENTATION RUNBOOK: GCLOUD CLI ──

Replace `YOUR_PROJECT_ID`, `YOUR_PROJECT_NUMBER`, `YOUR_REGION`, `YOUR_SERVICE_NAME`, and `YOUR_SERVICE_URL` with environment-specific values.

### Step 1: Provision Topics & Dead-Letter Subscription
```bash
# Create primary and dead-letter topics
gcloud pubsub topics create orders-topic
gcloud pubsub topics create orders-dlq-topic

# Create retention subscription on the DLQ topic
gcloud pubsub subscriptions create orders-dlq-sub \
    --topic=orders-dlq-topic

# Grant Pub/Sub service agent permission to publish to the DLQ topic
gcloud pubsub topics add-iam-policy-binding orders-dlq-topic \
    --member="serviceAccount:service-YOUR_PROJECT_NUMBER@://gserviceaccount.com" \
    --role="roles/pubsub.publisher"
```

### Step 2: Configure Zero-Trust OIDC Service Account
```bash
# Create dedicated invoker identity
gcloud iam service-accounts create pubsub-invoker \
    --display-name="Pub/Sub Cloud Run Invoker"

# Allow Pub/Sub service agent to mint OIDC tokens
gcloud iam service-accounts add-iam-policy-binding \
    "pubsub-invoker@YOUR_PROJECT_://gserviceaccount.com" \
    --member="serviceAccount:service-YOUR_PROJECT_NUMBER@://gserviceaccount.com" \
    --role="roles/iam.serviceAccountTokenCreator"

# Grant Cloud Run invoker permission
gcloud run services add-iam-policy-binding YOUR_SERVICE_NAME \
    --region=YOUR_REGION \
    --member="serviceAccount:pubsub-invoker@YOUR_PROJECT_://gserviceaccount.com" \
    --role="roles/run.invoker"
```

### Step 3A: Create Pull Subscription (Ordering + DLQ)
```bash
gcloud pubsub subscriptions create orders-pull-sub \
    --topic=orders-topic \
    --enable-message-ordering \
    --dead-letter-topic=orders-dlq-topic \
    --max-delivery-attempts=5 \
    --ack-deadline=60

# Allow Pub/Sub service agent to ack forwarded messages
gcloud pubsub subscriptions add-iam-policy-binding orders-pull-sub \
    --member="serviceAccount:service-YOUR_PROJECT_NUMBER@://gserviceaccount.com" \
    --role="roles/pubsub.subscriber"
```

### Step 3B: Create Authenticated Push Subscription (Ordering + DLQ)
```bash
gcloud pubsub subscriptions create orders-push-sub \
    --topic=orders-topic \
    --push-endpoint="https://YOUR_SERVICE_URL/pubsub/push" \
    --push-auth-service-account="pubsub-invoker@YOUR_PROJECT_://gserviceaccount.com" \
    --push-auth-token-audience="https://YOUR_SERVICE_URL" \
    --enable-message-ordering \
    --dead-letter-topic=orders-dlq-topic \
    --max-delivery-attempts=5 \
    --ack-deadline=60

# Allow Pub/Sub service agent to ack forwarded messages
gcloud pubsub subscriptions add-iam-policy-binding orders-push-sub \
    --member="serviceAccount:service-YOUR_PROJECT_NUMBER@://gserviceaccount.com" \
    --role="roles/pubsub.subscriber"
```

### Step 4: Verification
```bash
gcloud pubsub subscriptions describe orders-push-sub \
    --format="yaml(enableMessageOrdering,deadLetterPolicy,pushConfig)"
```

#---

## ── INFRASTRUCTURE AS CODE: TERRAFORM ──

```hcl
data "google_project" "project" {}

# ------------------------------------------------------------------------------
# 1. Topics & Dead-Letter Storage


------------------------------------------------------------------------------

resource "google_pubsub_topic" "orders_topic" {
name = "orders-topic"
}
resource "google_pubsub_topic" "orders_dlq_topic" {
name = "orders-dlq-topic"
}
resource "google_pubsub_subscription" "orders_dlq_sub" {
name  = "orders-dlq-sub"
topic = google_pubsub_topic.orders_dlq_topic.id
}
resource "google_pubsub_topic_iam_member" "dlq_publisher" {
topic  = google_pubsub_topic.orders_dlq_topic.id
role   = "roles/pubsub.publisher"
member = "serviceAccount:service-${data.google_project.project.number}@gserviceaccount.com"
}

------------------------------------------------------------------------------


2. Zero-Trust OIDC Authentication for Cloud Run Push


------------------------------------------------------------------------------

resource "google_service_account" "pubsub_invoker" {
account_id   = "pubsub-invoker"
display_name = "Pub/Sub Cloud Run Invoker"
}
resource "google_service_account_iam_member" "token_creator" {
service_account_id = google_service_account.pubsub_invoker.name
role               = "roles/iam.serviceAccountTokenCreator"
member             = "serviceAccount:service-${data.google_project.project.number}@gserviceaccount.com"
}
resource "google_cloud_run_v2_service_iam_member" "run_invoker" {
name     = "YOUR_SERVICE_NAME"
location = "YOUR_REGION"
role     = "roles/run.invoker"
member   = "serviceAccount:${google_service_account.pubsub_invoker.email}"
}

------------------------------------------------------------------------------


3A. Pull Subscription (Ordering + DLQ + Exponential Backoff)


------------------------------------------------------------------------------

resource "google_pubsub_subscription" "orders_pull_sub" {
name  = "orders-pull-sub"
topic = google_pubsub_topic.orders_topic.id
enable_message_ordering = true
ack_deadline_seconds    = 60
dead_letter_policy {
dead_letter_topic     = google_pubsub_topic.orders_dlq_topic.id
max_delivery_attempts = 5
}
retry_policy {
minimum_backoff = "10s"
maximum_backoff = "600s"
}
depends_on = [google_pubsub_topic_iam_member.dlq_publisher]
}
resource "google_pubsub_subscription_iam_member" "pull_sub_dlq_reader" {
subscription = google_pubsub_subscription.orders_pull_sub.id
role         = "roles/pubsub.subscriber"
member       = "serviceAccount:service-${data.google_project.project.number}@gserviceaccount.com"
}

------------------------------------------------------------------------------


3B. Authenticated Push Subscription (Ordering + DLQ + OIDC)


------------------------------------------------------------------------------

resource "google_pubsub_subscription" "orders_push_sub" {
name  = "orders-push-sub"
topic = google_pubsub_topic.orders_topic.id
enable_message_ordering = true
ack_deadline_seconds    = 60
push_config {
push_endpoint = "https://YOUR_SERVICE_URL/pubsub/push"
oidc_token {
service_account_email = google_service_account.pubsub_invoker.email
audience              = "https://YOUR_SERVICE_URL"
}
}
dead_letter_policy {
dead_letter_topic     = google_pubsub_topic.orders_dlq_topic.id
max_delivery_attempts = 5
}
depends_on = [
google_pubsub_topic_iam_member.dlq_publisher,
google_service_account_iam_member.token_creator,
google_cloud_run_v2_service_iam_member.run_invoker
]
}
resource "google_pubsub_subscription_iam_member" "push_sub_dlq_reader" {
subscription = google_pubsub_subscription.orders_push_sub.id
role         = "roles/pubsub.subscriber"
member       = "serviceAccount:service-${data.google_project.project.number}@gserviceaccount.com"
}


#---

## ── APPLICATION CODE REFERENCE ──

To maintain strict ordering guarantees in application code:
1. **Publishers** must explicitly target a **regional Pub/Sub endpoint** (`<REGION>://googleapis.com`) and enable message ordering on the client.
2. **Push Subscribers** must decode the Base64-encoded `message.data` field from the JSON HTTP envelope and return an HTTP `2xx` status to acknowledge, or an HTTP `4xx`/`5xx` status to trigger retries and eventual DLQ routing.

### 1. Python Implementation (`google-cloud-pubsub` & FastAPI)

#### Publisher with Regional Endpoint & Ordering Key
```python
from google.api_core.client_options import ClientOptions
from google.cloud import pubsub_v1

PROJECT_ID = "your-project-id"
TOPIC_ID = "orders-topic"
REGION = "us-central1"

# 1. Configure client to use a regional endpoint and enable ordering
publisher_options = pubsub_v1.types.PublisherOptions(enable_message_ordering=True)
client_options = ClientOptions(api_endpoint=f"{REGION}://googleapis.com")

publisher = pubsub_v1.PublisherClient(
    publisher_options=publisher_options,
    client_options=client_options,
)
topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)


def publish_ordered_event(order_id: str, payload: str) -> str:
    data = payload.encode("utf-8")
    # Messages with the same ordering_key are delivered sequentially
    future = publisher.publish(topic_path, data=data, ordering_key=order_id)
    try:
        return future.result()
    except Exception as exc:
        # Resume publishing for this key if an error pauses the internal queue
        publisher.resume_publish(topic_path, order_id)
        raise exc
```

#### Push Subscriber Endpoint (Cloud Run / FastAPI)
```python
import base64
import json
from fastapi import FastAPI, HTTPException, Request, Response

app = FastAPI()


@app.post("/pubsub/push")
async def receive_pubsub_push(request: Request):
    envelope = await request.json()
    if not envelope or "message" not in envelope:
        # Returning 400 signals a malformed payload; Pub/Sub will retry until DLQ threshold
        raise HTTPException(status_code=400, detail="Invalid Pub/Sub message format")

    pubsub_message = envelope["message"]
    ordering_key = pubsub_message.get("orderingKey", "none")

    try:
        # Decode Base64 message payload
        raw_data = base64.b64decode(pubsub_message["data"]).decode("utf-8")
        event = json.loads(raw_data)

        # --- Execute idempotent business logic here ---
        print(f"Processed event for key={ordering_key}: {event}")

        # Return 200/204 to acknowledge message and unblock next message in ordering key
        return Response(status_code=204)

    except Exception as exc:
        # Returning 500 triggers exponential backoff retry and eventual DLQ forwarding
        raise HTTPException(status_code=500, detail=f"Processing failed: {exc}")
```

#---

### 2. Go Implementation (`://google.com` & `net/http`)

#### Publisher with Regional Endpoint & Ordering Key
```go
package main

import (
	"context"
	"fmt"

	"://google.com"
	"google.golang.org/api/option"
)

func publishOrderedEvent(ctx context.Context, projectID, topicID, region, orderID, payload string) (string, error) {
	endpoint := fmt.Sprintf("%s://googleapis.com", region)

	// 1. Initialize client bound to the regional endpoint
	client, err := pubsub.NewClient(ctx, projectID, option.WithEndpoint(endpoint))
	if err != nil {
		return "", fmt.Errorf("pubsub.NewClient: %w", err)
	}
	defer client.Close()

	topic := client.Topic(topicID)
	// 2. Enable message ordering on the topic publisher
	topic.EnableMessageOrdering = true
	defer topic.Stop()

	res := topic.Publish(ctx, &pubsub.Message{
		Data:        []byte(payload),
		OrderingKey: orderID,
	})

	msgID, err := res.Get(ctx)
	if err != nil {
		// Resume publishing for this ordering key after a failure
		topic.ResumePublish(orderID)
		return "", fmt.Errorf("publish failed: %w", err)
	}
	return msgID, nil
}
```

#### Push Subscriber Endpoint (Cloud Run / `net/http`)
```go
package main

import (
	"encoding/json"
	"log"
	"net/http"
)

type pushEnvelope struct {
	Message struct {
		Data        []byte            `json:"data"` // Go's encoding/json automatically decodes Base64 into []byte
		Attributes  map[string]string `json:"attributes"`
		MessageID   string            `json:"messageId"`
		OrderingKey string            `json:"orderingKey"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

func pubsubPushHandler(w http.ResponseWriter, r *http.Request) {
	var envelope pushEnvelope
	if err := json.NewDecoder(r.Body).Decode(&envelope); err != nil {
		http.Error(w, "Bad Request: invalid JSON envelope", http.StatusBadRequest)
		return
	}

	// --- Execute idempotent business logic here ---
	log.Printf("Received msgID=%s key=%s payload=%s",
		envelope.Message.MessageID,
		envelope.Message.OrderingKey,
		string(envelope.Message.Data),
	)

	// Return 204 No Content to acknowledge the message
	w.WriteHeader(http.StatusNoContent)
}
```
