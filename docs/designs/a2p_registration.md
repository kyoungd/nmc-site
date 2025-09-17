TITLE: Stateless A2P Registration Service — High-Level Contract

MISSION
Build a stateless, resilient A2P 10DLC registration service for US SMBs with one use case:
CustomerCare.MissedCallRecovery. The service records desired state, reconciles with the
SMS provider (via an adapter), and emits events. It never blocks on carrier/TCR.

NON-GOALS
- Not a PBX, not SMS sending, not a chatbot.
- No multi-provider or direct TCR/CSP in v1 (use one provider via an abstraction).
- No admin UI. API + workers + webhooks only.

ARCHITECTURE OVERVIEW
- Bounded context: A2P Registration.
- Stateless API + stateless reconciliation workers. Persistence in a DB.
- Event outbox for reliable outbound webhooks (at-least-once).
- Clean ports/adapters: domain depends on interfaces; provider-specific code behind an adapter.
- Tenancy isolation; no shared DB with other services.

DOMAIN (Aggregates and Invariants)
Aggregates:
1) BrandRegistration (who sends; legal entity with EIN)
   - Unique: (country, taxId)
   - Phases: DRAFT → SUBMITTED → VETTED | REJECTED
2) CampaignRegistration (what/why; use case under a Brand)
   - Single use case: CustomerCare.MissedCallRecovery
   - Unique: one ACTIVE campaign per (brandId, useCase)
   - Phases: DRAFT → SUBMITTED → APPROVED → ACTIVE | REJECTED | SUSPENDED
3) PhoneNumberBinding (link artifact: number ↔ campaign)
   - Invariant: an E.164 can be bound to exactly one campaign at a time
   - Phases: REQUESTED → ATTACHED → VERIFIED | FAILED | DETACHED

Notes:
- Treat PhoneNumber as an external asset/value object (E.164 + provider refs). Its lifecycle
  belongs to Telephony Integration (another context), not here.

RECONCILIATION LOOP (Core Behavior)
- Three controllers: Brand, Campaign, Binding. Each compares desired spec vs provider state,
  issues idempotent create/update/link calls, and updates status.conditions.
- Triggers: spec changes (generation bump), periodic timer, optional provider webhooks.
- Backoff with jitter; DLQ and alert after max attempts.
- Outbox events on state transitions.

PROVIDER PORT (Abstraction)
Define a provider interface (A2PProviderPort) with minimal methods:
- ensure_brand(BrandSpec) -> ExternalRefs | Pending
- ensure_campaign(CampaignSpec, brand_external) -> ExternalRefs | Pending
- ensure_messaging_service(campaign_external) -> MessagingServiceId
- attach_number(ms_id, e164) -> Attached | Pending
- poll_status(external_ids) -> {phase, conditions}
Rules:
- One Messaging Service per campaign.
- A campaign may have many numbers; a number may belong to one campaign at a time.

API (HTTP surface; write desired state, never block)
Brands
- POST /brands → create/upsert BrandRegistration (DRAFT)
- POST /brands/{brandId}:submit → mark SUBMITTED; reconciler drives to VETTED/REJECTED
- GET  /brands/{brandId} → {spec, status.phase, conditions[], externalRefs, observedGeneration}

Campaigns
- POST /campaigns → create CampaignRegistration (DRAFT) for brandId, useCase fixed
- POST /campaigns/{campaignId}:submit → SUBMITTED; reconciler to APPROVED/ACTIVE/REJECTED
- GET  /campaigns/{campaignId} → {spec, status, externalRefs (campaignId, messagingServiceId)}

Number Bindings
- POST /numbers:attach {campaignId, e164} → REQUESTED; reconciler attaches and verifies
- POST /numbers:detach {e164} → DETACHED
- GET  /numbers/{e164} → {campaignId?, status.phase, conditions[]}

HTTP Semantics
- 201/200: spec stored
- 202: work enqueued; not complete
- 409: invariant violation (e.g., number bound elsewhere; second active campaign)
- 422: invalid/missing compliance fields
- 404: missing resource
- 5xx: only for real server failures

VALIDATION (Fail Fast)
- Brand: country, taxId (EIN), legalName, websiteDomain, support contact.
- Campaign: optInDescription, at least one sample message, STOP/HELP text present,
  linkDomains owned by the Brand (no generic shorteners).
- Binding: E.164 format; number must be available in provider.

GATING LOGIC (Downstream)
- Outbound SMS in other services must be hard-gated on:
  Brand=VETTED AND Campaign=ACTIVE AND ≥1 Number=VERIFIED.
- Emit A2PReady{brandId,campaignId,numbers[]} when all conditions are met.

OUTBOUND WEBHOOKS (Events you emit)
- Types: BrandVetted, BrandRejected, CampaignApproved, CampaignActivated,
  CampaignRejected, NumberAttached, NumberVerified, NumberAttachFailed, A2PReady.
- Delivery: at-least-once; per-aggregate ordering; include sequence.
- Security: HMAC-SHA256 over timestamp+body with tenant secret; 5s timeout; exponential retries.
- Replay endpoint for N days.
- Include eventId and aggregateId; bodies are idempotent.

OBSERVABILITY
- Metrics: reconcile_runs_total{resource}, provider_calls_total{method},
  status_phase_gauge{resource,phase}, webhook_delivery_attempts_total,
  idempotency_dupes_total, assignment_conflicts_total.
- Structured logs (no raw PII); trace each reconcile with aggregateId/providerRef.

IDEMPOTENCY & KEYS
- Support Idempotency-Key header on POSTs.
- Natural dedupe:
  Brand: hash(country|taxId)
  Campaign: hash(tcrBrandId|useCase|canonical(linkDomains))
  Binding: hash(messagingServiceId|E164)
- Reconciler operations must be idempotent against provider.

PERSISTENCE & CONSISTENCY
- Surrogate PKs: brandId, campaignId, bindingId (or use E.164 as natural key for binding).
- Uniques: (country,taxId), (brandId,useCase,active=true), E164 globally unique in bindings.
- Use transactional outbox for events; never emit outside a committed transaction.

RATE LIMITS (for senders downstream, not here)
- Campaign-level token bucket suggested; optional brand-level daily caps if provider exposes them.

SECURITY & TENANCY
- Per-tenant row-level isolation; auth required on all endpoints.
- Encrypt PII at rest; audit trails for provider calls (store hashes where feasible).

HAPPY PATH (Narrative)
1) Create + submit Brand → reconciler vets → Brand=VETTED (event BrandVetted).
2) Create + submit Campaign → reconciler approves/activates → Campaign=ACTIVE (event CampaignActivated).
3) Attach number(s) → reconciler attaches/verifies → Number=VERIFIED (event NumberVerified).
4) Emit A2PReady; downstream messaging flips canSend=true.

DELAY / FAILURE BEHAVIOR
- API returns immediately with 201/202; progress is via status + events.
- Reconciler polls + handles provider webhooks; retries with backoff.
- Reject/Conflicts surfaced in status.conditions and via events; allow edit+resubmit.

QUALITY BAR
- Pure domain logic has no I/O.
- Ports for repos, outbox, provider; adapters implement them.
- Tests must enforce invariants and event emission on transitions.
- No synchronous “approval wizard” flows; everything is eventual.

END OF CONTRACT


Perfect. Here are **copy-paste-ready step blocks** you can drop into your codegen tool **after** the system brief. Each block is self-contained, prescriptive, and test-driven. No code in the prompt—just contracts and constraints.

---

```text
STEP 0 — SCAFFOLD + TOOLING

Goal: Create repo scaffolding, app factory, config, health check. No domain logic.

Allowed paths:
- /app/** (new)
- /tests/** (new)
- /alembic/** (empty for now)
- pyproject.toml, Makefile, .env.example

Do NOT modify: (none; first step)

Requirements:
- FastAPI app factory `create_app()`.
- Pydantic Settings for config (env-driven).
- Structured logging helper.
- Health endpoint GET /health -> 200 {"status":"ok"}.
- Tooling: ruff, mypy, pytest, uvicorn, httpx, SQLAlchemy, Alembic.
- Basic DI container (simple provider registry).

Tests to write (/tests/smoke/test_health.py):
- App starts; GET /health returns 200 + JSON schema.
- Settings load from environment (override via env vars).

Definition of Done:
- `make test` passes; `ruff` & `mypy` clean.
- No TODOs, no placeholders.
```

---

```text
STEP 1 — CONTRACTS FIRST (OPENAPI + EVENT SCHEMAS)

Goal: Author OpenAPI + JSON Schemas for outbound events. No handlers.

Allowed paths:
- /app/contracts/openapi.yaml
- /app/contracts/events/*.json
- /tests/contracts/**

Do NOT modify: Anything outside /app/contracts and /tests/contracts.

Requirements:
- OpenAPI routes:
  - POST /brands
  - POST /brands/{brandId}:submit
  - GET  /brands/{brandId}
  - POST /campaigns
  - POST /campaigns/{campaignId}:submit
  - GET  /campaigns/{campaignId}
  - POST /numbers:attach
  - POST /numbers:detach
  - GET  /numbers/{e164}
- Define request/response objects with `spec`, `status.phase`, `conditions[]`, `externalRefs`, `observedGeneration`.
- HTTP codes: 200/201/202/409/422/404 as per brief.
- Event schemas (JSON Schema Draft 2020-12):
  - BrandVetted, BrandRejected, CampaignApproved, CampaignActivated, CampaignRejected,
    NumberAttached, NumberVerified, NumberAttachFailed, A2PReady.
- Webhook signature headers documented (HMAC over timestamp+body).

Tests to write:
- Validate OpenAPI with openapi-spec-validator.
- Validate example event payloads against JSON Schemas (ajv-like lib or python equivalent).
- Ensure all routes present with correct verbs and response codes.

Definition of Done:
- `make test` green; contracts compile; no endpoints implemented yet.
```

---

```text
STEP 2 — DOMAIN MODEL (PURE)

Goal: Implement pure domain aggregates and invariants. No I/O.

Allowed paths:
- /app/domain/{brands.py,campaigns.py,binding.py,events.py,errors.py}
- /tests/domain/**

Do NOT modify: contracts or scaffold.

Requirements:
- Aggregates:
  - BrandRegistration: identity (country,taxId), legalName, displayName, websiteDomain, brandType; phases DRAFT|SUBMITTED|VETTED|REJECTED.
  - CampaignRegistration: brandId, useCase fixed "CustomerCare.MissedCallRecovery"; phases DRAFT|SUBMITTED|APPROVED|ACTIVE|REJECTED|SUSPENDED; invariant: one ACTIVE per brand/useCase.
  - PhoneNumberBinding: e164, campaignId; phases REQUESTED|ATTACHED|VERIFIED|FAILED|DETACHED; invariant: one campaign per e164.
- State transition methods + guards; emit domain events (typed in events.py).
- No imports from FastAPI/DB/httpx.

Tests to write:
- Brand: cannot change (country,taxId) after SUBMITTED; VETTED precondition.
- Campaign: cannot activate if brand not VETTED; enforce single ACTIVE per brand/useCase.
- Binding: attach fails if e164 already bound; verify only after attach.

Definition of Done:
- 100% domain coverage on critical branches; pure functions/classes only.
```

---

```text
STEP 3 — PERSISTENCE PORTS + OUTBOX PORT (INTERFACES ONLY)

Goal: Define repository ports and outbox interface. No implementations.

Allowed paths:
- /app/domain/repos.py
- /app/infra/outbox/port.py
- /tests/ports/**

Do NOT modify: domain aggregates.

Requirements:
- Protocols/ABCs:
  - BrandRepo, CampaignRepo, BindingRepo (get/save/find-by…; atomic save; uniqueness errors).
  - OutboxPort.publish(event) append-only with sequence per aggregate.
- Error taxonomy types (Conflict, NotFound).

Tests to write:
- Type-checking tests using typing.Protocol (isinstance duck-typing).
- Fake in-memory stubs for tests only to prove interface shape.

Definition of Done:
- Mypy passes on interfaces; no DB code.
```

---

```text
STEP 4 — DB ADAPTERS + MIGRATIONS

Goal: Concrete SQLAlchemy repos, models, and transactional outbox.

Allowed paths:
- /app/infra/db/{models.py,repos.py,session.py}
- /app/infra/outbox/{sql_outbox.py}
- /alembic/** (init + migration_0001)
- /tests/infra_db/**

Do NOT modify: domain or ports.

Requirements:
- Models map aggregates; unique constraints:
  - Brand: (country,taxId) unique.
  - Campaign: (brandId,useCase,active=true) unique partial.
  - Binding: e164 unique.
- Transaction pattern: save aggregate + append outbox message atomically.
- SQLite test DB; Postgres-ready DDL (use alembic).
- Map status.phase, conditions (JSON), externalRefs (JSON).

Tests to write:
- CRUD + uniqueness violations raise domain Conflict.
- Outbox writes within same transaction as aggregate.
- Migration creates all tables; reversible.

Definition of Done:
- Alembic upgrade/downgrade works; tests green.
```

---

```text
STEP 5 — PROVIDER PORT + FAKE PROVIDER

Goal: Provider abstraction and a deterministic fake with delays.

Allowed paths:
- /app/adapters/provider_port.py
- /app/adapters/fake_provider.py
- /tests/provider_fake/**

Do NOT modify: DB or domain.

Requirements:
- A2PProviderPort methods:
  - ensure_brand(BrandSpec) -> ExternalRefs|Pending
  - ensure_campaign(CampaignSpec, brand_ext) -> ExternalRefs|Pending
  - ensure_messaging_service(campaign_ext) -> MsId
  - attach_number(ms_id,e164) -> Attached|Pending
  - poll_status(external_ids) -> {phase,conditions}
- FakeProvider:
  - Configurable approval delays; deterministic via seed.
  - Can simulate REJECTED by flags.
  - Stores created objects in-memory.

Tests to write:
- Happy path: progresses from pending to approved/active.
- Rejection path: returns REJECTED with reason in conditions.
- Idempotency: repeated ensure_* calls are no-ops.

Definition of Done:
- Port stable; Fake passes contract tests.
```

---

```text
STEP 6 — RECONCILIATION ENGINE (SKELETON)

Goal: Three controllers + scheduler; idempotent convergence.

Allowed paths:
- /app/recon/{brand_controller.py,campaign_controller.py,binding_controller.py,scheduler.py}
- /tests/recon/**

Do NOT modify: domain/contracts/ports.

Requirements:
- Controllers fetch aggregate, compare desired vs provider, call provider port, update status, emit events via OutboxPort.
- Backoff with jitter; nextRunAt stored per aggregate.
- Scheduler tick: processes limited batch per controller; no in-memory state reliance.

Tests to write:
- With FakeProvider, end-to-end: DRAFT/SUBMITTED → VETTED/ACTIVE/VERIFIED over ticks.
- Backoff increases after transient failures; resets on success.
- Events appended to outbox on transitions.

Definition of Done:
- Deterministic runs; no busy loops; tests green.
```

---

```text
STEP 7 — API HANDLERS (WRITE SPEC; NEVER BLOCK)

Goal: Implement HTTP routes per OpenAPI. Persist specs, enqueue reconcile.

Allowed paths:
- /app/api/{brands.py,campaigns.py,numbers.py,router.py}
- /app/main.py (wire router only)
- /tests/api/**

Do NOT modify: contracts file; domain invariants.

Requirements:
- POSTs: store/validate spec; return 201 or 202 as appropriate.
- GETs: return current spec + status + externalRefs.
- Enforce invariants with 409/422.
- Accept Idempotency-Key (dedupe).

Tests to write:
- Route existence and schemas match OpenAPI (golden assertions).
- Status codes: 201/202/409/422 paths.
- Creating campaign under non-VETTED brand → 202 on submit but progress blocked until brand VETTED.

Definition of Done:
- OpenAPI conformance tests pass; no provider calls inside handlers.
```

---

```text
STEP 8 — OUTBOUND WEBHOOK DISPATCHER

Goal: At-least-once event delivery with HMAC, retries, replay.

Allowed paths:
- /app/api/webhooks.py (registration + test endpoint)
- /app/infra/outbox/{dispatcher.py,signing.py}
- /tests/webhooks/**

Do NOT modify: recon controllers.

Requirements:
- Webhook registry (URL + secret + active flag).
- Dispatcher pulls ordered events per aggregate; delivers with HMAC-SHA256 header set; 5s timeout; backoff schedule; dead-letter after N attempts; replay endpoint.
- Headers: X-NMC-Event, X-NMC-EventId, X-NMC-Sequence, X-NMC-Aggregate-Id, X-NMC-Timestamp, X-NMC-Signature.

Tests to write:
- Successful delivery path; signature verifies.
- Duplicate deliveries: consumer idempotency validated in test double.
- Replay sends identical body/signature (modulo timestamp handling spec).

Definition of Done:
- Dispatcher runs in background loop; metrics counters exposed later.
```

---

```text
STEP 9 — TWILIO ADAPTER (CONCRETE PROVIDER)

Goal: Implement A2PProviderPort against Twilio APIs (TrustHub/A2P/Messaging Service).

Allowed paths:
- /app/adapters/twilio/{adapter.py,mapping.py,client.py}
- /tests/twilio_contracts/**

Do NOT modify: provider port signature.

Requirements:
- httpx client with retries + circuit breaker.
- Map domain → Twilio entities:
  - Brand ↔ TrustHub Business Profile
  - Campaign ↔ A2P campaign (10DLC)
  - Messaging Service per campaign; link phone numbers
- Idempotent ensure_* operations keyed by externalRefs/SIDs.
- Secrets/env vars only; no hardcoded tokens.

Tests to write:
- Contract tests using recorded/mocked responses (no live calls).
- Idempotency: repeating ensure_* does not duplicate.
- Error mapping: Twilio 4xx → domain 422/409; 5xx → retry.

Definition of Done:
- FakeProvider tests still pass; Twilio adapter passes contract suite (mocked).
```

---

```text
STEP 10 — INBOUND PROVIDER WEBHOOKS + POLLING

Goal: Accept provider callbacks to accelerate status; keep polling.

Allowed paths:
- /app/api/provider_webhooks.py
- /app/recon/poller.py
- /tests/provider_inbound/**

Do NOT modify: existing controllers’ logic signatures.

Requirements:
- Parse Twilio callback(s); validate signatures; update externalRefs/status.conditions; enqueue reconcile immediately.
- Background poller to poll lagging items periodically (still required).

Tests to write:
- Valid webhook advances phase; invalid signature rejected.
- Poller wakes stuck items (simulate missed webhooks).

Definition of Done:
- System still converges with webhooks disabled; webhooks just speed it up.
```

---

```text
STEP 11 — GUARDRAILS + OBSERVABILITY

Goal: Compliance validators + metrics + health/readiness + per-campaign rate limiter hooks (for downstream usage).

Allowed paths:
- /app/domain/validators.py
- /app/observ/{metrics.py,health.py}
- /app/api/metrics.py
- /tests/validation_obs/**

Do NOT modify: contracts.

Requirements:
- Validate STOP/HELP presence; linkDomains belong to Brand’s domain; block generic shorteners.
- Expose /metrics (Prometheus): reconcile_runs_total, provider_calls_total, status_phase_gauge{resource,phase}, webhook_delivery_attempts_total, idempotency_dupes_total, assignment_conflicts_total.
- Readiness/health endpoints extended (DB, queue).
- Token-bucket scaffolding keyed by campaignId (no sender here; just provide util).

Tests to write:
- Validation rejects bad campaign specs (422).
- Metrics endpoints return expected families.
- Token-bucket utility behaves deterministically.

Definition of Done:
- Validators enforced on API writes; metrics observable; tests green.
```

---

### How to use these

1. Paste the **system brief** first.
2. Paste one **STEP block**.
3. Run the generated code; ensure tests pass.
4. Freeze the files touched in that step.
5. Move to the next step.

Stay disciplined. Small steps, locked contracts, always with tests.


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


Fair. You want **tiny, append-only drops** that any LLM can generate (\~300 LOC max each), with **zero edits** to prior code. Here’s the plan: **12 nano-steps**, each independent, each producing new files only, each with tests. You compose them by importing previous modules—never rewriting them.

I’ve given you **copy-paste blocks**. Use one per run.

---

```text
NANO-STEP S0 — CORE CONTRACTS (TYPES + ERRORS)

Goal
Define enums, dataclasses, and error types used by later steps. No I/O, no ORM, no HTTP.

Allowed paths
- /pkg_core/__init__.py
- /pkg_core/types.py         # Enums: BrandPhase, CampaignPhase, BindingPhase, BrandType
- /pkg_core/models.py        # dataclasses: BrandSpec, CampaignSpec, BindingSpec, Condition
- /pkg_core/errors.py        # DomainError, ConflictError, ValidationError, NotFoundError
- /tests_core/**

Requirements
- Pure Python (stdlib only). Dataclasses or pydantic BaseModel (your pick, but keep it light).
- Phases and BrandType must match earlier brief.
- Zero external deps except pydantic (optional).

Tests to write
- Enum values exist and are comparable.
- Dataclass validation (minimal): cannot build CampaignSpec without stop/help text or link_domains.

LOC budget
- Code ≤ 200 LOC, Tests ≤ 120 LOC.
```

---

```text
NANO-STEP S1 — BRAND DOMAIN + IN-MEMORY REPO

Goal
Implement BrandRegistration aggregate behavior and a minimal in-memory repository. No DB, no HTTP.

Allowed paths
- /pkg_brand_domain/__init__.py
- /pkg_brand_domain/aggregate.py     # BrandRegistration with phase transitions
- /pkg_brand_domain/repo_memory.py   # InMemoryBrandRepo adhering to simple interface
- /tests_brand_domain/**

Dependencies
- import from pkg_core only.

Requirements
- Methods: create(spec)->Brand, submit()->Brand (DRAFT→SUBMITTED).
- Repo interface (inline here): get(brand_id), get_by_tax_id(tenant_id,country,tax_id), save(brand).
- Enforce uniqueness (country,tax_id) inside memory repo.

Tests to write
- Happy path create→submit.
- Duplicate tax_id raises ConflictError.
- Phase cannot go SUBMITTED→DRAFT.

LOC budget
- Code ≤ 220 LOC, Tests ≤ 120 LOC.
```

---

```text
NANO-STEP S2 — CAMPAIGN DOMAIN + IN-MEMORY REPO

Goal
CampaignRegistration aggregate + in-memory repo enforcing basic invariants.

Allowed paths
- /pkg_campaign_domain/__init__.py
- /pkg_campaign_domain/aggregate.py
- /pkg_campaign_domain/repo_memory.py
- /tests_campaign_domain/**

Dependencies
- pkg_core for types/errors.

Requirements
- Single useCase constant: "CustomerCare.MissedCallRecovery".
- Methods: create(spec)->Campaign, submit()->Campaign (DRAFT→SUBMITTED).
- Invariant placeholder: track `active` flag; only one active per (brand_id,useCase) in repo.
- Repo interface (inline): get(campaign_id), find_active_by_brand_use_case(brand_id,useCase), save(campaign).

Tests to write
- Create→submit OK.
- Two active campaigns for same pair -> ConflictError (simulate set_active()).
- Missing STOP/HELP or link_domains -> ValidationError on create.

LOC budget
- Code ≤ 240 LOC, Tests ≤ 140 LOC.
```

---

```text
NANO-STEP S3 — BINDING DOMAIN + IN-MEMORY REPO

Goal
PhoneNumberBinding aggregate + in-memory repo enforcing one-number-one-campaign.

Allowed paths
- /pkg_binding_domain/__init__.py
- /pkg_binding_domain/aggregate.py
- /pkg_binding_domain/repo_memory.py
- /tests_binding_domain/**

Dependencies
- pkg_core for types/errors.

Requirements
- Methods: request_attach(e164,campaign_id)->Binding (phase REQUESTED), verify()->VERIFIED, detach()->DETACHED.
- Repo interface (inline): get_by_e164(e164), save(binding), detach(e164).
- Enforce unique e164 globally in repo.

Tests to write
- Attach→verify success path.
- Attach same e164 twice -> ConflictError.
- Detach frees e164 for reuse.

LOC budget
- Code ≤ 220 LOC, Tests ≤ 120 LOC.
```

---

```text
NANO-STEP S4 — IN-MEMORY OUTBOX + EVENTS

Goal
Append-only outbox and simple event types. No DB.

Allowed paths
- /pkg_outbox_mem/__init__.py
- /pkg_outbox_mem/events.py       # Event dataclasses: BrandSubmitted, CampaignSubmitted, NumberAttachRequested, NumberDetached
- /pkg_outbox_mem/outbox.py       # InMemoryOutbox with append(list) and read_all()
- /tests_outbox_mem/**

Dependencies
- pkg_core for errors/types.

Requirements
- At-least-once semantics simulated; keep order of append calls.
- Event structure includes event_id (uuid), aggregate_type, aggregate_id, occurred_at.

Tests to write
- Append preserves order and idempotency when given same event_id twice (drop duplicate).

LOC budget
- Code ≤ 180 LOC, Tests ≤ 100 LOC.
```

---

```text
NANO-STEP S5 — SQLITE PERSISTENCE: BRANDS ONLY

Goal
Standalone SQLite repo for brands with schema creation routine.

Allowed paths
- /pkg_brand_sqlite/__init__.py
- /pkg_brand_sqlite/schema.py      # create tables if not exist
- /pkg_brand_sqlite/repo_sqlite.py # BrandRepoSQLite implementing S1 interface
- /tests_brand_sqlite/**

Dependencies
- pkg_core, standard library sqlite3 (no SQLAlchemy).

Requirements
- Tables: brands (tenant_id, brand_id, country, tax_id, legal_name, display_name, website_domain, brand_type, phase, conditions_json, observed_generation, created_at, updated_at, tcr_brand_id, provider_brand_sid), UNIQUE(tenant_id,country,tax_id).
- Methods: get, get_by_tax_id, save, update_phase.
- Serialize conditions as JSON.

Tests to write
- Schema creation works.
- Create/get roundtrip.
- Uniqueness conflict enforced by DB (map to ConflictError).

LOC budget
- Code ≤ 300 LOC, Tests ≤ 150 LOC.
```

---

```text
NANO-STEP S6 — SQLITE PERSISTENCE: CAMPAIGNS ONLY

Goal
SQLite repo for campaigns with partial unique on ACTIVE.

Allowed paths
- /pkg_campaign_sqlite/__init__.py
- /pkg_campaign_sqlite/schema.py
- /pkg_campaign_sqlite/repo_sqlite.py
- /tests_campaign_sqlite/**

Dependencies
- pkg_core, sqlite3.

Requirements
- campaigns table with columns from the brief; boolean `active`; UNIQUE(tenant_id,brand_id,use_case,active) enforced via partial uniqueness emulation: use a trigger to fail when inserting/updating a second active row for same keys.
- Methods: get, find_active_by_brand_use_case, save, set_active, update_phase.

Tests to write
- Create→set_active works.
- Second set_active for same brand/use_case fails (ConflictError).
- Phase updates persist.

LOC budget
- Code ≤ 300 LOC, Tests ≤ 170 LOC.
```

---

```text
NANO-STEP S7 — SQLITE PERSISTENCE: BINDINGS ONLY

Goal
SQLite repo for number bindings with global e164 uniqueness.

Allowed paths
- /pkg_binding_sqlite/__init__.py
- /pkg_binding_sqlite/schema.py
- /pkg_binding_sqlite/repo_sqlite.py
- /tests_binding_sqlite/**

Dependencies
- pkg_core, sqlite3.

Requirements
- bindings table with UNIQUE(tenant_id,e164).
- Methods: get_by_e164, save(binding with REQUESTED), update_phase (ATTACHED/VERIFIED), detach (mark DETACHED and free uniqueness by either soft-delete row or keep row with unique loosened via nullable tenant_id on DETACHED).
- Keep it simple: on detach, delete row.

Tests to write
- Attach same e164 twice → ConflictError.
- Detach then re-attach succeeds.

LOC budget
- Code ≤ 240 LOC, Tests ≤ 140 LOC.
```

---

```text
NANO-STEP S8 — SQLITE IDEMPOTENCY STORE

Goal
Idempotency table + helper.

Allowed paths
- /pkg_idem_sqlite/__init__.py
- /pkg_idem_sqlite/schema.py
- /pkg_idem_sqlite/store.py
- /tests_idem_sqlite/**

Dependencies
- pkg_core, sqlite3.

Requirements
- Table idempotency_keys(tenant_id, route, key, response_json, status_code, created_at) with UNIQUE(tenant_id,route,key).
- Helper `with_idempotency(conn, tenant_id, route, key, compute_resp_fn)`:
  - On hit: return stored (status_code, body).
  - On miss: call compute_resp_fn(); store and return.

Tests to write
- First call stores; second returns cached.
- Different key produces fresh entry.

LOC budget
- Code ≤ 180 LOC, Tests ≤ 120 LOC.
```

---

```text
NANO-STEP S9 — SQLITE OUTBOX

Goal
Append-only outbox table + repo.

Allowed paths
- /pkg_outbox_sqlite/__init__.py
- /pkg_outbox_sqlite/schema.py
- /pkg_outbox_sqlite/repo_sqlite.py
- /tests_outbox_sqlite/**

Dependencies
- pkg_core, sqlite3.

Requirements
- Table outbox_events(id, tenant_id, aggregate, aggregate_id, event_type, payload_json, created_at).
- Repo: append(event), list_since(tenant_id, after_id).
- No dispatcher, just storage.

Tests to write
- Append N events and list_since returns correct slice.
- Payload roundtrips JSON intact.

LOC budget
- Code ≤ 180 LOC, Tests ≤ 100 LOC.
```

---

```text
NANO-STEP S10 — HTTP FACADE: BRANDS (IN-PROCESS SQLITE)

Goal
Minimal FastAPI app exposing Brand endpoints using S5 + S8 + S9. No other endpoints.

Allowed paths
- /svc_brands_api/__init__.py
- /svc_brands_api/app.py            # FastAPI app factory; inject sqlite conn; mount routes
- /svc_brands_api/routes.py
- /svc_brands_api/dto.py
- /tests_brands_api/**

Dependencies
- pkg_core, pkg_brand_sqlite, pkg_idem_sqlite, pkg_outbox_sqlite, fastapi, pydantic.

Requirements
- Routes:
  - POST /brands (Idempotency-Key optional)
  - POST /brands/{brandId}:submit
  - GET  /brands/{brandId}
- Behavior:
  - Write desired state quickly; use idempotency store for POSTs.
  - On POSTs, also append a simple outbox event (BrandSubmitted for :submit).
- Validation: legalName, taxId, country='US', websiteDomain non-empty.

Tests to write
- Happy path POST→:submit→GET.
- Idempotency: same key returns stored response.
- Outbox gets BrandSubmitted on :submit.

LOC budget
- Code ≤ 300 LOC, Tests ≤ 200 LOC.
```

---

```text
NANO-STEP S11 — HTTP FACADE: CAMPAIGNS

Goal
FastAPI routes for campaigns using S6 + S8 + S9.

Allowed paths
- /svc_campaigns_api/__init__.py
- /svc_campaigns_api/app.py
- /svc_campaigns_api/routes.py
- /svc_campaigns_api/dto.py
- /tests_campaigns_api/**

Dependencies
- pkg_core, pkg_campaign_sqlite, pkg_idem_sqlite, pkg_outbox_sqlite, fastapi, pydantic.

Requirements
- Routes:
  - POST /campaigns
  - POST /campaigns/{campaignId}:submit
  - GET  /campaigns/{campaignId}
- Validate STOP/HELP and link_domains, use fixed useCase.
- Map DB uniqueness violation to 409 when attempting to mark active (you may stub active=false in this facade; still enforce validation and submission).

Tests to write
- Create invalid (no STOP/HELP) -> 422.
- Create valid -> 201; :submit -> 202; GET shows SUBMITTED.

LOC budget
- Code ≤ 300 LOC, Tests ≤ 200 LOC.
```

---

```text
NANO-STEP S12 — HTTP FACADE: NUMBER BINDINGS

Goal
FastAPI routes for number bindings using S7 + S8 + S9.

Allowed paths
- /svc_bindings_api/__init__.py
- /svc_bindings_api/app.py
- /svc_bindings_api/routes.py
- /svc_bindings_api/dto.py
- /tests_bindings_api/**

Dependencies
- pkg_core, pkg_binding_sqlite, pkg_idem_sqlite, pkg_outbox_sqlite, fastapi, pydantic.

Requirements
- Routes:
  - POST /numbers:attach
  - POST /numbers:detach
  - GET  /numbers/{e164}
- Behavior:
  - Attach → phase=REQUESTED; append NumberAttachRequested to outbox.
  - Detach deletes or marks DETACHED; append NumberDetached.
- Validation: E.164 regex.

Tests to write
- Attach same e164 twice -> 409.
- Detach then re-attach works.
- Idempotency on attach with same key returns identical response.

LOC budget
- Code ≤ 280 LOC, Tests ≤ 180 LOC.
```

---

### How to run this without pain

* Treat each nano-step as a **separate package/folder**. Don’t edit prior steps; only **import** them.
* Keep each response small; cap code LOC per step as specified.
* If you need integration later, create a **thirteenth tiny “glue” service** that mounts all three routers into one FastAPI app—again in a new folder.

**Bottom line:** this decomposition keeps every drop ≤300 LOC of code, with tests, and zero rewrites. You append new, small packages; you never mutate old ones. That’s how you stay inside AI’s competence envelope.






--------------------------------------------------------------------------
--------------------------------------------------------------------------



---

# A2P Registration API (v1) — concise spec

**Base:** `https://api.nevermisscall.com/v1`
**Auth:** `Authorization: Bearer <token>` (per-tenant)
**Headers:** `Content-Type: application/json`, `Accept: application/json`, `Idempotency-Key` on POSTs (optional, recommended)

## Enums

* **BrandPhase:** `DRAFT | SUBMITTED | VETTED | REJECTED`
* **CampaignPhase:** `DRAFT | SUBMITTED | APPROVED | ACTIVE | REJECTED | SUSPENDED`
* **BindingPhase:** `REQUESTED | ATTACHED | VERIFIED | FAILED | DETACHED`
* **BrandType:** `STANDARD | SOLE_PROP`

## Common shapes

* **Status:** `{ "phase": <Enum>, "conditions": [ { "type": str, "status": "True|False", "reason": str, "message": str, "lastTransitionTime": ISO8601 } ], "observedGeneration": int, "externalRefs": { ... } }`
* **Error:** `{"error": {"code": "ValidationError|ConflictError|NotFound", "message": str, "details": {...}}}`

---

## Brands

* **POST /brands → 201** (create DRAFT)
  Body: `{ country:"US", taxId, legalName, displayName, websiteDomain, supportEmail?, brandType }`
  Resp: `{ brandId, spec:{...}, status }`

* **POST /brands/{brandId}\:submit → 202** (set SUBMITTED)
  Resp: `{ brandId, status }`

* **GET /brands/{brandId} → 200**
  Resp: `{ brandId, spec:{...}, status }`

Validation: require `country="US"`, `taxId`, `legalName`, `websiteDomain`.

---

## Campaigns  *(single use case: `"CustomerCare.MissedCallRecovery"`)*

* **POST /campaigns → 201** (create DRAFT)
  Body: `{ brandId, useCase:"CustomerCare.MissedCallRecovery", optInDescription, sampleMessages:[str], stopHelpText, linkDomains:[url] }`
  Resp: `{ campaignId, brandId, spec:{...}, status }`

* **POST /campaigns/{campaignId}\:submit → 202** (set SUBMITTED)
  Resp: `{ campaignId, status }`

* **GET /campaigns/{campaignId} → 200**
  Resp: `{ campaignId, brandId, spec:{...}, status }`

Validation: `stopHelpText` must include **STOP** and **HELP**; `sampleMessages[0]` present; `linkDomains` non-empty (no generic shorteners).

---

## Number bindings

* **POST /numbers\:attach → 202** (REQUESTED)
  Body: `{ campaignId, e164 }`
  Resp: `{ e164, campaignId, status }`

* **POST /numbers\:detach → 200** (DETACHED)
  Body: `{ e164 }`
  Resp: `{ e164, status }`

* **GET /numbers/{e164} → 200**
  Resp: `{ e164, campaignId?, status }`

Invariant: one active binding per `e164` per tenant.

---

## HTTP semantics

* Success: **201** (create), **202** (submitted/requested), **200** (read/detach)
* Errors: **422** invalid, **409** conflict/invariant, **404** missing, **401/403** auth, **429** rate limit, **5xx** server

## Idempotency

* On POST: if `Idempotency-Key` repeats for same tenant+route, return **exact prior** status/body (24h).

## Notes

* API writes set **desired state** only; provider activation is out-of-scope/async elsewhere.
* Downstream systems must gate sending on: `Brand=VETTED` **and** `Campaign=ACTIVE` **and** `≥1 Binding=VERIFIED`.
