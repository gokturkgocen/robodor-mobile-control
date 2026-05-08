# Architecture

## Goals

- **Local-first.** Operators on site must be able to control the door even when the network is unavailable. The server is never in the critical control path.
- **Multi-tenant.** Multiple organizations share one platform without ever seeing each other's devices, telemetry, or backups.
- **Operationally simple.** Single Lambda, single DynamoDB table, single CloudFront distribution. No long-running compute, no managed pools we don't need.
- **Reproducible.** The entire stack lives in CDK; bringing it up on a clean AWS account is one `cdk deploy`.

---

## Mobile architecture

Both apps follow the same shape: UI → ViewModel/State → Repository.

```
        UI Layer
           │
           ▼
   ViewModel / @State
           │
           ▼
   ┌──────────────────────────┐
   │       Repository         │   single source of truth
   │   ───────────────────    │
   │   • BLE connection       │
   │   • Modbus codec         │
   │   • GATT lifecycle       │
   │   • Register cache       │
   │   • Polling engine       │
   │   • BLE quality metrics  │
   │   • Manual mode safety   │
   └──────────┬───────────────┘
              │
              ▼
   ┌─────────────────────────┐
   │   Telemetry History     │   subscribes to repository
   │   (downsampled buffers, │   no writes back
   │    persisted to disk)   │
   └─────────────────────────┘
```

The view layer never talks to BLE directly. Buttons mutate registers via the repository's command queue; readouts come from `@Published` (iOS) / `StateFlow` (Android).

A separate **TelemetryBridge** subscribes to the same repository to push connection-state events, periodic snapshots, and a heartbeat to the server when the user opts in. It is read-only with respect to BLE state.

### BLE quality

A `BleMetricsTracker` keeps a 150-sample rolling latency window plus an EMA of read latency. The dashboard's quality bar reads:

| EMA latency  | State      |
|--------------|------------|
| < 250 ms     | Excellent  |
| < 500 ms     | Good       |
| < 1 000 ms   | Weak       |
| ≥ 1 000 ms   | Critical (warning + reconnect cues) |

Time-outs apply a 2 000 ms penalty to the EMA so a single dropped read is visible immediately.

### Manual mode safety path

Live open / close / stop are routed through a separate write path with a much shorter timeout than normal register writes. On timeout the manual state is dropped immediately and a best-effort STOP write is fired. On unexpected disconnect during active manual movement, automatic reconnect is suppressed for that interaction so the device doesn't accept stale operator intent after a network glitch. Real fail-safety is enforced by the firmware; the app only adds a risk-reduction layer on top.

---

## Backend architecture

```
                  Public DNS
                       │
                       ▼
            ┌──────────────────────┐
            │   API Gateway        │  HTTP API, throttled
            │   (eu-central-1)     │
            └──────────┬───────────┘
                       │
            ┌──────────▼───────────┐
            │   Single Lambda      │  Node.js 22 (TS)
            │   • JWT verifier     │
            │   • Auth flows       │
            │   • Card state       │
            │   • Telemetry sync   │
            │   • Command queue    │
            │   • Encrypted backup │
            └─┬──────┬──────┬──────┘
              │      │      │
              ▼      ▼      ▼
         ┌────────┐ ┌──────────┐ ┌─────────────┐
         │Cognito │ │DynamoDB  │ │ S3 + KMS    │
         │ + IDP  │ │ + GSI1   │ │ encrypted   │
         └────────┘ └──────────┘ └─────────────┘
```

### Single-table DynamoDB

| PK pattern        | SK pattern         | What it stores                       |
|-------------------|--------------------|--------------------------------------|
| `USER#<sub>`      | `PROFILE`          | role, organizationId, fullName, email |
| `CARD#<cardId>`  | `STATE`            | active card state, last seen         |
| `CARD#<cardId>`  | `CMD#<id>`         | pending remote command (TTL 5 min)   |
| `CARD#<cardId>`  | `RESULT#<id>`      | command ack + result (TTL 1 h)       |

A single GSI (`GSI1PK = ORG#<id>`, `GSI1SK = CARD#<cardId>`) lets per-tenant device lists run as a single Query. Old rows are backfilled with GSI keys on the next event using `if_not_exists`, so the index stays accurate without a migration job.

### Authorization

The API runs in two compatibility modes during the migration window:

1. **Preferred** — `Authorization: Bearer <Cognito access token>`. The Lambda verifies the JWT against Cognito's JWKS (cached by `aws-jwt-verify`), pulls the actor's role and organization from the **server-controlled** profile row in DynamoDB, and uses that for every authorization decision.
2. **Legacy** — older clients that still send `x-robodor-*` headers continue to work; the Lambda accepts them only as a fallback when no valid JWT is presented. Once both apps are out in the field with the JWT path, this fallback is removed.

Critically, `role` and `organizationId` are **never** read from Cognito custom attributes anymore. Cognito attributes are user-mutable historically, so promoting authorization data into a server-controlled DynamoDB row eliminates the entire class of "I changed my own attribute" attacks. The Lambda role does not have `AdminUpdateUserAttributes`.

### Idempotent commands

Remote door / settings commands accept an optional `idempotencyKey`. The Lambda writes the command with `ConditionExpression: attribute_not_exists(PK)` so a duplicate request from a client retry returns the existing `commandId` instead of queuing a second physical operation.

### Encrypted backups

Settings backups are encrypted **on the device** with AES-256-GCM using a per-user key. The ciphertext travels through S3 (KMS-encrypted at rest with a customer-managed key on top, defence-in-depth). Decryption only ever happens on the originating device. The server never holds plaintext settings.

---

## Live activities & quick actions

iOS uses `ActivityKit` for a "door is currently opening / closing / stopped" Live Activity, plus an App Shortcut + URL scheme handler so a Siri shortcut or home-screen action can prepare a connection and fire a quick command. The flow is staged so the UI can show the user where it's blocked (waiting for disconnect, waiting for scan, waiting for ready) instead of a black-box spinner.

---

## What's deliberately not here

- **Modbus register addresses** — proprietary spec.
- **Settings schema and value limits** — proprietary spec.
- **BLE transport / packet codec** — proprietary, hardware-tuned timeouts.
- **Hardware-specific tunings** — backed by field testing on physical units.
- **Live AWS resource identifiers** — account ID, Cognito pool, API Gateway URL, CloudFront domain.

These would expose the product to copying or attack and are kept in a private repository.
