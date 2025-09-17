# LLM Brief — Twilio Number Provisioning (Ultra‑Concise)

**Goal:** Generate a tiny **near‑stateless** FastAPI service that provisions Twilio local numbers and attaches required webhooks for nevermisscall.com.

---

## 1) Scope (and only this)

* **List availability** by `areaCode` with `sms/voice` filters.
* **Purchase** number.
* **Configure**: set **Messaging webhook URL** (inbound SMS) and **Voice** (either **voiceUrl** or **voiceAppSid**) + **statusCallbackUrl**.
* **Release** number.

**Out of scope:** sending SMS/calls, missed‑call logic, consent/10DLC, CRM, analytics.

**Decisions:** FastAPI + DI; **Port/Adapter** (`TelephonyPort` + `TwilioAdapter`); Twilio = **source of truth**; optional **idempotency ledger** (Redis/Postgres) and audit; **dry‑run** supported; **retry + circuit breaker** around Twilio.

---

## 2) Public API (contract)

All mutations require `Idempotency-Key`. Responses include `correlationId`.

* `GET /availability?areaCode=415&sms=true&voice=true&limit=20&page=...`

  * Returns candidates `[ { e164, country, capabilities } ]`.
* `POST /numbers` — purchase + configure (or dry‑run)

  * Body: `{ e164? | areaCode?, capabilities?, webhooks:{ smsWebhookUrl, voiceUrl? | voiceAppSid?, statusCallbackUrl? }, dryRun? }`
  * Responses: `201/200` (configured) or `207` (purchased but unconfigured) with diagnostics.
* `PUT /numbers/{sid}/webhooks` — update webhooks.
* `GET /numbers/{sid}` — echo provider state for drift visibility.
* `DELETE /numbers/{sid}` — release (idempotent).

---

## 3) Provider ops (minimal)

* **Search** available local numbers.
* **Purchase** by E.164 or via search selection.
* **Configure**: attach Messaging webhook; attach Voice (URL **or** TwiML App SID) + `statusCallbackUrl`.
* **Release** the number.

---

## 4) Validation & Policies

* Webhooks must be **https**, ≤2048 chars, **allowlisted domains**, no secrets in query.
* `voiceUrl` **xor** `voiceAppSid` (not both).
* Ensure purchased number supports requested capabilities.
* Timeouts: **8s** per provider call; **max 3** retries with jitter; map 429/5xx.
* Optional HEAD reachability probe (non‑blocking) for URLs.

---

## 5) Errors (mapping)

`400` validation • `404` not found • `409` availability race • `429` throttled • `502` provider error • `503` provider unavailable (circuit open). Include `{ code, message, details }`.

---

## 6) Non‑functional & Observability

* Stateless handlers; horizontal scale; no shared in‑mem state.
* Health `/healthz`; readiness `/readyz` (token check).
* Correlation‑Id per request; structured logs for Twilio ops.
* Metrics: availability/purchase/configure success rates, Twilio latency, 429/5xx counts.

---

## 7) Code layout (tiny files)

```
app/main.py           # FastAPI bootstrap, health
app/deps.py           # DI: config/logger/port
routers/availability.py
routers/numbers.py    # POST/PUT/GET/DELETE
models/dto.py         # Pydantic request/response
models/errors.py      # exception mappers
ports/telephony.py    # Protocol + types
domain/service.py     # pure orchestration
domain/policies.py    # validators
domain/idempotency.py # middleware + store
adapters/twilio_adapter.py
utils/retry.py        # backoff/circuit
```

**Env:** `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` (or key/secret), optional `TWILIO_SUBACCOUNT_SID`, `ALLOWED_WEBHOOK_DOMAINS`, `REQUEST_TIMEOUT_MS`, `RETRY_MAX_ATTEMPTS`, `IDEMPOTENCY_BACKEND`.

---

## 8) Generation plan (chunked)

1. **Ports + DTOs + Policies** (compile without Twilio).
2. **Routers + Service** (use FakeTelephonyPort).
3. **TwilioAdapter + Idempotency + Retry**.

Constraints for codegen: each file <200 LOC; no unused deps; deterministic responses; JSON only.

---

## 9) Acceptance criteria

* List → Purchase → Configure → Update → Release work end‑to‑end.
* Mutations **idempotent** via `Idempotency-Key`.
* **Dry‑run** returns planned Twilio ops without side effects.
* `GET /numbers/{sid}` reflects provider state.
* Unit tests for service orchestration with fake adapter.

---

## 10) Explicit non‑goals

No consent/10DLC, conversation logic, messaging send, call flows, CRM sync, analytics, UI, or reconciliation jobs. Provisioning only.



Here’s a tight, three-step build plan with a test phase after each. It’s scoped to **provisioning only** and optimized for AI codegen (file-by-file, stateless, DI-first).

---

# Step 1 — Contracts & Validation (compile-only, no Twilio)

**Goal:** lock APIs and invariants so later chunks snap in cleanly.

**Generate (files):**

* `ports/telephony.py` — `TelephonyPort` Protocol + dataclasses:

  * `search(area_code: str, sms: bool, voice: bool) -> list[AvailableNumber]`
  * `purchase(e164: str | None, area_code: str | None, caps: set[str]) -> PurchasedNumber`
  * `configure(sid: str, sms_url: str, voice_url: str | None, voice_app_sid: str | None, status_cb: str | None) -> None`
  * `release(sid: str) -> None`
  * `get_number(sid: str) -> NumberState`
* `models/dto.py` — Pydantic models for:

  * AvailabilityQuery, AvailabilityResponse
  * PurchaseRequest, PurchaseResponse
  * WebhookUpdateRequest
* `domain/policies.py` — pure validators:

  * `validate_webhook_urls(…)`, `validate_capabilities(…)`, `xor_voice_url_or_app_sid(…)`
* `models/errors.py` — typed exceptions + to-HTTP error map (we’ll wire in step 2).

**Testing (now):**

* Unit tests (no FastAPI yet):

  * URL policy: reject non-https, >2048 chars, non-allowlisted domains.
  * Voice URL XOR App SID enforced.
  * Capabilities check.
* Success criteria: all tests pass; mypy/pyright clean; no Twilio imports.

**LLM prompt (use verbatim-ish):**

> “Generate only these files: ports/telephony.py, models/dto.py, domain/policies.py, models/errors.py. Keep each file <200 LOC, no side effects, no network. Use Python 3.11 typing, Pydantic v2. Provide docstrings explaining *why*. Do not add FastAPI or Twilio yet.”

---

# Step 2 — HTTP Surface & Orchestration (with Fake port)

**Goal:** working API with a **FakeTelephonyPort** so endpoints run and tests assert JSON contracts.

**Generate (files):**

* `app/main.py` — FastAPI bootstrap, routers include, `/healthz` & `/readyz` stubs.
* `app/deps.py` — DI container:

  * Env config loader, logger, `get_port()` returns **FakeTelephonyPort** for now.
* `routers/availability.py` — `GET /availability` → `TelephonyPort.search`.
* `routers/numbers.py` —

  * `POST /numbers` (purchase + configure + optional `dryRun`)
  * `PUT /numbers/{sid}/webhooks`
  * `GET /numbers/{sid}`
  * `DELETE /numbers/{sid}`
  * Add **Correlation-Id** per request (generate if missing).
* `domain/service.py` — pure orchestration:

  * purchase flow → configure → shape responses
  * dry-run returns mutation plan without calling port
* `models/errors.py` — add FastAPI exception handlers mapping our exceptions to 400/404/409/502/503.

**Testing (now):**

* FastAPI `TestClient` contract tests (golden JSON):

  * Availability happy path.
  * Purchase+configure (using Fake port) returns 201 with `state="Configured"`.
  * Dry-run plan includes purchase + configure ops.
  * 409 when Fake port simulates availability race.
  * PUT webhooks enforces XOR policy.
  * DELETE returns 200 and is idempotent (second call safe NOOP).
  * `/healthz` returns 200; `/readyz` OK with Fake.
* Success criteria: endpoints return the exact fields; no Twilio dependency; 95% branch coverage on service + policies.

**LLM prompt:**

> “Using the files from Step 1 as context, generate: app/main.py, app/deps.py, routers/availability.py, routers/numbers.py, domain/service.py, and update models/errors.py with FastAPI handlers. Use a `FakeTelephonyPort` inside deps for now. Implement correlation id middleware. Enforce validation via domain.policies. Keep each file <200 LOC.”

---

# Step 3 — Twilio Adapter, Idempotency, Retry/Circuit

**Goal:** swap Fake for real Twilio, add idempotency middleware, resilience.

**Generate (files):**

* `adapters/twilio_adapter.py` — `TwilioAdapter(TelephonyPort)`:

  * Wrap Twilio SDK or `httpx` calls.
  * Timeouts: 8s; map 429/5xx; **no sleeps in adapter**—use retry helper.
* `domain/idempotency.py` — middleware + store:

  * Read `Idempotency-Key` on `POST /numbers` & `DELETE /numbers/{sid}`.
  * Backends: in-memory (dev) + Redis or Postgres (flagged by env).
  * Key = (method, path, body\_hash, tenant if available). Replay returns saved response.
* `utils/retry.py` — jittered backoff, max 3 attempts, classify retryable errors; coarse circuit breaker (fail-fast after N consecutive provider failures for T seconds).
* `app/deps.py` — update DI:

  * `USE_FAKE_PORT` env switch.
  * Inject `IdempotencyMiddleware`.
  * Provide `ALLOWED_WEBHOOK_DOMAINS`, timeouts, retry params from env.

**Testing (now):**

* **Adapter unit tests** with a stubbed HTTP layer (no real network):

  * Retries on 429/5xx, no retry on 4xx.
  * Error mapping: provider→ our exceptions.
* **Idempotency tests**:

  * Same key returns identical body/status; different body with same key → 409 or 422 (choose and document).
  * Concurrency test: two parallel POSTs with same key → one winner, one replay.
* **Resilience tests**:

  * Fake adapter raises 3 consecutive retryable errors → circuit opens → subsequent calls short-circuit with 503 until half-open probe succeeds.
* **(Optional) Live smoke** with Twilio sandbox creds behind a feature flag:

  * `GET /availability` returns >0.
  * `POST /numbers` with `dryRun=true` returns a plan.
  * **Do not** actually buy in CI; keep live only for manual smoke.

**Success criteria:**

* Idempotent mutations; retries verified; circuit behavior observable via metrics/logs.
* Swapping Fake ↔ Twilio adapter is a one-line env change.
* No global mutable state; multiple instances behave identically.

**LLM prompt:**

> “Generate adapters/twilio\_adapter.py, domain/idempotency.py, utils/retry.py, and update app/deps.py to wire them. Keep files <200 LOC, use env vars for config, no business logic beyond provisioning. Implement jittered backoff and a simple circuit breaker. Provide in-memory idempotency store with an interface that can be swapped for Redis/Postgres.”

---

## Build/run checklist (for you, not the LLM)

* After each step: run `ruff`/`black`, `mypy`, `pytest -q`.
* Keep each file small; if a file creeps >200 LOC, split it.
* Never add Twilio logic into routers or service; only via `TelephonyPort`.
* Don’t auto-release numbers on partial failure; return `PurchasedButUnconfigured` + diagnostics.

Want me to turn these three prompts into copy-paste-ready blocks you can drop into your codegen tool?


# Three-Step Codegen Prompts — Twilio Provisioning Service

Copy/paste these **six** prompts (build+test per step) into your codegen LLM. Each prompt is self-contained, enforces small files, and avoids side effects.

---

## 🔧 Step 1 — Build (Contracts & Validation, no Twilio, no FastAPI)

````
You are generating the FIRST chunk of a small Python 3.11 project. Scope: contracts and validation only. No Twilio, no FastAPI, no network calls, no I/O. Keep files small (<200 LOC each), zero side effects.

### Objectives
- Define the Telephony port (protocol) and types needed for provisioning.
- Define DTOs (Pydantic v2) for API requests/responses (to be used later by FastAPI).
- Implement pure validation policies (URLs, capabilities, XOR rule).
- Define error types we will map to HTTP later.

### Files to output (exact paths)
1) ports/telephony.py
2) models/dto.py
3) domain/policies.py
4) models/errors.py

### Requirements
- Python 3.11 typing: Protocol, TypedDict/NamedTuple/dataclasses OK; prefer dataclasses for simple structs.
- Pydantic v2 only.
- Docstrings should explain *why* design choices exist.
- No runtime behavior beyond functions/types (i.e., no prints, no top-level code).
- Keep enums/strings stable and explicit.

### Content details
**ports/telephony.py**
- Define `class TelephonyPort(Protocol)` with methods:
  - `search(area_code: str, sms: bool, voice: bool) -> list[AvailableNumber]`
  - `purchase(e164: str | None, area_code: str | None, capabilities: set[str]) -> PurchasedNumber`
  - `configure(sid: str, sms_url: str, voice_url: str | None, voice_app_sid: str | None, status_cb_url: str | None) -> None`
  - `release(sid: str) -> None`
  - `get_number(sid: str) -> NumberState`
- Define dataclasses: `AvailableNumber`, `PurchasedNumber`, `NumberState` with fields: `sid?`, `e164`, `country`, `capabilities` (set[str]), and provider metadata as needed.

**models/dto.py**
- Pydantic models:
  - `AvailabilityQuery`, `AvailabilityResponse` (with candidates list)
  - `PurchaseRequest` (either `e164` or `areaCode`, optional `capabilities`, required `webhooks`), `PurchaseResponse` (`state: str` with values: `Configured` | `PurchasedButUnconfigured`, `warnings: list[str]`)
  - `WebhookUpdateRequest`
- Include a `CorrelationFields` mixin (`correlationId: str` optional) to be filled by HTTP layer later.

**domain/policies.py**
- Pure functions (no I/O):
  - `validate_webhook_urls(sms_url: str | None, voice_url: str | None, status_cb_url: str | None, allowed_domains: set[str]) -> None`
  - `xor_voice_url_or_app_sid(voice_url: str | None, voice_app_sid: str | None) -> None`
  - `validate_capabilities(requested: set[str], supported: set[str]) -> None`
- Constraints: HTTPS only; max URL length 2048; host must be in allowlist; forbid secrets in query (simple heuristic: keys like token, key, secret).

**models/errors.py**
- Define exception classes: `ValidationError`, `NotFoundError`, `ConflictError`, `RateLimitedError`, `ProviderError`, `ProviderUnavailableError`.
- Provide a helper `error_code(exc: Exception) -> str` returning stable machine codes.

### Output format
Output the four files as separate fenced code blocks, each starting with a comment line containing its path, e.g.:
```python
# ports/telephony.py
<code here>
````

Do not include any other commentary.

```

---

## ✅ Step 1 — Tests
```

Generate unit tests for Step 1 artifacts using pytest. No FastAPI, no Twilio. Pure functions and types only.

### Files to output

1. tests/unit/test\_policies.py
2. tests/unit/test\_dto\_shapes.py

### Coverage

* URL policy: rejects non-https, >2048 chars, disallowed domain, query string containing token/key/secret.
* XOR policy: exactly one of voiceUrl or voiceAppSid must be present.
* Capabilities policy: error when requested not subset of supported.
* DTO: PurchaseRequest validation scenarios (e164 vs areaCode), minimal/extra fields behavior.

### Output format

Two fenced code blocks with the file paths in the first comment line.

```

---

## 🔧 Step 2 — Build (HTTP Surface & Orchestration with Fake Port)
```

You are generating the SECOND chunk. Goal: working FastAPI app using a FakeTelephonyPort so we can run endpoints without Twilio.

### Files to output

1. app/main.py
2. app/deps.py
3. routers/availability.py
4. routers/numbers.py
5. domain/service.py
6. models/errors.py (update: add FastAPI exception handlers)

### Requirements

* FastAPI only; no DB. Add a lightweight request-id (Correlation-Id) middleware.
* DI: `get_port()` in deps currently returns FakeTelephonyPort (in-memory, deterministic).
* Endpoints:

  * `GET /availability`
  * `POST /numbers` (purchase + configure + optional `dryRun`)
  * `PUT /numbers/{sid}/webhooks`
  * `GET /numbers/{sid}`
  * `DELETE /numbers/{sid}`
* `domain/service.py` orchestrates: validate via `domain.policies`, call port, shape responses, implement dry-run (return a plan without calling port).
* All JSON responses include `correlationId` (generate if header missing).
* Keep files <200 LOC, no TODOs, no unused imports.

### FakeTelephonyPort behavior (in deps)

* `search` returns deterministic fake numbers for any area code.
* `purchase` returns a fake SID and echoes capabilities; simulate 1-in-5 conflict to test 409.
* `configure` is a no-op; `get_number` returns a plausible state; `release` records a tombstone.

### Output format

Six fenced code blocks, each beginning with a comment line specifying its path.
Do not include tests in this prompt.

```

---

## ✅ Step 2 — Tests (FastAPI contract tests with Fake Port)
```

Generate pytest tests using FastAPI TestClient for Step 2. No Twilio. Validate JSON contracts and error mapping.

### Files to output

1. tests/contract/test\_availability\_api.py
2. tests/contract/test\_numbers\_api.py

### Cases

* Availability: happy path returns candidates array and correlationId.
* Purchase: 201 with state="Configured"; includes sid/e164; dryRun returns plan and no mutations (assert via FakePort introspection hook).
* Conflict path: Fake port simulates availability race → 409 with code/message.
* Webhook update: XOR rule enforced → 400 when both provided.
* Get number: returns current provider-like state.
* Delete: idempotent; second call still 200/204 with safe response.
* Health/readiness: `/healthz` and `/readyz` return 200.

### Output format

Two fenced code blocks with the file paths in the first comment line.

```

---

## 🔧 Step 3 — Build (Twilio Adapter, Idempotency, Retry/Circuit)
```

You are generating the THIRD chunk. Goal: real adapter and resilience. Keep files <200 LOC each.

### Files to output

1. adapters/twilio\_adapter.py
2. domain/idempotency.py
3. utils/retry.py
4. app/deps.py (update to wire adapter + idempotency + env config)

### Requirements

* `adapters/twilio_adapter.py` implements TelephonyPort using Twilio SDK or httpx. Config via env: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, optional `TWILIO_SUBACCOUNT_SID`, `REQUEST_TIMEOUT_MS`.
* Apply **8s timeout**, classify retryable errors (429, 5xx, network timeouts) but do **not** sleep here—use retry helper.
* `utils/retry.py`: jittered backoff (e.g., base 200ms, factor 2, jitter ±20%), max attempts=3; simple circuit breaker (open after N consecutive failures for T seconds; half-open allows 1 probe).
* `domain/idempotency.py`: Starlette/FastAPI middleware that enforces Idempotency-Key for `POST /numbers` and `DELETE /numbers/{sid}`. In-memory backend with interface allowing Redis/Postgres later. Key: (method, path, body hash). Replay returns saved status/body/headers.
* `app/deps.py` updates: env switch `USE_FAKE_PORT` to toggle Fake vs Twilio adapter; inject IdempotencyMiddleware; load allowlisted domains & retry config from env.

### Output format

Four fenced code blocks with file paths in first comment lines.

```

---

## ✅ Step 3 — Tests (Adapter stubs, Idempotency, Retry)
```

Generate pytest tests focusing on behavior, not real Twilio. Stub the adapter’s HTTP layer to simulate responses.

### Files to output

1. tests/unit/test\_retry\_and\_circuit.py
2. tests/unit/test\_idempotency\_middleware.py
3. tests/unit/test\_twilio\_adapter\_errors.py

### Cases

* Retry helper: retries 429/5xx/timeouts with backoff; does not retry 4xx (e.g., 400/404).
* Circuit breaker: opens after N failures, short-circuits calls with 503; half-open probe resets on success.
* Idempotency: identical key returns identical status/body; conflicting body with same key yields 409; concurrent calls with same key → one winner, one replay.
* Twilio adapter: maps provider errors to our exceptions; imposes request timeout; never retries inside adapter (delegated to retry helper).

### Output format

Three fenced code blocks with file paths in first comment lines.

```
```





--------------------------------------------------------------------------
--------------------------------------------------------------------------

# External API — Twilio Provisioning (Ultra‑Short Contract)

**Purpose:** search, purchase, configure, release Twilio numbers.
**Auth:** `Authorization: Bearer <token>`
**Idempotency:** required on `POST /numbers`, `DELETE /numbers/{sid}` via `Idempotency-Key`.
**Conventions:** E.164 numbers (e.g., `+14155551234`), `areaCode`=3‑digit string, capabilities in {`sms`,`voice`}.
**Correlation:** responses include `correlationId`; client may send `Correlation-Id`.

---

## Endpoints

1. **GET /availability** — query: `areaCode` (req), `sms` (bool), `voice` (bool), `limit` (int, default 20), `page` (cursor).
   **200** → `{ areaCode, capabilities:{sms,voice}, candidates:[{ e164, country, capabilities:{sms,voice} }], nextPage?, correlationId }`

2. **POST /numbers** — purchase + configure (or `dryRun`).
   **Headers:** `Idempotency-Key`.
   **Body:** `{ e164? | areaCode?, capabilities?[], webhooks:{ smsWebhookUrl, voiceUrl? | voiceAppSid?, statusCallbackUrl? }, dryRun? }`
   **201** Configured → `{ sid, e164, state:"Configured", warnings:[], provider:{accountSid}, correlationId }`
   **207** Partial → `{ sid, e164, state:"PurchasedButUnconfigured", warnings:[…], correlationId }`
   **200** Replay (idempotent).
   **200** Dry‑run → `{ plan:[ {op:"purchase",…}, {op:"configureMessaging",…}, {op:"configureVoice",…} ], correlationId }`

3. **PUT /numbers/{sid}/webhooks** — **200** → echo current `{ webhooks:{…}, correlationId }`.

4. **GET /numbers/{sid}** — **200** → `{ sid, e164, country, capabilities:{…}, webhooks:{…}, correlationId }`.

5. **DELETE /numbers/{sid}** — **Headers:** `Idempotency-Key`.
   **200** → `{ sid, released:true, correlationId }` (idempotent).

6. **Health:** `GET /healthz` → `200 { ok:true }`; `GET /readyz` → `200 { ready:true }`.

---

## Validation

* Webhooks: **https**, ≤2048 chars, domain allowlist, no secrets in query (token/key/secret).
* **Exactly one** of `voiceUrl` or `voiceAppSid`.
* Purchased number must support requested capabilities.

---

## Errors (stable `code`)

* **400** `ValidationError` — bad params/URLs/capabilities/XOR.
* **404** `NotFound` — unknown SID.
* **409** `Conflict` — availability race/duplicate intent.
* **429** `RateLimited` — throttled.
* **502** `ProviderError` — Twilio 5xx/timeout.
* **503** `ProviderUnavailable` — circuit open/provider down.
  All errors include `correlationId` and optional `details`.

---

## Notes

* Availability results are **ephemeral**; purchase may return 409.
* Provisioning **only sets URLs** (Messaging webhook, Voice URL/App SID, Status Callback); it does **not** send SMS or run call logic.

