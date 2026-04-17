import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  QueryCommand
} from "@aws-sdk/lib-dynamodb";
import { randomBytes } from "crypto";

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);

const TABLE_NAME = process.env.TABLE_NAME;
const BASE_URL = process.env.BASE_URL;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Generate a unique URL shortcode
 */
function generateCode() {
  return randomBytes(4).toString("hex");
}

/**
 * Validate URL format and prevent internal IP access
 */
function isValidUrl(url) {
  try {
    const parsed = new URL(url);

    // Only allow http/https
    if (!["http:", "https:"].includes(parsed.protocol)) {
      return false;
    }

    // Prevent internal IP abuse (SSRF protection)
    const blocked = [
      "169.254",     // link-local
      "127.",        // localhost
      "0.",          // current network
      "10.",         // private
      "172.16.",     // private
      "192.168."     // private
    ];

    if (blocked.some(ip => parsed.hostname.startsWith(ip)) || 
        parsed.hostname === "localhost") {
      return false;
    }

    // Block reserved TLDs
    const blockedTlds = [".local", ".internal", ".private", ".localhost"];
    if (blockedTlds.some(tld => parsed.hostname.endsWith(tld))) {
      return false;
    }

    return true;
  } catch (error) {
    return false;
  }
}

/**
 * Extract user ID from JWT authorizer context
 */
function extractUserId(event) {
  try {
    const claims = event.requestContext.authorizer?.claims;
    return claims?.sub || null;
  } catch {
    return null;
  }
}

/**
 * Structured logging
 */
function log(level, message, data = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data
  }));
}

// ============================================================================
// HANDLERS
// ============================================================================

/**
 * POST /shorten - Create a new shortened URL
 */
async function handleCreateShortUrl(event) {
  try {
    const userId = extractUserId(event);
    if (!userId) {
      log("warn", "No user ID in JWT claims");
      return {
        statusCode: 401,
        body: JSON.stringify({ error: "Unauthorized" })
      };
    }

    // Parse request body
    let body;
    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Invalid JSON in request body" })
      };
    }

    const originalUrl = body.url;
    const customCode = body.customCode;

    // Validate URL
    if (!originalUrl || !isValidUrl(originalUrl)) {
      log("warn", "Invalid URL provided", { originalUrl, userId });
      return {
        statusCode: 400,
        body: JSON.stringify({ 
          error: "Invalid or unsafe URL",
          details: "URL must be http/https and not point to internal IPs"
        })
      };
    }

    // Validate custom code (if provided)
    if (customCode && !/^[a-z0-9_-]{3,20}$/i.test(customCode)) {
      return {
        statusCode: 400,
        body: JSON.stringify({ 
          error: "Invalid custom code",
          details: "Code must be 3-20 alphanumeric characters"
        })
      };
    }

    const code = customCode || generateCode();
    const now = Date.now();
    const expiresAt = Math.floor(now / 1000) + (365 * 24 * 60 * 60); // 1 year TTL

    // Store in DynamoDB
    await ddb.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          code,
          userId,
          originalUrl,
          createdAt: now,
          expiresAt,
          status: "active",
          clickCount: 0,
          tags: body.tags || []
        },
        // Prevent overwriting existing codes
        ConditionExpression: "attribute_not_exists(code)"
      })
    );

    log("info", "Short URL created", { code, userId });

    return {
      statusCode: 201,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        shortUrl: `${BASE_URL}/${code}`,
        code,
        originalUrl,
        expiresAt
      })
    };
  } catch (error) {
    // Handle duplicate code error
    if (error.name === "ConditionalCheckFailedException") {
      log("warn", "Code already exists", { error: error.message });
      return {
        statusCode: 409,
        body: JSON.stringify({ error: "Short code already in use" })
      };
    }

    // Handle DynamoDB errors
    if (error.name === "ValidationException") {
      log("error", "DynamoDB validation error", { error: error.message });
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Invalid request" })
      };
    }

    log("error", "Failed to create short URL", { error: error.message });
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Internal server error" })
    };
  }
}

/**
 * GET /{code} - Redirect to original URL and increment click count
 */
async function handleRedirect(event) {
  try {
    const code = event.pathParameters?.code;

    if (!code) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Missing code parameter" })
      };
    }

    // Fetch URL mapping
    const result = await ddb.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: { code }
      })
    );

    if (!result.Item) {
      log("info", "URL not found", { code });
      return {
        statusCode: 404,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: "Short URL not found" })
      };
    }

    // Check if expired
    if (result.Item.status !== "active") {
      log("info", "URL inactive", { code, status: result.Item.status });
      return {
        statusCode: 410,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: "Short URL no longer available" })
      };
    }

    // Increment click count asynchronously (non-blocking)
    ddb.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: { code },
        UpdateExpression: "SET clickCount = if_not_exists(clickCount, :zero) + :inc, lastAccessedAt = :now",
        ExpressionAttributeValues: {
          ":zero": 0,
          ":inc": 1,
          ":now": Date.now()
        }
      })
    ).catch(err => {
      log("warn", "Failed to update click count", { code, error: err.message });
    });

    log("info", "URL redirect", { code, clickCount: result.Item.clickCount + 1 });

    return {
      statusCode: 302,
      headers: {
        "Location": result.Item.originalUrl,
        "Cache-Control": "no-cache"
      }
    };
  } catch (error) {
    log("error", "Redirect failed", { error: error.message });
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Internal server error" })
    };
  }
}

// ============================================================================
// MAIN HANDLER
// ============================================================================

export const handler = async (event) => {
  try {
    const method = event.requestContext.http.method;
    const path = event.requestContext.http.path;

    log("info", "Incoming request", { method, path });

    if (method === "POST" && path === "/shorten") {
      return await handleCreateShortUrl(event);
    }

    if (method === "GET") {
      return await handleRedirect(event);
    }

    // Method not allowed
    return {
      statusCode: 405,
      body: JSON.stringify({ error: "Method not allowed" })
    };
  } catch (error) {
    log("error", "Unhandled error", { error: error.message, stack: error.stack });
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Internal server error" })
    };
  }
};
