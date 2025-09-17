Executive Summary

You are starting a low-touch, high-margin digital agency called nevermisscall.com. Your core business is selling a simple, automated service to local service businesses that instantly turns their missed phone calls into paying customers via text message.


The Core Problem You Solve
Local service businesses (plumbers, dentists, electricians, etc.) are often too busy working to answer every incoming phone call.
This is an invisible but extremely expensive problem. A missed call from a new customer means that customer immediately calls a competitor.
The result is lost revenue, lost jobs, and wasted marketing dollars every single day.




## Roles & Access ##
- Business (subscriber): Pays subscription; configures brand, numbers, service areas, pricing ranges, business hours & holidays; sees all reports. Does not answer calls.
- **Employee (agent/technician) **: Handles conversations, confirms quotes, schedules, edits job notes. Access only to their calendar + assigned conversations.
- Backend Administrator: Internal operations; manages A2P 10DLC registrations, troubleshooting, number provisioning, compliance, refunds/credits.






## Authentication & Authorization (Clerk)
* Clerk for user auth (business owners/employees).
AuthN/Z: Clerk.dev with role claims; Business owns one or more phone numbers; Employees belong to exactly one Business and one calendar; all actions are auditable.

---

## 1. Approach

* Use **Clerk hosted pages** (less work, Clerk manages the UI + flows).
* Your app just redirects users to Clerk for **sign-in / sign-up / forgot password**.
* Clerk returns a session + `clerkUserId` to your app.
* You create a **local User record** in Postgres keyed by `clerkUserId`.

---

## 2. Supported Auth Methods

* **Email + Password** → always available fallback.
* **Google** → covers most tradespeople with Gmail/Workspace.
* **Facebook** → still widely used by local service pros who run business pages.

That’s broad enough for plumbers, electricians, HVAC, etc.
No need for Apple, GitHub, LinkedIn, etc. in this audience.

---

## 3. Core Features (out of the box from Clerk)

* **Sign-In** (email/password or social).
* **New Registration** (email verification included).
* **Forgot Password** (reset via email).
* **Session Management** (Clerk middleware in Next.js).
* **Optional Account Settings UI** (password, MFA, etc. — if you want it).

---

## 4. Where Your DB Comes In

* At **registration**, you only touch the **User** table:

  * Store `clerkUserId`, `email`, `name` (if available).
  * Mark them as `globalRole = USER`.
* **Business** and **Employee** are **not created yet**.

  * Those are only added **after subscription** in your onboarding flow.

---

## 5. User Flow

1. Visitor hits **Sign Up** → sent to Clerk hosted page.
2. Clerk handles registration & verification.
3. Clerk redirects back with a valid session.
4. Your app checks Postgres for `clerkUserId`:

   * If new → create `User` row.
   * If existing → just log them in.
5. User lands in app with **no business info yet**.
6. When they subscribe → create `Business`, `BusinessUser`, and optional `Employee`.

---

✅ Net result: **Clerk handles identity**, you handle **business/employee models** later.
This keeps auth simple and offloads security, while leaving you in control of business logic.





## Onboarding & Provisioning
* Business setup wizard, Stripe checkout, phone number provisioning, calendar connect, brand assets upload.
* Includes all configuration/knowledge: business hours, service areas, price ranges, FAQs, response templates, language defaults.


* Keep current entities. Enforce via config/entitlement:

  * `Business.teamSizeLimit = 1`
  * Auto‑create `Employee` for owner; hide Team UI
  * `Appointment.employeeId` = owner’s employeeId
  * `CalendarAccount.employeeId` = owner’s employeeId

---

### Technology Stack
react-hook-form + Zod (with @hookform/resolvers/zod) on top of shadcn/ui.

### Page 1 — Account & Plan

**Critical**

* Owner email (OTP)
* Owner mobile (OTP)
* Business display name
* Vertical selector
* Plan: Flat → **Stripe Checkout**

**Default**

* Logo upload, brand color
* Address/timezone (prefilled from Stripe or area code)
* Languages (default `en`)

---

### Page 2 — Number & Operating Setup

**Critical**

* Reserve **local MMS** number (status: **Pending Activation** until A2P Approved)
* Confirm **Hours**: Mon–Fri 8–6 (toggle weekends)
* Confirm **Service Area**: 15‑mile radius

**Default**

* Area‑code preferences / start port‑in
* Ring window (20s), Owner window (60s; 30–180 allowed)
* After‑hours behavior: AIOnly (default) / QueueForHuman / CloseWithMsg
* Holidays list (US Federal preloaded)
* STOP/HELP copy (CTIA stock)

> **Note:** Until A2P is approved, the reserved number **cannot send SMS**. Inbound calls still reach your number; the system logs missed calls but **won’t text back** yet.

---

### Page 3 — Calendar, Messaging & Pricing

**Critical**

* Connect **Google Calendar** *(Skip = offers/callback mode)*
* Instant text‑back preview + AI disclosure (stock)
* Pick **top 3 services** (seeded) & accept default price ranges

**Default**

* Buffers, double‑book policy, title/description templates
* Edit templates; enable bilingual (`es`)
* Revenue prompts ON (120 min), attribution window (14 days)
* Ops contacts (email/SMS), optional Slack webhook

---

### Page 4 — **A2P 10DLC Compliance (Required to Text)**

Use this page to **explain the law** in plain English, collect the **minimum data**, and submit. **Go Live** remains disabled until Approved.

**Critical**

* **Why this matters (banner):** Carriers require verified brands/campaigns for application-to-person (A2P) texting. We **cannot send any SMS** without approval. You can still accept calls.
* **A2P Micro‑form (prefilled where possible):**

  * **Legal business name** (from Stripe) — must match EIN
  * **EIN / Tax ID** (format check)
  * **Website URL** (from email domain/Stripe) — must have *Privacy* and *Terms*
  * **Authorized contact** (name, email, phone)
  * **Use case:** Customer Care (two‑way conversational)
  * **Sample messages:** stock templates including **STOP** / **HELP** language
  * **Opt‑in mechanism:** Inbound only (customer texts/calls first)
  * **Submit A2P** → status: **Submitted/Pending Carriers**

**Default**

* **Education panel:**

  * What A2P 10DLC is and why carriers enforce it
  * What’s reviewed (brand identity, website, message samples)
  * Typical approval pitfalls & fixes
  * Throughput basics and content restrictions

* **Quick‑fix checklist (auto‑validated):**
  * ✅ Website reachable over HTTPS
  * ✅ Privacy & Terms pages found
  * ✅ Legal name ≈ EIN record name
  * ✅ STOP/HELP present in at least one sample

* **Status & Resubmission:** Show carrier reason codes; one‑click edit→resubmit.

---

### Review & Go Live (inline on Page 4)

**Critical**

* Summary (number, hours, service radius, templates, calendar)
* **Go Live** toggle is **disabled** until **A2P = Approved**
* Once Approved → auto‑activate number, run live missed‑call test (places a call to your number, confirms instant SMS), then enable **Go Live**

**Default**

* Invite optional **concierge call‑back** for setup (15 min)

---
























## Message Orchestrator
* Event/state machine for missed-call flow, 60s owner window, AI fallback, owner takeover.
* Single source of truth for conversations; logs every in/out message (no separate inbox service).
* Simple call counting for entitlements/usage ("new phone numbers per day" rule).

** Core Event Flow — “Missed Call → Conversation → Appointment”**
1. Inbound call to Business number.
2. Missed condition: no answer within configured ring window; Twilio Server records call.missed.
3. Instant Text‑Back: Orchestrator sends branded SMS template to caller.
4. Owner Window (T=0..60s): Orchestrator waits; if Employee replies, AI stands down; if silent, proceed.
5. AI Fallback: DispatchBot AI takes over → triage intent → answer FAQs → offer timeslots.
6. Scheduling: Universal Calendar fetches availability; books appointment; confirmation SMS.
7. Handover/Takeover: At any time Employee can jump in; AI pauses; Orchestrator updates state.
8. Closure: Conversation summarized; revenue follow‑up reminder to record job value.
9. Reporting: KPIs updated (response time, conversion, revenue); all events logged.


** Orchestrator State Machine (High‑Level) **
States: idle → missed_detected → texted → owner_window → ai_active → scheduled/abandoned/escalated → closed.
Timers: owner_window=60s (configurable), ai_inactivity_timeout (e.g., 15m), follow_up_after_no_show.
Transitions:
- Owner replies → owner_window → human_active.
- No owner reply → ai_active.
- Appointment booked → scheduled.
- Customer STOP → closed (opt‑out flag set).





** Webhook Gateway (new module) **
Unified ingress for Twilio/Stripe/Calendar; signature verification, de-duplication/replay handling, basic observability.



** Reports Module (business-only) **
Calls list, responder (AI vs human), conversion to appointments, and month-to-date revenue captured.


** A2P 10DLC (Manual v1) **
Ops tracked via spreadsheet; internal Admin toggle to mark a number "ready" once approved.





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

## A2P Manager (Stateless)

**Endpoints**

* `POST /a2p/submit` — payload: legal name, EIN, website, authorized contact, use case, sample messages.
* `POST /a2p/status` — poll provider; normalize to `DRAFT/SUBMITTED/PENDING_CARRIERS/APPROVED/REJECTED`.

**Writes (via Orchestrator)**

* Update `A2PArtifact` and `Business.a2pStatus`; activate number when Approved.

---


## Twilio Phone Numbers Manager (Stateless)
* **Search → buy is two different APIs.** Twilio’s *AvailablePhoneNumbers* search returns inventory by area code/NPA (and filters like SMS/MMS/voice), but **does not hold** numbers; you must **POST to IncomingPhoneNumbers** to actually purchase one. Keeping this logic in a thin service is ideal. ([Twilio][1])
* **A2P wiring belongs here.** After purchase, the service can attach the number to the tenant’s **Messaging Service** (so it’s auto-associated to the approved A2P campaign) and set webhooks—details you don’t want spread across the app. ([Twilio][2])
* **No true “reservation.”** Twilio reservation in docs applies to **Proxy pools**, not inventory. So you either buy immediately or accept race conditions; better that this service enforces the rule. ([Twilio][3])

### Minimal API (stateless)

**GET `/v1/phone/available`**
Query: `country=US&type=local&areaCode=310&sms=true&mms=true&voice=true&limit=20`
Returns: `{numbers:[{e164, friendlyName, areaCode, capabilities}], fetchedAt}`
(Uses Twilio *AvailablePhoneNumbers Local*.) ([Twilio][4])

**POST `/v1/phone/purchase`**
Body: `{businessId, e164? , search:{areaCode, sms,mms,voice}, count=1, idempotencyKey}`
Behavior:

1. If `e164` omitted, search then buy first `count` matches via *IncomingPhoneNumbers*.
2. Set SMS/Voice webhooks to your **Twilio Edge** endpoints.
3. If tenant has **approved A2P**, attach PN SID to their **Messaging Service**; else mark DB status `PENDING_ACTIVATION`.
   Returns: `{numbers:[{e164, phoneSid, status}]}`. ([Twilio][5])

**POST `/v1/phone/release`**
Body: `{phoneSid}` → releases number (and detaches from Messaging Service if present). ([Twilio][5])

**POST `/v1/phone/attach`** (idempotent)
Body: `{phoneSid, messagingServiceSid}` → adds number to MS sender pool (used for A2P campaign association). ([Twilio][2])

**POST `/v1/phone/configure-webhooks`**
Body: `{phoneSid, smsUrl, voiceUrl}` → sets inbound URLs/region as needed. ([Twilio][5])

---

### Implementation notes (practical)

* **Stateless**: no DB writes here—return Twilio artifacts; Orchestrator persists `PhoneNumber{e164, twilioSid, status}` and flips `Business.a2pStatus` gates.
* **Idempotency**: require `Idempotency-Key` on `purchase` to prevent double-buys.
* **Solo-first**: enforce `count=1` in v1 (bulk buying invites cost + inventory drift).
* **A2P guardrails**: numbers can’t send SMS until they’re in a Messaging Service tied to an **approved** campaign; each number can belong to **one** campaign at a time. ([Twilio Help Center][6])
* **Fallback search**: support `postalCode` as an alternative to `areaCode` (Twilio supports both). ([Twilio][1])





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






## 2.11 Billing Class (Dependency Injection)

**Goal:** keep billing logic **inside Orchestrator** as a stateless class (no internal cache), with **Stripe as billing SoT** and our DB as the runtime snapshot (`Business`, `Entitlement`). Webhook Gateway invokes this class after signature verification.

**Responsibilities:**

* Normalize **Stripe** checkout/subscription/invoice events and apply **idempotent** updates to `Business`/`Entitlement`.
* Expose simple **commands**: *Upgrade now* (immediate price change) and *Schedule downgrade* (next cycle); final truth confirmed via Stripe webhooks.
* Maintain per-business **entitlement snapshot** (plan, active flag, quota in `limitsJson`, optional period anchors).

**Injected Ports (DI):**

* `StripePort` (update subscription price; schedule downgrade).
* `BusinessRepo` (read/update `stripeCustomerId` / `stripeSubscriptionId`).
* `EntitlementRepo` (1:1 upsert by `businessId`).
* `PlanCatalogPort` (map `stripePriceId → { code, monthlyQuota, priceCents }`).
* `EventDeduper` (process each `stripeEventId` once).
* `Clock` / `Logger` / `Tracer` (utilities).

**Reads/Writes:**

* **Reads:** `Business(stripeCustomerId, stripeSubscriptionId)`, `Entitlement(businessId)`, `PlanCatalog` (if table).
* **Writes:**

  * `Business.stripeCustomerId`, `Business.stripeSubscriptionId`
  * `Entitlement.{ plan, active, limitsJson, currentPeriodStart?, currentPeriodEnd?, stripePriceId? }`
  * *(Optional)* `BillingEvent(stripeEventId)` for idempotency ledger (or reuse a generic processed-events table).

**Behavior (events → effects):**

* `checkout.session.completed` → set Stripe refs; `Entitlement.active=true`; set `plan` from `price.id`; set quota in `limitsJson`; set optional period anchors.
* `customer.subscription.updated` → reflect upsell/downsell; refresh `plan` and anchors; update `active` per status.
* `invoice.payment_*` / `customer.subscription.deleted` → toggle `active` accordingly.

**Notes / Policy:**

* **Single active subscription** per Business.
* **Upsell** increases quota **immediately** (current period).
* **Downsell** applies **next cycle** (no mid-period quota shrink).
* Quota enforcement lives in Orchestrator using `Entitlement` + `Conversation` counts; this class does not keep counters.

**Non-goals (v1.1):**

* No multi-subscription, overages, or local schedulers.
* No durable state inside the class; all persistence via repos.


