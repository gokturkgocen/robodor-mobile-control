# Server highlights

Single AWS account, single CDK stack, single Lambda. The whole backend stands up on a clean account with one `cdk deploy`.

## Stack shape

- **API Gateway HTTP API** — public entry, throttled at the default route (rate / burst).
- **Single Node.js Lambda** (TypeScript) — all auth flows, telemetry sync, command queue, encrypted backups behind one handler. Fluid compute keeps cold starts off the critical path.
- **Amazon Cognito User Pool** — email/password + Google identity provider. JWT-based access tokens, refresh tokens with 30-day validity, hardened password policy (≥ 12 chars, mixed case + digit + symbol).
- **DynamoDB** — single-table design, partition + sort key, one GSI for tenant-scoped queries. PAY_PER_REQUEST billing, retained on stack delete.
- **S3 + KMS CMK** — telemetry cold archive, encrypted user backups, encryption at rest with a customer-managed key.
- **CloudFront + S3** — static hosting for the web admin console.

## Authentication

- Cognito access token in `Authorization: Bearer …`. Lambda verifies with `aws-jwt-verify` (JWKS cached after first call).
- After verification, the actor's role + organization are loaded from a server-controlled DynamoDB row (`PK = USER#<sub>`, `SK = PROFILE`). Cognito custom attributes are not trusted for authorization — they are user-mutable historically, so promoting authorization data into a server-only row eliminates a class of "I changed my own attribute" attacks.
- The Lambda's IAM role does **not** have `AdminUpdateUserAttributes`. Even with a stolen token an attacker cannot promote themselves into another tenant.
- Onboarding is one-shot. The endpoint refuses to overwrite an existing organization with `ConditionExpression: organizationId = :empty`, returning `409 ALREADY_ONBOARDED` if you try to redo it.
- Token refresh runs through a dedicated `/v1/auth/refresh` endpoint which executes Cognito `REFRESH_TOKEN_AUTH`.

## Authorization

Every endpoint that touches a card resolves the card's owning organization first, then runs `cardScopeAllowed(actor, card.organizationId)`. Admin role is special-cased to see across organizations; everyone else is bound to their own tenant.

## Telemetry & commands

- **Telemetry snapshots and events** are appended to S3 (cold archive) and the corresponding "active card state" row in DynamoDB is updated for the hot read path. Heartbeat events skip the S3 archive (would just spam) and only refresh `lastSeenAt`.
- **Remote commands** live as `CMD#<id>` rows under the card's partition with a 5-minute TTL. Clients can supply an `idempotencyKey`; the write uses `attribute_not_exists(PK)` so a duplicate retry returns the existing `commandId` instead of queuing a second physical operation. Acknowledgement deletes the pending row and writes a `RESULT#<id>` row (1-hour TTL) for the dashboard to read back.

## Logging hygiene

Caught exceptions are logged with `safeErrorMessage()` which strips the message body and keeps only the error type. This prevents Cognito errors (which sometimes include the email or token fragments in their message) from ending up in CloudWatch.

## Reproducibility

The CDK stack carries no hardcoded AWS account IDs, no personal bucket names, no personal domains. The same code drops onto a company-owned account by changing one CDK context parameter.
