# External Services — Stateless Architecture (LEAN v1.1)

> Principle: **Orchestrator + DB are the only Sources of Truth.** External services are **stateless** (no durable storage), pure functions over inputs. All writes go back through the Orchestrator with **idempotency keys**, **service JWTs**, and **correlation IDs**.

---

## Summary of Stateless Services

* **Twilio Edge** — voice/SMS webhook handler; verifies Twilio signatures; normalizes events; emits to Orchestrator. *No PII persisted.*
* **DispatchBot AI** — price‑ranges + scheduling intent; given context → returns reply/intent/slots; never sends SMS; no history/PII stored.
* **Universal Calendar** — availability + booking adapter (Google first); accepts short‑lived **access tokens**; idempotent booking.
* **Billing Edge (Stripe)** — webhook receiver for Checkout/Subscription lifecycle; toggles entitlements; idempotent on `event.id`.
* **A2P Manager** — submits brand/campaign; polls statuses; writes updates to DB; no local storage.

---

## Cross‑Cutting Contracts

* **Auth:** Orchestrator signs requests to services with a short‑lived **service JWT** (claims: `aud`, `bizId`, `convId`, `scope`). Webhooks from providers validated with provider signatures.
* **Idempotency:** All state‑changing calls include `Idempotency-Key`; services must be **safe to retry**. Dedup and final persistence happen in Orchestrator.
* **Observability:** `x-corr-id` from Orchestrator → all services → provider responses; logs and metrics roll up per conversation.
* **Privacy:** Payloads contain the minimum fields; services keep no durable logs with PII.

---

## Twilio Edge (Stateless External Service — Voice/SMS)

**Endpoints**

* `POST /twilio/voice` — inbound/missed/voicemail webhooks.
* `POST /twilio/sms` — inbound SMS; status callbacks for outbound messages.

**Behavior**

* Verify Twilio signature; map events into canonical form: `{ bizId, phoneNumberId, fromE164, toE164, eventType, timestamps, providerSids, payloadSubset }`.
* Forward to Orchestrator; **never** send outbound SMS (that’s Orchestrator’s job). No durable storage.

**Failure modes**

* If Orchestrator is down: return 2xx to Twilio **after** enqueueing to a transient queue (e.g., Pub/Sub/SQS). The queue is still stateless from the service POV.

---

## DispatchBot AI (Stateless External Service)

**Request → Response**

* Input: `policy`, `context.messages`, `hours`, `serviceArea`, `pricing`, `capabilities`.
* Output: `{ reply, lang, intent, suggestedSlots[], escalate, confidence, safety.redactions[] }`.

**Notes**

* Scope: **price ranges + scheduling** only. Unknowns → recommend escalate.
* Multilingual basics (start with `en`; optional `es`).

---

## Universal Calendar (Stateless External Service)

**Endpoints**

* `POST /calendar/availability` — requires short‑lived **access token** from Orchestrator.
* `POST /calendar/book` — idempotent via `Idempotency-Key` (e.g., `book_{convId}_{slotStart}`), conflict‑aware.

**Notes**

* No refresh tokens stored here; Orchestrator resolves them via secrets manager and passes access tokens.

---

## Billing Edge (Stripe — Stateless)

**Endpoints**

* `POST /stripe/webhook` — verify signature; dedupe on `event.id`; emit normalized events: `checkout.completed`, `subscription.updated`, `customer.updated`.

**Writes (via Orchestrator)**

* Update `Entitlement.active`, store `stripeCustomerId`, optional `stripeSubscriptionId`.

---

## A2P Manager (Stateless)

**Endpoints**

* `POST /a2p/submit` — payload: legal name, EIN, website, authorized contact, use case, sample messages.
* `POST /a2p/status` — poll provider; normalize to `DRAFT/SUBMITTED/PENDING_CARRIERS/APPROVED/REJECTED`.

**Writes (via Orchestrator)**

* Update `A2PArtifact` and `Business.a2pStatus`; activate number when Approved.

---

## What stays in Orchestrator (Source of Truth)

* **Conversations** & **Messages** (full log + delivery audit)
* **Contacts** (opt‑out ledger)
* **Business config** (hours, service area, pricing, templates)
* **PhoneNumber** + A2P status
* **Appointments** & **CalendarAccount** (token refs only)

---

## Latency Budgets & SLAs

* AI respond p95 ≤ **1500 ms**
* Availability p95 ≤ **600 ms**
* Booking p95 ≤ **1000 ms**
* Twilio Edge handler p95 ≤ **250 ms** (excluding provider retries)

**Timeout strategy:** graceful degrade to human/escalation; never block the owner window.

---

## Rollout Approach

* Start with services as **internal Cloud Run/Lambda** apps behind a private gateway. Keep the HTTP contracts stable so we can later swap implementations or isolate cost without schema changes.
