# Stateless Service APIs (JSON-only) — LEAN v1.1

> All endpoints accept and return **application/json**. Use a short‑lived **service JWT** in `Authorization: Bearer <token>` for internal calls (Orchestrator → service). Provider webhooks are signature‑verified by the service.

---

## 1) Twilio Edge (Stateless) — Voice/SMS Webhooks

**Ingress only (from Twilio).**

### POST /twilio/voice

Request

```json
{
  "toE164": "+13105551234",
  "fromE164": "+13105559876",
  "callSid": "CAxxxxxxxx",
  "callStatus": "ringing|in-progress|completed|no-answer|busy|failed|voicemail",
  "timestamp": "2025-09-15T19:41:00Z"
}
```

Response

```json
{ "ok": true }
```

### POST /twilio/sms

Request

```json
{
  "toE164": "+13105551234",
  "fromE164": "+13105559876",
  "messageSid": "SMxxxxxxxx",
  "body": "Hi, I called earlier",
  "timestamp": "2025-09-15T19:41:00Z"
}
```

Response

```json
{ "ok": true }
```

### POST /twilio/status-callback

Request

```json
{
  "messageSid": "SMxxxxxxxx",
  "status": "queued|sent|delivered|undelivered|failed",
  "errorCode": "30007",
  "timestamp": "2025-09-15T19:41:33Z"
}
```

Response

```json
{ "ok": true }
```

---

## 2) DispatchBot AI (Stateless)

### POST /v1/ai/respond

Request

```json
{
  "businessId": "biz_123",
  "conversationId": "c_456",
  "policy": { "priceRangesOnly": true, "discloseAI": true, "lang": "en" },
  "context": {
    "messages": [
      {"role": "user", "text": "Do you service 90034?"}
    ],
    "hours": {"mon": [["08:00","18:00"]]},
    "serviceArea": {"radiusMiles": 15, "center": "Los Angeles, CA"},
    "pricing": [
      {"name": "Drain cleaning", "min": 99, "max": 249, "unit": "PER_JOB"}
    ]
  },
  "capabilities": { "canText": true, "canOfferSlots": true }
}
```

Response

```json
{
  "reply": "I can share a price range and available times. Would you like tomorrow 10:00 or 2:00?",
  "lang": "en",
  "intent": "OFFER_TIMESLOTS|PROVIDE_PRICE_RANGE|ESCALATE|SMALL_TALK",
  "suggestedSlots": [
    {"start": "2025-09-16T10:00:00Z", "end": "2025-09-16T11:00:00Z"}
  ],
  "escalate": false,
  "confidence": 0.82,
  "safety": { "redactions": [] }
}
```

---

## 3) Universal Calendar (Stateless)

### POST /v1/calendar/availability

Request

```json
{
  "businessId": "biz_123",
  "employeeId": "emp_1",
  "range": { "start": "2025-09-16", "end": "2025-09-20" },
  "policy": { "durationMin": 60, "bufferMin": 0, "doubleBook": "NODOUBLE" },
  "accessToken": "ya29..."
}
```

Response

```json
{
  "slots": [
    {"start": "2025-09-16T10:00:00Z", "end": "2025-09-16T11:00:00Z"}
  ]
}
```

### POST /v1/calendar/book

Request

```json
{
  "businessId": "biz_123",
  "employeeId": "emp_1",
  "slot": { "start": "2025-09-16T10:00:00Z", "end": "2025-09-16T11:00:00Z" },
  "title": "Drain cleaning for +13105559876",
  "description": "Caller: +13105559876",
  "accessToken": "ya29...",
  "idempotencyKey": "book_c_456_2025-09-16T10:00Z"
}
```

Response

```json
{ "ok": true, "externalId": "gcal_event_123" }
```

### POST /v1/calendar/cancel

Request

```json
{
  "businessId": "biz_123",
  "employeeId": "emp_1",
  "externalId": "gcal_event_123",
  "accessToken": "ya29...",
  "idempotencyKey": "cancel_gcal_event_123"
}
```

Response

```json
{ "ok": true }
```

---

## 4) Billing Edge (Stripe — Stateless)

**Ingress only (from Stripe).**

### POST /stripe/webhook

Request

```json
{ "event": { "id": "evt_123", "type": "checkout.session.completed", "data": {"object": {"id": "cs_..."}} } }
```

Response

```json
{ "ok": true }
```

---

## 5) A2P Manager (Stateless)

### POST /a2p/validate

Request

```json
{
  "bizId": "biz_123",
  "legalName": "Acme Plumbing LLC",
  "ein": "12-3456789",
  "website": "https://acmeplumbing.com",
  "contact": {"name": "Sam", "email": "owner@acme.com", "phone": "+13105551234"},
  "useCase": "CUSTOMER_CARE",
  "samples": ["Thanks for calling {business}. Reply STOP to opt out.", "HELP at https://..." ]
}
```

Response

```json
{ "ok": true, "errors": [] }
```

### POST /a2p/submit

Request

```json
{
  "bizId": "biz_123",
  "legalName": "Acme Plumbing LLC",
  "ein": "12-3456789",
  "website": "https://acmeplumbing.com",
  "contact": {"name": "Sam", "email": "owner@acme.com", "phone": "+13105551234"},
  "useCase": "CUSTOMER_CARE",
  "samples": ["Thanks for calling {business}. Reply STOP to opt out."]
}
```

Response

```json
{ "bizId": "biz_123", "status": "SUBMITTED", "providerRef": { "brandId": "br_...", "campaignId": "ca_..." } }
```

### POST /a2p/status

Request

```json
{ "bizId": "biz_123", "providerRef": { "brandId": "br_...", "campaignId": "ca_..." } }
```

Response

```json
{ "bizId": "biz_123", "status": "PENDING_CARRIERS", "reason": null }
```

### POST /a2p/attach-numbers

Request

```json
{ "bizId": "biz_123", "campaignId": "ca_...", "numbers": ["+13105551234"] }
```

Response

```json
{ "bizId": "biz_123", "attached": true, "campaignId": "ca_...", "numbers": ["+13105551234"] }
```

### POST /a2p/webhook

Request

```json
{ "event": { "id": "a2p_evt_123", "type": "campaign.approved", "data": {"campaignId": "ca_..."} } }
```

Response

```json
{ "ok": true }
```

---

### Common Error Shape (all services)

Response

```json
{ "ok": false, "error": { "code": "BAD_REQUEST|UNAUTHORIZED|CONFLICT|PROVIDER_ERROR", "message": "human readable" } }
```
