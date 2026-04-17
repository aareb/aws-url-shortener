/**
 * AWS URL Shortener Lambda Function
 * 
 * Purpose: REST API for creating shortened URLs and redirecting to original URLs
 * 
 * Architecture:
 * - POST /shorten: Creates a new shortened URL mapping
 * - GET /{code}: Redirects to the original URL and tracks analytics
 */

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  QueryCommand
} from "@aws-sdk/lib-dynamodb";
import { randomBytes } from "crypto";

// Initialize DynamoDB client for document-based operations
const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);

// Environment variables loaded from Lambda function configuration
const TABLE_NAME = process.env.TABLE_NAME;       // DynamoDB table for URL mappings
const BASE_URL = process.env.BASE_URL;           // Base domain for shortened URLs

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Generate a unique URL shortcode
 * Uses 4 random bytes converted to hexadecimal (8 characters)
 * Example: "a1b2c3d4"
 */
function generateCode() {
  return randomBytes(4).toString("hex");
}

/**
 * Validate URL format and prevent internal IP access (SSRF protection)
 * 
 * Checks performed:
 * - URL must be valid HTTP/HTTPS format
 * - Blocks localhost and link-local addresses (127.*, 169.254.*)
 * - Blocks private IP ranges (10.*, 172.16.*, 192.168.*, 0.*)
 * - Blocks reserved TLDs (.local, .internal, .private, .localhost)
 * 
 * @param {string} url - The URL to validate
 * @returns {boolean} - True if URL is valid and safe, false otherwise
 */
function isValidUrl(url) {
  try {
    const parsed = new URL(url);

    // Only allow http/https protocols (no ftp, gopher, etc.)
    if (!["http:", "https:"].includes(parsed.protocol)) {
      return false;
    }

    // Prevent Server-Side Request Forgery (SSRF) attacks by blocking internal IP ranges
    const blocked = [
      "169.254",     // link-local addresses
      "127.",        // localhost loopback
      "0.",          // current network
      "10.",         // private Class A
      "172.16.",     // private Class B
      "192.168."     // private Class C
    ];

    if (blocked.some(ip => parsed.hostname.startsWith(ip)) || 
        parsed.hostname === "localhost") {
      return false;
    }

    // Block reserved special-use TLDs
    const blockedTlds = [".local", ".internal", ".private", ".localhost"];
    if (blockedTlds.some(tld => parsed.hostname.endsWith(tld))) {
      return false;
    }

    return true;
  } catch (error) {
    // URL parsing failed (malformed URL)
    return false;
  }
}

/**
 * Extract user ID from JWT authorizer context
 * The API Gateway Cognito authorizer provides JWT claims in the event
 * 
 * @param {object} event - Lambda event from API Gateway
 * @returns {string|null} - User's unique ID (sub claim) or null if not found
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
 * Structured JSON logging for CloudWatch
 * All logs include timestamp, level, and message for easy parsing
 * 
 * @param {string} level - Log level (info, warn, error)
 * @param {string} message - Main log message
 * @param {object} data - Additional structured data to include
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
 * 
 * Request Body:
 * {
 *   "url": "https://example.com/long/path",     // Required: URL to shorten
 *   "customCode": "mylink",                      // Optional: Custom short code
 *   "tags": ["tag1", "tag2"]                     // Optional: Metadata tags
 * }
 * 
 * Returns:
 * 201: Short URL created successfully
 * 400: Invalid URL or request format
 * 401: User not authenticated
 * 409: Custom code already in use
 * 500: Server error
 */
async function handleCreateShortUrl(event) {
  try {
    // Step 1: Extract and validate user authentication via JWT
    const userId = extractUserId(event);
    if (!userId) {
      log("warn", "No user ID in JWT claims");
      return {
        statusCode: 401,
        body: JSON.stringify({ error: "Unauthorized" })
      };
    }

    // Step 2: Parse and validate request body
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

    // Step 3: Validate the original URL for security
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

    // Step 4: Validate custom code format if provided (3-20 alphanumeric, hyphen, underscore)
    if (customCode && !/^[a-z0-9_-]{3,20}$/i.test(customCode)) {
      return {
        statusCode: 400,
        body: JSON.stringify({ 
          error: "Invalid custom code",
          details: "Code must be 3-20 alphanumeric characters"
        })
      };
    }

    // Step 5: Generate short code (use custom or random)
    const code = customCode || generateCode();
    const now = Date.now();
    // Set expiration to 1 year from now (in Unix timestamp seconds)
    const expiresAt = Math.floor(now / 1000) + (365 * 24 * 60 * 60);

    // Step 6: Store the URL mapping in DynamoDB
    // ConditionExpression ensures we don't overwrite existing codes
    await ddb.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          code,                           // Partition key
          userId,                         // Who created this URL
          originalUrl,                    // The actual long URL
          createdAt: now,                 // Creation timestamp
          expiresAt,                      // When this URL expires
          status: "active",               // Current status
          clickCount: 0,                  // Initialize click tracking
          tags: body.tags || []           // Optional tags for organization
        },
        // Prevent overwriting - throw error if code already exists
        ConditionExpression: "attribute_not_exists(code)"
      })
    );

    log("info", "Short URL created", { code, userId });

    // Step 7: Return successful response with shortened URL details
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
    // Handle specific error cases with appropriate HTTP status codes
    
    // Code already exists - return 409 Conflict
    if (error.name === "ConditionalCheckFailedException") {
      log("warn", "Code already exists", { error: error.message });
      return {
        statusCode: 409,
        body: JSON.stringify({ error: "Short code already in use" })
      };
    }

    // DynamoDB validation error - return 400 Bad Request
    if (error.name === "ValidationException") {
      log("error", "DynamoDB validation error", { error: error.message });
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Invalid request" })
      };
    }

    // Unexpected error - return 500 Internal Server Error
    log("error", "Failed to create short URL", { error: error.message });
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Internal server error" })
    };
  }
}

/**
 * GET /{code} - Redirect to original URL and increment click count
 * 
 * Functionality:
 * - Retrieves the URL mapping from DynamoDB
 * - Checks if the URL is active and not expired
 * - Increments click count asynchronously (non-blocking)
 * - Returns HTTP 302 redirect to original URL
 * 
 * Returns:
 * 302: Redirect to original URL
 * 400: Invalid code parameter
 * 404: Short URL not found
 * 410: URL expired or inactive
 * 500: Server error
 */
async function handleRedirect(event) {
  try {
    // Step 1: Extract the short code from URL path parameter
    const code = event.pathParameters?.code;

    if (!code) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Missing code parameter" })
      };
    }

    // Step 2: Retrieve the URL mapping from DynamoDB using the code as partition key
    const result = await ddb.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: { code }
      })
    );

    // Step 3: Check if the URL mapping exists
    if (!result.Item) {
      log("info", "URL not found", { code });
      return {
        statusCode: 404,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: "Short URL not found" })
      };
    }

    // Step 4: Verify the URL is active (not inactive/deleted)
    // Could be "active", "inactive", or "expired"
    if (result.Item.status !== "active") {
      log("info", "URL inactive", { code, status: result.Item.status });
      return {
        statusCode: 410,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ error: "Short URL no longer available" })
      };
    }

    // Step 5: Update click count asynchronously (fire-and-forget)
    // This doesn't block the redirect response, improving performance
    ddb.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: { code },
        // Increment clickCount, initialize to 0 if not exists, update lastAccessedAt timestamp
        UpdateExpression: "SET clickCount = if_not_exists(clickCount, :zero) + :inc, lastAccessedAt = :now",
        ExpressionAttributeValues: {
          ":zero": 0,           // Default value if clickCount doesn't exist
          ":inc": 1,            // Increment by 1
          ":now": Date.now()    // Current timestamp
        }
      })
    ).catch(err => {
      // Log any errors but don't fail the redirect
      log("warn", "Failed to update click count", { code, error: err.message });
    });

    log("info", "URL redirect", { code, clickCount: result.Item.clickCount + 1 });

    // Step 6: Return HTTP 302 redirect response with original URL
    // Cache-Control: no-cache prevents browser caching of the redirect
    return {
      statusCode: 302,
      headers: {
        "Location": result.Item.originalUrl,  // The destination URL
        "Cache-Control": "no-cache"           // Don't cache redirect
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

/**
 * Lambda Handler - Main entry point
 * 
 * Receives HTTP requests from API Gateway and routes them to appropriate handlers
 * 
 * Routing Logic:
 * - POST /shorten → Create shortened URL
 * - GET /{code} → Redirect to original URL
 * - Other methods/paths → Return 405 Method Not Allowed
 * 
 * @param {object} event - API Gateway Lambda proxy integration event
 * @returns {object} - Lambda proxy integration response
 */
export const handler = async (event) => {
  try {
    // Extract HTTP method and path from API Gateway event
    const method = event.requestContext.http.method;
    const path = event.requestContext.http.path;

    log("info", "Incoming request", { method, path });

    // Route to appropriate handler based on HTTP method and path
    if (method === "POST" && path === "/shorten") {
      return await handleCreateShortUrl(event);
    }

    if (method === "GET") {
      return await handleRedirect(event);
    }

    // Unsupported HTTP method or path
    return {
      statusCode: 405,
      body: JSON.stringify({ error: "Method not allowed" })
    };
  } catch (error) {
    // Catch any unhandled errors at the top level
    log("error", "Unhandled error", { error: error.message, stack: error.stack });
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Internal server error" })
    };
  }
};
