Absolutely. Below is the **complete, consolidated Externalization / Cloud Readiness Plan v1.3** in clean Markdown format. You can paste this directly into a `.md` file (e.g., `EXTERNALIZATION_PLAN_v1_3.md`).

---

# Legacy Treasure Chest

# Externalization / Cloud Readiness Plan v1.3

---

## 0) Scope Lock (Non-Negotiable Boundaries)

### In Scope (Cloud Responsibilities)

The cloud backend will provide:

* AI services (Gemini 2.5)
* Partner discovery (Google Places API New)
* Stateless request processing
* Rate limiting and cost control
* Monitoring and logging
* Health checks

### Explicitly NOT in Scope

* No backend storage of inventory data
* No user accounts
* No multi-user collaboration
* No cross-device sync
* No executor login system
* No household group management

**Architectural Principle:**
Legacy Treasure Chest remains a **single-user, single-device planning tool**.
The backend exists only to provide AI augmentation and partner discovery.

---

## 1) Security Model

### 1.1 API Authentication (Required)

All endpoints except `/health` must require:

```
Header: X-LTC-API-KEY: <secret>
```

* Secret stored only in cloud environment variables.
* Embedded in app build for TestFlight (acceptable for small controlled rollout).
* Rotatable via new app build if compromised.

### 1.2 HTTPS Only

* Enforce HTTPS at platform level.
* No HTTP fallback.
* ATS (App Transport Security) enabled in iOS.

### 1.3 Rate Limiting (Additive Model)

Rate limiting is enforced **per device ID**.

#### Global Limit

* 60 requests per minute per device (across all endpoints)

#### Endpoint-Specific Limits

* `/ai/analyze-item-photo`: 10 req/min/device
* `/ai/generate-liquidation-brief`: 10 req/min/device
* `/ai/generate-liquidation-plan`: 10 req/min/device
* `/ai/disposition/partners/search`: 20 req/min/device

**Implementation Order**

1. Check global limit.
2. Check endpoint-specific limit.
3. Reject if either exceeded.

Response format:

```json
{
  "error": "rate_limited",
  "message": "Too many requests. Please slow down.",
  "retry_after_seconds": 60
}
```

---

## 2) Cost Containment Strategy

### 2.1 Device ID (Keychain-Based)

Each physical device must generate and persist a unique ID.

Keychain configuration:

* Service: `com.legacytreasurechest.device-id`
* Account: `ltc_device_id`
* Accessibility: `kSecAttrAccessibleAfterFirstUnlock`
* Synchronizable: **false** (must not sync via iCloud Keychain)

Header sent on every request:

```
X-LTC-DEVICE-ID: <uuid>
```

---

### 2.2 Daily Quotas (In-Memory, v1)

Quota tracking will be:

* In-memory
* Reset daily
* Per-device

#### Default Daily Limits

* AI calls: 50/day/device
* Places searches: 30/day/device

Response when exceeded:

```json
{
  "error": "quota_exceeded",
  "message": "Daily AI limit reached. Please try again tomorrow.",
  "retry_after_seconds": 43200
}
```

Redis is explicitly deferred until:

* Multiple backend instances are deployed
* > 100 active users
* Abuse patterns require distributed coordination

---

### 2.3 Kill Switches

Environment variables:

```
AI_ENABLED=true
PLACES_ENABLED=true
```

When disabled:

```json
{
  "error": "service_unavailable",
  "message": "AI analysis is temporarily unavailable. Please try again later.",
  "retry_after_seconds": 3600
}
```

Kill switches are used to:

* Immediately stop financial exposure
* Pause provider integrations
* Stabilize during outages

---

## 3) Monitoring & Financial Guardrails

### 3.1 Monthly Budget Structure (Locked)

Expected usage (10 TestFlight users):

* $50–$75/month

Thresholds:

| Level | Action                                       |
| ----- | -------------------------------------------- |
| $100  | Alert – investigate                          |
| $200  | Hard review – reduce quotas or pause invites |
| $300  | Kill switch activation                       |

Budget alerts must be configured in:

* Google Cloud (Gemini + Places)
* Hosting platform (if applicable)

---

### 3.2 Logging Policy

* Use platform logs only (stdout/stderr).
* Do NOT log:

  * Base64 image data
  * Full prompts
  * API keys
* Retain logs for **7 days**.

If platform default >7 days, reduce retention where possible.

---

## 4) Backend Configuration

### Required Environment Variables

```
GEMINI_API_KEY
GEMINI_MODEL=gemini-2.5-flash
PARTNER_DISCOVERY_PROVIDER=google
GOOGLE_PLACES_API_KEY
LTC_GATEWAY_API_KEY
AI_ENABLED=true
PLACES_ENABLED=true
```

Optional:

```
LOG_LEVEL=INFO
```

---

### 4.1 Health Endpoint

`GET /health` does NOT require API key.

Example response:

```json
{
  "status": "ok",
  "timestamp": "2026-02-13T10:30:00Z",
  "services": {
    "ai": "enabled",
    "places": "enabled"
  }
}
```

If AI disabled:

```json
{
  "status": "degraded",
  "services": {
    "ai": "disabled",
    "places": "enabled"
  }
}
```

---

### 4.2 CORS

CORS is not required for native iOS apps.

Keeping existing CORS middleware is harmless but not critical.

---

## 5) iOS Client Requirements

### 5.1 Base URL Switching

* Debug build → Mac mini gateway
* Release/TestFlight → Cloud gateway

Single configuration point controls environment.

---

### 5.2 Required Headers

All AI and partner requests must include:

```
X-LTC-API-KEY
X-LTC-DEVICE-ID
```

---

### 5.3 Error Handling UX

Handle:

* `401 unauthorized`
* `429 rate_limited`
* `quota_exceeded`
* `service_unavailable`

Display clear guidance:

* “Daily limit reached.”
* “Service temporarily unavailable.”

Never show raw backend error text.

---

## 6) Privacy & Compliance

### 6.1 Data Processing

* Photos sent to AI for analysis.
* Text descriptions sent to AI.
* Location data sent for partner search.
* No inventory data stored server-side.

### 6.2 Log Retention

* Logs retained 7 days.
* No long-term storage of user inventory data.
* Logs contain operational metadata only.

### 6.3 Data Deletion

To delete all inventory data:

* Delete the app from device.

To request deletion of server logs:

* Contact support email.

---

## 7) Deployment Strategy

### 7.1 Phased Launch

Week 1:

* Cloud live
* Mac mini retained for your development fallback

Week 2:

* If stable, optionally decommission Mac mini gateway

---

## 8) Rollback Strategy (Clarified)

### Immediate Response to Failure

1. Flip kill switches.
2. Review platform logs.
3. Pause deployment if necessary.

### For TestFlight Users

* They cannot fall back to Mac mini.
* They will receive standardized service_unavailable errors.
* If outage >24 hours, send TestFlight update message.
* Optionally ship temporary client-side feature disable.

### For Your Development

* Keep Mac mini running for 2 weeks as personal safety net.
* Debug builds can still point locally.

---

## 9) Implementation Sequence

### Step 1 – Backend Security

* API key middleware
* Kill switches
* Standardized error responses
* Enhanced `/health`

### Step 2 – Backend Cost Controls

* Device ID extraction
* In-memory quota tracker
* Additive rate limiting

### Step 3 – Cloud Deployment

* Deploy service
* Configure environment variables
* Verify `/health`
* Test from cellular

### Step 4 – iOS Updates

* Keychain device ID
* Base URL switching
* Required headers
* Graceful error handling

### Step 5 – Monitoring

* Budget alerts configured
* Log retention verified
* Cost monitoring active

### Step 6 – Privacy & App Store

* Publish privacy policy
* Add URL to App Store Connect
* Configure nutrition labels

---

# End of Document

---

If you would like, I can now:

* Produce a **short executive summary version** for README inclusion
* Or generate a **Cloud Hardening Checklist** distilled to one page
* Or move directly to implementation files (Swift + `main.py`)
