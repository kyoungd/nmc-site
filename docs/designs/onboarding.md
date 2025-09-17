
# Page 1 — Account (no plan picker)

**Basic (visible)**

* `displayName` *(prefill from Stripe; editable)*
* `vertical` *(prefill guess from Stripe MCC/name; editable select)*
* `ownerEmailVerified` *(badge, read-only)*
* `ownerMobileVerified` *(badge, read-only)*
* **CTA:** “Continue”

**Advanced (collapsed)**

* `logoUrl` *(prefill from Stripe brand; upload optional)*
* `brandColor` *(prefill from logo; editable)*
* `timezone` *(prefill from browser/IP/address; editable)*
* `address` *(prefill from Stripe; editable)*
* `languages` *(default: `["en"]`; toggle `es`)*

**Hidden/derived**

* `stripeActive=true`, `planCode` (from Stripe)
* `tenantId`, `teamSizeLimit=1`, auto-create owner employee

---

# Page 2 — Number & Operating Setup

**Basic (visible)**

* `areaCode` *(prefill suggestion list: \[addr NPA, owner NPA, nearby]; default top suggestion)*
* `hours` *(Mon–Fri 08:00–18:00; weekends toggle; single compact control)*
* `serviceRadiusMi` *(slider, default 15)*
* **Number result banner** *(read-only after reserve): `e164`, `state`, `capabilities`*
* **CTA:** “Looks good”

**Advanced (collapsed)**

* `startPortIn` *(toggle)*

  * if true → `portIn.phoneNumber`, `accountNumber`, `pin`
* `ringWindowSec` *(default 20)*
* `ownerWindowSec` *(default 60, 30–180)*
* `afterHoursMode` *(default `AIOnly`)*
* `holidays` *(US federal preloaded; edit)*
* `stopHelpText` *(CTIA stock; read-only unless override)*

**Hidden/derived**

* `preferredAreaCodes[]` (ranked)
* Provisioning: auto-pick **local MMS** number (idempotent); store `providerSid`, `correlationId`
* Hard gate: **no outbound SMS** until A2P passes

---

# Page 3 — Calendar, Messaging & Pricing

**Basic (visible)**

* `calendarProvider` *(default “google”)*
* `connectCalendar` *(button → sets `calendarConnected=true`)*
* `topServices[]` *(chips; preselected 3 by vertical)*
* `priceRanges` *(inline min/max with defaults)*
* **CTA:** “Continue”

**Advanced (collapsed)**

* `doubleBookPolicy` *(default `block`)*
* `buffers.beforeMin`/`afterMin` *(defaults 15/15)*
* `templates.title`/`description` *(prefilled by vertical)*
* `bilingual` *(toggle `es`)*
* `revenuePromptsMins` *(default 120)*
* `attributionDays` *(default 14)*
* `opsEmails[]` *(seed owner email)*
* `opsSms[]` *(seed owner mobile)*
* `slackWebhookUrl` *(optional; validated)*

**Hidden/derived**

* `instantTextPreview` (computed)
* Template tokens resolved with `displayName`

---

# Page 4 — A2P 10DLC (Required to Text)

**Basic (visible)**

* `brandType` *(auto: `SOLE_PROP` if no EIN; else `STANDARD`; editable)*
* `legalBusinessName` *(prefill Stripe; editable)*
* `websiteUrl` *(prefill Stripe/email domain; editable)*
* `taxId` *(shown **only if** `brandType=STANDARD`; EIN format)*
* `authorizedContact.name/email/phoneE164` *(prefill Clerk/Stripe; editable)*
* **One-paragraph disclosure** + **Submit** button
* **Status pill** *(VETTED/ACTIVE/…)*

**Advanced (collapsed)**

* `useCase` *(locked: `CustomerCare.MissedCallRecovery`)*
* `optInDescription` *(locked: “Inbound only…”)*
* `sampleMessages[]` *(prefilled 2 with STOP/HELP; editable)*
* `stopHelpText` *(locked stock)*
* `linkDomains[]` *(prefill from website; editable, no public shorteners)*

**Hidden/derived**

* Checklist booleans: `httpsOk`, `privacyFound`, `termsFound`, `legalMatchesTaxIdLike`, `stopHelpPresent`
* Background polling & reason-code mapping
* Enable texting only when **Brand=VETTED & Campaign=ACTIVE & Binding=VERIFIED**

---

## Interaction rules (to keep it idiot-proof)

* **Max 3 inputs per Basic section.** Everything else goes Advanced or hidden.
* **Inline “Accepted defaults” chip** after we auto-fill; no walls of text.
* **Only surface blockers.** If a check fails (e.g., no Privacy page), show a single line with a “Fix” link, not a form dump.
* **Contextual reveal.** Port-in fields appear only when toggled; EIN appears only for `STANDARD`.
* **Undoable automation.** We auto-reserve a number; “Change number” link opens Advanced → area code list.

---

## Implementation notes (for you)

* Keep **Basic vs Advanced** as two form groups per page (`basic`, `advancedCollapsed=true`).
* Persist on blur/next; don’t force “Save” everywhere.
* In server guards, only validate **Basic** fields to advance; **Advanced** edits are optional refinements.

If you want, I’ll turn this into four Zod schemas with `.pick()` subsets for **Basic** and full schemas for **Advanced**, plus the minimal shadcn/ui layout skeletons.





**lightweight onboarding DB**, isolated with `ob_*` tables, **autosave as you go**, and a **clean handoff** to your main DB after finalize. Here’s the minimal, sane shape.

# 1) Authoritative state (one row per tenant)

**Table: `ob_flow`**

* `tenantId (pk, unique)`
* `phase` ∈ `ACCOUNT | NUMBER | CALMSG | A2P | FINALIZE | COMPLETE`
* `emailVerified (bool)` • `mobileVerified (bool)` • `stripeActive (bool)`
* `numberState` ∈ `null | Configured | PendingActivation | Porting | Active`
* `textingEligible (bool)` (computed gate: Brand=VETTED ∧ Campaign=ACTIVE ∧ Binding=VERIFIED)
* `completion` (jsonb) — `{ account:0-100, number:0-100, calmsg:0-100, a2p:0-100 }`
* `blockers` (jsonb\[]) — machine-detected reasons (e.g., `["WEBSITE_PRIVACY_MISSING"]`)
* `schemaVersion (int)` — for forward-compat of drafts
* `version (int)` — optimistic concurrency (increment on every write)
* `createdAt`, `updatedAt`

> Purpose: **step gating + autosave header**. UI only asks “what’s next?” from here.

# 2) Draft data (split by section; 1 row per section)

Keep it **simple** and **forgiving**: mostly JSONB with a few indexed columns you care about.

**Table: `ob_account`** (Page 1)

* `tenantId (pk, unique)`
* `displayName` **(Basic)**
* `vertical` **(Basic)**
* `logoUrl` *(Adv)* • `brandColor` *(Adv)*
* `timezone` *(Adv)* • `address` *(Adv, jsonb)* • `languages` *(Adv, text\[])*
* Prefill (read-only in UI, for audit): `ownerEmail`, `ownerMobileE164`
* `lastSavedAt`

**Table: `ob_number`** (Page 2)

* `tenantId (pk, unique)`
* `areaCode` **(Basic)**
* `hours` **(Basic, jsonb)** — compact structure: `{mon:{open,start,end}, ...}`
* `serviceRadiusMi` **(Basic, int)**
* `ringWindowSec` *(Adv,int=20)* • `ownerWindowSec` *(Adv,int=60)*
* `afterHoursMode` *(Adv,enum: AIOnly|QueueForHuman|CloseWithMsg)*
* `holidays` *(Adv, text\[])* • `stopHelpText` *(Adv, string; stock)*
* Provisioning outcome (read-only): `e164 (unique)`, `providerSid (unique)`, `capabilities (jsonb)`, `state`, `correlationId`
* Optional port-in: `portIn (jsonb)` — `{phoneNumber, accountNumber, pin}`
* `lastSavedAt`

**Table: `ob_calmsg`** (Page 3)

* `tenantId (pk, unique)`
* `calendarProvider` **(Basic, enum: google|none)** • `calendarConnected (bool)`
* `topServices` **(Basic, text\[], ≤3)**
* `priceRanges` **(Basic, jsonb)** — per service: `{min,max,currency}`
* `doubleBookPolicy` *(Adv)* • `buffers` *(Adv,jsonb)* • `templates` *(Adv,jsonb)*
* `bilingual` *(Adv,bool)* • `revenuePromptsMins` *(Adv,int)* • `attributionDays` *(Adv,int)*
* `opsEmails` *(Adv,text\[])* • `opsSms` *(Adv,text\[])* • `slackWebhookUrl` *(Adv)*
* `lastSavedAt`

**Table: `ob_a2p`** (Page 4)

* `tenantId (pk, unique)`
* **Brand inputs (Basic/Adv, prefilled):**
  `brandType (enum)`, `legalBusinessName`, `taxId?`, `websiteUrl`, `authorizedContact (jsonb)`
* **Campaign fixed bits (read-only):**
  `useCase="CustomerCare.MissedCallRecovery"`, `optInDescription="Inbound only..."`, `stopHelpText (stock)`
* **Campaign editable (Adv):** `sampleMessages (text[])`, `linkDomains (text[])`
* **Checklist (computed):** `httpsOk,bool` • `privacyFound,bool` • `termsFound,bool` • `legalMatchesTaxIdLike,bool` • `stopHelpPresent,bool`
* **Provider ids/status:** `brandId`, `brandPhase`, `campaignId`, `campaignPhase`, `bindingPhase`, `reason`, `correlationId`
* `lastSavedAt`

# 3) Autosave + concurrency (make it feel effortless)

* **Pattern:** Each page calls a single **server action** `save<Page>(partial, version)` on blur/step continue.
* **Validation:** Zod **partial** per page; merge into table row.
* **Versioning:** Read `ob_flow.version`; updates must include `version`; reject with 409 if stale (rare, but future-proof).
* **Progress:** After each save, recompute section `completion%` and `blockers`, then bump `ob_flow.version`.

# 4) Side-effects (provisioning/A2P) without coupling

**Table: `ob_outbox`** (minimal)

* `id (uuid, pk)`, `tenantId`, `type` ∈ `PROVISION_NUMBER | A2P_SUBMIT | A2P_REFRESH`
* `payload (jsonb)`, `attempts (int)`, `nextAttemptAt`, `status` ∈ `pending|done|failed`
* Worker executes calls to your **stateless** Provisioning/A2P services using **Idempotency-Key** = `tenantId:type`.

**Table: `ob_event`** (optional audit)

* `tenantId`, `ts`, `eventType`, `data (jsonb)` — for troubleshooting/resubmits.

# 5) Save-as-you-go: which fields are **Basic** vs **Advanced**

You already defined them. Persist both into the same table per page; **only Basic** gates phase progression. Advanced stays collapsed and optional.

# 6) State machine (kept tiny)

* `ACCOUNT → NUMBER → CALMSG → A2P → FINALIZE → COMPLETE`
* Guards (server-side):

  * leave `ACCOUNT` if `emailVerified && mobileVerified && stripeActive`
  * leave `NUMBER` if `ob_number.state='Configured' && capabilities.mms=true`
  * `FINALIZE` allowed iff `Brand=VETTED && Campaign=ACTIVE && Binding=VERIFIED`
* **We never call providers in the render path.** Outbox/worker only.

# 7) “Copy to main DB” handoff

* Create a **materialized snapshot** view (or API DTO) your copier can read:

  * **View:** `ob_snapshot` (SQL view that joins the four tables into one JSONB per tenant)

    * Columns: `tenantId, phase, textingEligible, snapshot (jsonb)`
  * Copier service watches for `ob_flow.phase='FINALIZE'` → copies snapshot into core DB → sets `COMPLETE`.
* Keep `ob_*` as **immutable audit** after completion.

# 8) Indexes & constraints (cheap safety)

* `ob_flow.tenantId (unique)`
* `ob_number.e164 (unique)` • `providerSid (unique)`
* Partial index to ensure **one** onboarding flow per tenant.
* Small check constraints: `ownerWindowSec BETWEEN 30 AND 180`, arrays `topServices` length ≤ 3.

# 9) What the UI shows (progressive disclosure)

* **Basic**: ≤3 inputs per page, plus one “Looks good/Continue”.
* **Advanced**: collapsed accordion; edits autosave the same row.
* **Status pills**: number state, A2P phases — read-only, small.

---

## TL;DR

Use **5 tables** (`ob_flow`, `ob_account`, `ob_number`, `ob_calmsg`, `ob_a2p`) + tiny `ob_outbox` (and optional `ob_event`). Autosave partials with optimistic concurrency, compute progress + blockers server-side, and expose a single **snapshot view** for your copier. That’s as simple as it gets without painting yourself into a corner.



-------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------



Perfect. Here are **ready-to-paste prompts** for your coding AI. Each step has a **BUILD** prompt and a **TEST** prompt. They’re self-contained: paste one prompt per session.

---

# BUILD — STEP 1 (Page 1: Account)

**Paste this whole block to your coding AI:**

```
SPEC_VERSION=2025-09-16

OVERVIEW_PEG:
App: Next.js(App Router, JS), Tailwind, shadcn/ui, RHF+Zod, Prisma(Postgres), Clerk, Stripe.
Isolation: Onboarding-only ob_* tables; main DB copied later by a separate service.
Flow: ACCOUNT → NUMBER → CALMSG → A2P → FINALIZE → COMPLETE (server-guarded).
UI: Basic ≤3 inputs visible/page; Advanced collapsed; autosave on blur/continue.
Hard Gate: No outbound SMS until Brand=VETTED && Campaign=ACTIVE && Binding=VERIFIED.
No provider calls in render. Server actions persist to ob_*.
Return shape from actions: { phase, completion, blockers, textingEligible }.
Simplicity > everything.

GOAL:
Implement Page 1 (Account) with Basic-only surface + Advanced accordion, autosave,
and server-side gating. No plan picker (already paid/trialled).

FILES (create/update):
1) app/(onboarding)/onboarding/account/page.js
2) app/(onboarding)/onboarding/_actions/step1_account.action.js
3) lib/ob/schemas/account.zod.js

BASIC (visible):
- displayName (prefill from Stripe; editable)
- vertical (prefill guess; editable select)
- badges: ownerEmailVerified, ownerMobileVerified (read-only)

ADVANCED (collapsed):
- logoUrl, brandColor, timezone, address, languages (["en"] default)

PREFILL SOURCES:
- Clerk: owner email/mobile + verification flags
- Stripe: business/display name, address, brand assets if present
- Heuristics: timezone from browser/IP

SERVER ACTION:
- Upsert ob_account with provided fields
- Update ob_flow.emailVerified/mobileVerified/stripeActive from systems
- Phase advance remains ACCOUNT unless all three are true; then allow redirect
- Return { phase, completion, blockers, textingEligible }

CONSTRAINTS:
- ≤300 LOC per file
- No provider calls in page render
- Only Basic gates progress; Advanced never blocks
- Autosave on blur/continue; optimistic toast “Saved”

ACCEPTANCE CRITERIA:
- With prefills, user can click Continue without typing
- ob_account row exists/updates
- Verified badges reflect Clerk
- Advanced collapsed by default and autosaves when expanded
```

---

# TEST — STEP 1 (Page 1: Account)

```
SPEC_VERSION=2025-09-16 (same overview peg as above)

GOAL:
Write tests to validate Page 1 behavior and server action logic.

WHAT TO PRODUCE:
- Unit tests for lib/ob/schemas/account.zod.js (Zod)
- Integration tests for step1_account.action.js against a test DB (Prisma)
- A lightweight e2e (Playwright) flow for the Basic path (mock Clerk/Stripe)

UNIT (Zod):
- Basic fields required; Advanced optional
- languages defaults to ["en"]
- timezone accepts valid IANA, rejects garbage

INTEGRATION (Action):
- Upsert creates then updates ob_account
- Uses Clerk flags to compute email/mobile verified
- Returns { phase, completion, blockers, textingEligible }
- Does NOT advance phase unless email+mobile verified && stripeActive

E2E (Basic happy path):
- Load /onboarding/account with mocks → shows 2 editable inputs + badges
- Click Continue without edits → toast Saved; either stays (guards false) or redirects if true
- Expand Advanced, change timezone → autosave; reload reflects change

REPORT:
- Print a short summary: passed counts and any failing assertions
```

---

# BUILD — STEP 2 (Page 2: Number & Operating Setup)

```
SPEC_VERSION=2025-09-16

OVERVIEW_PEG: (same as Step 1)

GOAL:
Implement Page 2 to reserve/configure a local MMS number with minimal UX.
Advanced options collapsed. Idempotent provisioning via server action.

FILES:
1) app/(onboarding)/onboarding/number/page.js
2) app/(onboarding)/onboarding/_actions/step2_number.action.js
3) lib/ob/schemas/number.zod.js

BASIC (visible):
- areaCode (suggested list: addr NPA, owner NPA, nearby; default first)
- hours (Mon–Fri 08:00–18:00; weekends toggle; compact)
- serviceRadiusMi (slider default 15)
- Number banner (read-only): e164, state, capabilities
- CTA: “Looks good”

ADVANCED (collapsed):
- startPortIn toggle → phoneNumber/accountNumber/pin
- ringWindowSec (default 20), ownerWindowSec (default 60, range 30–180)
- afterHoursMode (AIOnly default), holidays, stopHelpText (stock, read-only)

SERVER ACTION:
- Upsert ob_number for hours/radius/etc
- If no e164 set, call Provisioning API once with Idempotency-Key=ob:prov:<tenantId>
  to auto-pick local MMS; store e164, providerSid, capabilities, state, correlationId
- Update ob_flow.numberState
- Return standard { phase, completion, blockers, textingEligible }

CONSTRAINTS:
- ≤300 LOC per file
- No provider calls in page render; action only
- Port-in fields required only when startPortIn=true
- Do not enable outbound SMS here; just store state

ACCEPTANCE:
- Default suggestion appears; one click reserves number
- ob_number has e164/providerSid/capabilities/state
- Banner shows results; CTA enabled to proceed
```

---

# TEST — STEP 2 (Number & Operating Setup)

```
SPEC_VERSION=2025-09-16 (same overview peg)

GOAL:
Test Zod schema, server action idempotency, and basic e2e flow.

WHAT TO PRODUCE:
- Unit tests for number.zod.js
- Integration tests for step2_number.action.js with mock Provisioning API
- E2E (Playwright) for default reserve flow

UNIT (Zod):
- hours default Mon–Fri 08–18; weekends toggle off
- ownerWindowSec bounds 30–180; ringWindowSec default 20
- areaCode len=3 and numeric

INTEGRATION:
- First call purchases+configures: returns e164+sid+state
- Second call with same Idempotency-Key replays without duplicating
- Persists capabilities.mms=true; updates ob_flow.numberState

E2E:
- Page shows areaCode suggestions; accepts default
- Click “Looks good” → number reserved; banner displays e164/state
- Reload: persisted banner still visible

REPORT:
- Summarize pass/fail; include evidence of idempotent behavior
```

---

# BUILD — STEP 3 (Page 3: Calendar, Messaging & Pricing)

```
SPEC_VERSION=2025-09-16

OVERVIEW_PEG: (same)

GOAL:
Implement Page 3 with minimal Basic inputs; Advanced collapsed. Skipping calendar
is allowed.

FILES:
1) app/(onboarding)/onboarding/calmsg/page.js
2) app/(onboarding)/onboarding/_actions/step3_calmsg.action.js
3) lib/ob/schemas/calmsg.zod.js

BASIC (visible):
- calendarProvider (default "google")
- connectCalendar button sets calendarConnected=true (mock OAuth allowed)
- topServices[] (chips; ≤3; preselected by vertical)
- priceRanges (inline min/max defaults)
- CTA: “Continue”

ADVANCED (collapsed):
- doubleBookPolicy (default block)
- buffers.before/after (defaults 15/15)
- templates.title/description (prefilled by vertical)
- bilingual toggle (es)
- revenuePromptsMins (default 120), attributionDays (default 14)
- opsEmails (seed owner email), opsSms (seed owner mobile)
- slackWebhookUrl (optional, https + domain allowlist)

SERVER ACTION:
- Upsert ob_calmsg with provided fields
- Return standard { phase, completion, blockers, textingEligible }

CONSTRAINTS:
- ≤300 LOC per file
- Only Basic gates progression
- instantTextPreview computed client-side only

ACCEPTANCE:
- With defaults, user can continue without edits
- topServices max 3 enforced
- Data persists and reload reflects state
```

---

# TEST — STEP 3 (Calendar, Messaging & Pricing)

```
SPEC_VERSION=2025-09-16

GOAL:
Test schema constraints, action persistence, and basic UI flow.

WHAT TO PRODUCE:
- Unit tests for calmsg.zod.js
- Integration tests for step3_calmsg.action.js
- E2E (Playwright) for Basic path

UNIT:
- topServices length ≤3; reject 4th
- priceRanges accepts null min or max; currency present
- slackWebhookUrl must be https and on allowlist

INTEGRATION:
- Action merges partials; preserves existing fields
- calendarConnected toggles true after Connect

E2E:
- Load page with preselected services; click Continue → success
- Add a 4th service → inline error visible; cannot proceed

REPORT:
- Pass/fail summary with notable validations
```

---

# BUILD — STEP 4 (Page 4: A2P 10DLC)

```
SPEC_VERSION=2025-09-16

OVERVIEW_PEG: (same)

GOAL:
Implement micro-form chiefly prefilled; submit to A2P API; show status pill;
enforce texting gate logic.

FILES:
1) app/(onboarding)/onboarding/a2p/page.js
2) app/(onboarding)/onboarding/_actions/step4_a2p.action.js
3) lib/ob/schemas/a2p.zod.js

BASIC (visible):
- brandType (auto SP if no EIN; else STANDARD; editable)
- legalBusinessName (prefill Stripe; editable)
- websiteUrl (prefill; editable; https)
- taxId (only if STANDARD; EIN format)
- authorizedContact {name,email,phone} (prefill Clerk/Stripe; editable)
- One-paragraph disclosure + Submit
- Status pill (VETTED/ACTIVE/...)

ADVANCED (collapsed):
- useCase (locked CustomerCare.MissedCallRecovery)
- optInDescription (locked "Inbound only...")
- sampleMessages[] (prefilled 2 incl STOP/HELP; editable)
- stopHelpText (locked stock)
- linkDomains[] (prefill from website; no public shorteners)

CHECKLIST (hidden compute):
- httpsOk, privacyFound, termsFound, legalMatchesTaxIdLike, stopHelpPresent

SERVER ACTION ON SUBMIT:
- Idempotent calls to A2P API:
  - create+submit brand (key ob:a2p:brand:<tenantId>)
  - create+submit campaign (key ob:a2p:camp:<tenantId>)
  - attach number (key ob:a2p:bind:<tenantId>)
- Upsert ob_a2p with phases/reason/correlationId
- Update ob_flow.textingEligible when VETTED+ACTIVE+VERIFIED
- Return standard shape

CONSTRAINTS:
- ≤300 LOC per file
- Show single-line fix hints if checklist fails (no form dump)
- Never enable SMS unless gate true

ACCEPTANCE:
- One click Submit works with good prefills
- Status pill updates; resubmit allowed after edits on rejection
- TextingEligible flips only when all phases satisfied
```

---

# TEST — STEP 4 (A2P 10DLC)

```
SPEC_VERSION=2025-09-16

GOAL:
Test validation, idempotent submissions, and gate logic.

WHAT TO PRODUCE:
- Unit tests for a2p.zod.js
- Integration tests for step4_a2p.action.js with mock A2P API
- E2E (Playwright) for basic submit → pending → approved

UNIT:
- taxId required iff brandType=STANDARD
- sampleMessages must include "STOP" and "HELP"
- linkDomains excludes public shorteners; requires website domain present

INTEGRATION:
- Replayed POSTs with same Idempotency-Key return same status/body
- textingEligible true only when brand=VETTED, campaign=ACTIVE, binding=VERIFIED
- reason code persisted on rejection

E2E:
- Submit → shows SUBMITTED/PENDING
- Simulate provider updates to VETTED/ACTIVE/VERIFIED → UI flips to “Texting enabled”
- Rejection shows one-line fix hint; edit → resubmit succeeds

REPORT:
- Summarize results; list any flaky behaviors
```

---

# BUILD — STEP 5 (Finalize & Snapshot)

```
SPEC_VERSION=2025-09-16

OVERVIEW_PEG: (same)

GOAL:
Produce a single joined snapshot for copier; gate finalize; mark phase.

FILES:
1) app/(onboarding)/onboarding/_actions/finalize.action.js
2) lib/ob/snapshot.js
3) (optional) app/api/onboarding/snapshot/route.js (GET)

IMPLEMENT:
- snapshot.js: build {account, number, calmsg, a2p} from ob_* for tenantId
- finalize.action: require textingEligible=true (or explicitly allow calls-only mode
  if you choose—document flag), set ob_flow.phase='FINALIZE', return standard shape
- optional GET: returns { tenantId, snapshot } for copier service

CONSTRAINTS:
- ≤300 LOC total across files
- No writes to main DB here
- Deterministic snapshot ordering/keys

ACCEPTANCE:
- Valid tenant yields complete snapshot including e164 and policies
- Phase changes to FINALIZE; COMPLETE left for copier to set later
```

---

# TEST — STEP 5 (Finalize & Snapshot)

```
SPEC_VERSION=2025-09-16

GOAL:
Test snapshot completeness and finalize gating.

WHAT TO PRODUCE:
- Integration tests for snapshot.js and finalize.action.js
- E2E check for redirect to dashboard after finalize trigger (mock copier)

INTEGRATION:
- Missing critical sections → blockers returned; snapshot not produced
- With textingEligible=false → finalize throws/blocks
- With textingEligible=true → snapshot returns; phase=FINALIZE

E2E:
- After Step 4 approved, finalize → success → UI redirects to dashboard

REPORT:
- Snapshot keys present; sizes; any nulls flagged
```

---

# BUILD — STEP 6 (Guards & State)

```
SPEC_VERSION=2025-09-16

OVERVIEW_PEG: (same)

GOAL:
Centralize gating & progress computation for the wizard.

FILES:
1) lib/ob/guards.js

IMPLEMENT:
- export async function getWizardState(tenantId): {
    phase, completion:{account,number,calmsg,a2p}, blockers:string[], textingEligible
  }
- Phase transitions:
  - leave ACCOUNT if emailVerified && mobileVerified && stripeActive
  - leave NUMBER if ob_number.state='Configured' && capabilities.mms=true
  - FINALIZE allowed iff Brand=VETTED && Campaign=ACTIVE && Binding=VERIFIED
- completion%: 0/50/100 per section based on Basic presence
- blockers: single-line reasons only (e.g., 'VERIFY_MOBILE', 'RESERVE_NUMBER')
- Never require Advanced fields

CONSTRAINTS:
- ≤300 LOC
- Pure read logic; no provider calls

ACCEPTANCE:
- Deterministic output for any ob_* permutation
- No circular transitions
```

---

# TEST — STEP 6 (Guards & State)

```
SPEC_VERSION=2025-09-16

GOAL:
Test guard decisions and computed completion/blockers.

WHAT TO PRODUCE:
- Unit tests for getWizardState with fixture permutations

CASES:
- Fresh tenant: phase=ACCOUNT, blockers include VERIFY_EMAIL/MOBILE
- Verified identity + stripeActive: still ACCOUNT until action advances; or
  phase indicates ready-to-advance per your design
- Number reserved with mms=true: NUMBER complete
- A2P VETTED/ACTIVE/VERIFIED: textingEligible=true, FINALIZE allowed
- Mixed states: accurate blockers and percentages

REPORT:
- Table of inputs → expected outputs; highlight any mismatches
```

---

## Final reminders (don’t skip)

* Keep **Basic** flows literally **three clicks per page** with defaults.
* Surface only **one-line** blockers; never dump configuration onto users.
* Maintain **idempotency keys** for all provider writes.
* Use the **same return shape** from all actions to prevent UI drift.

If you want, I can also package these prompts into a single text file so you can copy/paste faster.






------------------------------------------------------------------------------

---

# STEP 2 — Page 2 (Provisioning API)

## When to call the API

**Basic path (default, zero thinking):**

1. **On page load:** *No API calls.* Prefill `areaCode` suggestions from address/owner NPA locally.
2. **On “Looks good” (CTA):** *Single server action* calls **`POST /numbers`** to purchase+configure.

**Advanced path (optional):**

* If the user opens Advanced and changes area code repeatedly, **don’t call** the API per keystroke. At most, **once** on “Looks good”.
* If you want a preview list in Advanced, call **`GET /availability`** *once* when that drawer opens or when the user hits “Refresh list”.

## Exact API usage (server action)

* **Purchase & configure**

  * Endpoint: `POST /numbers`
  * Headers: `Authorization: Bearer <token>`, `Idempotency-Key: ob:prov:<tenantId>`, `Correlation-Id: <uuid>`
  * Body:
    `{ areaCode, capabilities:["sms","voice"], webhooks:{ smsWebhookUrl, voiceUrl|voiceAppSid, statusCallbackUrl } }`
* **Handle responses**

  * **201 `Configured`** → persist `{sid,e164,capabilities,state,correlationId}` to `ob_number`; set `ob_flow.numberState`.
  * **207 `PurchasedButUnconfigured`** → immediately call **`PUT /numbers/{sid}/webhooks`**, then persist as above.
  * **200 `Replay`** → treat as success; ensure idempotent upsert.
  * **409 `Conflict`** → show one-line hint “Number unavailable; try again” and (optionally) refresh `GET /availability` once.
  * **5xx/503/502** → record `correlationId`, show “Provider busy; try again” (do **not** spin).
* **Never** include secrets in webhook query strings; reject at validation.

## Data to persist (hidden)

* `ob_number`: `areaCode`, `e164`, `providerSid`, `capabilities`, `state`, `correlationId`, `hours`, `serviceRadiusMi`, ring windows, after-hours, holidays, `stopHelpText`.
* `ob_flow.numberState` and updated `completion%`.

## Polling/refresh

* UI polls **our DB** only.
* Optional: background **outbox** job to retry `PUT /webhooks` if you ever get 207.

## Port-in (Advanced only)

* Do **not** call Provisioning API (no port-in endpoint in your contract).
* Persist `portIn{ phoneNumber, accountNumber, pin }`, set `state='Porting'`, and let your separate porting service take it from there.

### TEST SESSION (after build)

* **Unit:** validate server-action input (areaCode len=3; webhooks https; XOR `voiceUrl|voiceAppSid`).
* **Integration (mock API):** assert idempotency on repeated `POST /numbers`; assert 207→PUT flow; handle 409 gracefully.
* **E2E:** user accepts defaults → one call, number banner appears, CTA enabled; Advanced closed by default.

---

# STEP 4 — Page 4 (A2P Registration API)

## When to call the API

**Basic path (default):**

1. **On page load:** *No API calls.* Run **local checklist** (HTTPS, Privacy/Terms, STOP/HELP present) silently.
2. **On “Submit” (CTA):** *Single server action* performs the full sequence against your A2P API.

**Advanced path (optional):**

* If user edits `sampleMessages` or `linkDomains`, **no API calls** until they hit “Submit” or “Resubmit”.

## Exact API sequence (server action)

* **Create Brand**

  * `POST /brands` body: `{ country:"US", taxId?, legalName, displayName, websiteDomain, brandType }`
  * On success: persist `brandId`, `status.phase`.
* **Submit Brand**

  * `POST /brands/{brandId}:submit`
* **Create Campaign**

  * `POST /campaigns` body: `{ brandId, useCase:"CustomerCare.MissedCallRecovery", optInDescription:"Inbound only...", sampleMessages:[...], stopHelpText, linkDomains:[...] }`
* **Submit Campaign**

  * `POST /campaigns/{campaignId}:submit`
* **Attach Number**

  * `POST /numbers:attach` body: `{ campaignId, e164 }`
* **Headers for all POSTs:** `Authorization: Bearer <token>`, `Idempotency-Key: ob:a2p:<op>:<tenantId>`

## Status & gating

* After submission, **do not** poll providers from the browser.
* Server action writes `ob_a2p.{brandPhase,campaignPhase,bindingPhase,reason}`.
* Background refresher (cron/outbox) uses:

  * `GET /brands/{brandId}`
  * `GET /campaigns/{campaignId}`
  * `GET /numbers/{e164}`
    and updates `ob_a2p`, then sets `ob_flow.textingEligible = (VETTED && ACTIVE && VERIFIED)`.
* UI shows a small **status pill** from our DB and a single sentence banner. No logs.

## Validation before calling API (keep Basic simple)

* **Local checklist** (hidden booleans):

  * `httpsOk`, `privacyFound`, `termsFound`
  * `legalMatchesTaxIdLike` (string-similarity only; don’t block on fuzzy mismatch)
  * `stopHelpPresent` (in `sampleMessages` or `stopHelpText`)
* If any fail, show **one line** with a **Fix** link (open Advanced or field).

## Resubmission

* If rejected, show **short reason**. When user edits the offending field(s), “Submit” becomes “Resubmit” → rerun the same sequence with **new** Idempotency-Keys: `ob:a2p:resubmit:<tenantId>:<n>`.

## Data to persist (hidden)

* `ob_a2p`: inputs (brandType, legalBusinessName, taxId?, websiteUrl, contact), checklist booleans, `brandId`, `campaignId`, `bindingPhase`, `reason`, `correlationId`.
* `ob_flow.textingEligible`, `completion%`.

### TEST SESSION (after build)

* **Unit:** schema rules — `taxId` required only for `STANDARD`; `sampleMessages` must include “STOP” + “HELP”; `linkDomains` not in public shorteners; `websiteUrl` https.
* **Integration (mock A2P API):** happy path (DRAFT→SUBMITTED→ACTIVE/VERIFIED), rejection path with reason, idempotent replays with same Idempotency-Key.
* **E2E:** page shows prefilled micro-form; one click “Submit” → status pill shows “Submitted/Pending”; when mock flips to VETTED/ACTIVE/VERIFIED, UI shows “Texting enabled”.

---

## Minimal payloads (so the AI doesn’t overbuild)

* **Provisioning `POST /numbers` body:**
  `{ areaCode, capabilities:["sms","voice"], webhooks:{ smsWebhookUrl, voiceUrl|voiceAppSid, statusCallbackUrl } }`
* **A2P `POST /brands` body:**
  `{ country:"US", taxId?, legalName, displayName, websiteDomain, brandType }`
* **A2P `POST /campaigns` body:**
  `{ brandId, useCase:"CustomerCare.MissedCallRecovery", optInDescription:"Inbound only...", sampleMessages:[s1,s2], stopHelpText, linkDomains:[domain] }`
* **A2P `POST /numbers:attach` body:**
  `{ campaignId, e164 }`

---

## Guardrails that keep it simple for non-technical users

* **Only one button per page.** Page 2 = “Looks good”. Page 4 = “Submit”.
* **No multi-step spinners.** Show a single, short banner: “We’re getting your number… done” / “Texting will start after approval.”
* **Never show raw errors.** Translate to one-liners with a “Try again” or “Fix” link.
* **Advanced stays closed** unless the user asks. Defaults are safe and prefilled.

If you want, I’ll turn this into two copy-paste “BUILD” and “TEST” prompts tailored for your coding AI for Page 2 and Page 4, exactly following these touchpoints.
