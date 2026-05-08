/**
 * Idempotent command write to DynamoDB.
 *
 * The naive write (`PutCommand` without a condition) lets a client
 * retry — for example after a network glitch — silently create a second
 * row, which the device then executes a second time. Bad if the command
 * is "open" and the device just did open.
 *
 * Solution: clients pass an optional `idempotencyKey`; the server uses it
 * as the sort-key suffix and writes with `attribute_not_exists(PK)` so a
 * duplicate retry is rejected by DynamoDB itself, without a race
 * window. We catch the conditional-check failure and return the
 * already-existing `commandId` so the client converges instead of
 * failing.
 *
 * Trimmed-down extract from the project's actual handler.
 */

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import { randomUUID } from "node:crypto";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const tableName = process.env.MAIN_TABLE_NAME ?? "";

type CommandInput = {
  cardId: string;
  type: string;
  payload: Record<string, unknown>;
  idempotencyKey?: string;
};

type CreateResult =
  | { ok: true; commandId: string; deduplicated: false }
  | { ok: true; commandId: string; deduplicated: true };

export async function createCommand(input: CommandInput): Promise<CreateResult> {
  const commandId = (input.idempotencyKey ?? "").trim() || randomUUID();
  try {
    await ddb.send(new PutCommand({
      TableName: tableName,
      Item: {
        PK: `CARD#${input.cardId}`,
        SK: `CMD#${commandId}`,
        commandId,
        type: input.type,
        payload: input.payload,
        status: "pending",
        createdAt: new Date().toISOString(),
        ttl: Math.floor(Date.now() / 1000) + 300, // 5 minute TTL
      },
      // Reject duplicate writes for the same (card, commandId) tuple.
      ConditionExpression: "attribute_not_exists(PK)",
    }));
    return { ok: true, commandId, deduplicated: false };
  } catch (error) {
    if ((error as { name?: string }).name === "ConditionalCheckFailedException") {
      // Same idempotency key already in flight — converge.
      return { ok: true, commandId, deduplicated: true };
    }
    throw error;
  }
}
