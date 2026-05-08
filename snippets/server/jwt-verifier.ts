/**
 * Pattern for verifying a Cognito JWT on a Lambda and resolving the actor
 * from a server-controlled DynamoDB profile, with a transitional fallback
 * to legacy header-based identity for older clients that haven't shipped
 * the Bearer token path yet.
 *
 * Highlights:
 *   • `aws-jwt-verify` caches Cognito's JWKS after the first call.
 *   • Authorization data (role, organizationId) is read from a server-only
 *     DynamoDB row, never from Cognito custom attributes (which are
 *     historically user-mutable and therefore untrustworthy).
 *   • A first-time backfill from Cognito attributes covers users that
 *     pre-date the migration so no one is locked out.
 *
 * Trimmed-down extract from the project's actual handler.
 */

import type { APIGatewayProxyEventV2 } from "aws-lambda";
import { CognitoJwtVerifier } from "aws-jwt-verify";

type RoleKey = "admin" | "operator" | "service" | "viewer";

type Actor = {
  userId: string;
  email: string;
  role: RoleKey;
  organizationId: string;
};

type UserProfile = {
  userId: string;
  email: string;
  role: RoleKey;
  organizationId: string;
};

const userPoolId = process.env.USER_POOL_ID ?? "";
const clientId = process.env.USER_POOL_CLIENT_ID ?? "";

const jwtVerifier = userPoolId && clientId
  ? CognitoJwtVerifier.create({
      userPoolId,
      tokenUse: "access",
      clientId,
    })
  : null;

declare function getUserProfile(userId: string): Promise<UserProfile | null>;
declare function backfillProfileFromIdp(userId: string, claims: Record<string, unknown>): Promise<UserProfile | null>;
declare function actorFromHeadersLegacy(event: APIGatewayProxyEventV2): Actor | null;

function header(event: APIGatewayProxyEventV2, name: string): string | undefined {
  return event.headers[name] ?? event.headers[name.toLowerCase()];
}

/// Resolve the actor for an authenticated request. Prefers a verified
/// JWT; falls back to legacy headers only when no valid JWT is present.
export async function actorFromRequest(event: APIGatewayProxyEventV2): Promise<Actor | null> {
  const fromJwt = await actorFromJwt(event);
  if (fromJwt) return fromJwt;
  return actorFromHeadersLegacy(event);
}

async function actorFromJwt(event: APIGatewayProxyEventV2): Promise<Actor | null> {
  if (!jwtVerifier) return null;
  const auth = header(event, "Authorization") ?? header(event, "authorization");
  if (!auth) return null;
  const match = auth.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  const token = match[1].trim();
  if (!token) return null;

  let claims: Awaited<ReturnType<typeof jwtVerifier.verify>>;
  try {
    claims = await jwtVerifier.verify(token);
  } catch {
    return null;
  }

  const userId = (claims.sub as string | undefined) ?? "";
  if (!userId) return null;

  // Authoritative profile lives in DynamoDB. Cognito custom attributes
  // are not trusted for authorization — they are user-mutable historically.
  let profile = await getUserProfile(userId);
  if (!profile) {
    profile = await backfillProfileFromIdp(userId, claims).catch(() => null);
    if (!profile) return null;
  }

  return {
    userId: profile.userId,
    email: profile.email,
    role: profile.role,
    organizationId: profile.organizationId,
  };
}
