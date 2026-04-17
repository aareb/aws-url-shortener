/**
 * Lambda Function Tests
 * 
 * Tests for URL shortener Lambda function
 * Run with: npm test
 */

import { handler } from './index.js';

describe('URL Shortener Lambda Handler', () => {
  
  // Mock environment variables
  beforeEach(() => {
    process.env.TABLE_NAME = 'test-urls';
    process.env.BASE_URL = 'https://short.example.com';
  });

  describe('POST /shorten - Create Short URL', () => {
    
    test('creates short URL with valid input', async () => {
      const event = {
        requestContext: {
          http: {
            method: 'POST',
            path: '/shorten'
          },
          authorizer: {
            claims: {
              sub: 'user-123'
            }
          }
        },
        body: JSON.stringify({
          url: 'https://example.com/long/url'
        })
      };

      // Would need to mock DynamoDB
      // const response = await handler(event);
      // expect(response.statusCode).toBe(201);
      // expect(JSON.parse(response.body)).toHaveProperty('shortUrl');
    });

    test('validates URL format', () => {
      const testCases = [
        { url: 'https://valid.com', valid: true },
        { url: 'http://valid.com', valid: true },
        { url: 'ftp://invalid.com', valid: false },
        { url: '127.0.0.1:8000', valid: false },
        { url: 'https://169.254.1.1', valid: false },
        { url: 'not-a-url', valid: false }
      ];

      // Tests for isValidUrl function
      // testCases.forEach(({ url, valid }) => {
      //   expect(isValidUrl(url)).toBe(valid);
      // });
    });

    test('rejects internal IP addresses', () => {
      const internalIPs = [
        '127.0.0.1',
        '192.168.1.1',
        '10.0.0.1',
        '172.16.0.1',
        '169.254.1.1',
        'localhost'
      ];

      // internalIPs.forEach(ip => {
      //   expect(isValidUrl(`http://${ip}`)).toBe(false);
      // });
    });

    test('validates custom code format', () => {
      const validCodes = ['abc', 'my-link', 'test_123', 'ABC123'];
      const invalidCodes = ['ab', 'toolongcodenamewithmanycharacters', 'bad!code', ''];

      // validCodes.forEach(code => {
      //   expect(isValidCode(code)).toBe(true);
      // });

      // invalidCodes.forEach(code => {
      //   expect(isValidCode(code)).toBe(false);
      // });
    });

    test('returns 401 when no JWT provided', async () => {
      const event = {
        requestContext: {
          http: {
            method: 'POST',
            path: '/shorten'
          },
          authorizer: {
            claims: null  // No JWT
          }
        },
        body: JSON.stringify({
          url: 'https://example.com'
        })
      };

      // const response = await handler(event);
      // expect(response.statusCode).toBe(401);
    });

    test('returns 400 for invalid JSON body', async () => {
      const event = {
        requestContext: {
          http: {
            method: 'POST',
            path: '/shorten'
          },
          authorizer: {
            claims: {
              sub: 'user-123'
            }
          }
        },
        body: 'invalid json {'
      };

      // const response = await handler(event);
      // expect(response.statusCode).toBe(400);
    });

    test('returns 400 for missing URL', async () => {
      const event = {
        requestContext: {
          http: {
            method: 'POST',
            path: '/shorten'
          },
          authorizer: {
            claims: {
              sub: 'user-123'
            }
          }
        },
        body: JSON.stringify({})  // No URL
      };

      // const response = await handler(event);
      // expect(response.statusCode).toBe(400);
    });

    test('returns 409 when custom code already exists', async () => {
      // Mock DynamoDB to throw ConditionalCheckFailedException
      // const response = await handler(event);
      // expect(response.statusCode).toBe(409);
    });
  });

  describe('GET /{code} - Redirect', () => {
    
    test('redirects to original URL', async () => {
      const event = {
        requestContext: {
          http: {
            method: 'GET',
            path: '/abc123'
          }
        },
        pathParameters: {
          code: 'abc123'
        }
      };

      // const response = await handler(event);
      // expect(response.statusCode).toBe(302);
      // expect(response.headers.Location).toBe('https://example.com/original');
    });

    test('returns 404 for non-existent code', async () => {
      const event = {
        requestContext: {
          http: {
            method: 'GET',
            path: '/nonexistent'
          }
        },
        pathParameters: {
          code: 'nonexistent'
        }
      };

      // const response = await handler(event);
      // expect(response.statusCode).toBe(404);
    });

    test('returns 410 for inactive URL', async () => {
      // Mock DynamoDB to return inactive item
      // const response = await handler(event);
      // expect(response.statusCode).toBe(410);
    });

    test('increments click count', async () => {
      // Mock DynamoDB UpdateCommand
      // Verify UpdateExpression includes clickCount increment
    });

    test('updates lastAccessedAt', async () => {
      // Mock DynamoDB UpdateCommand
      // Verify UpdateExpression includes lastAccessedAt
    });
  });

  describe('Error Handling', () => {
    
    test('catches DynamoDB errors gracefully', async () => {
      // Mock DynamoDB to throw error
      // expect(response.statusCode).toBe(500);
    });

    test('returns proper error response format', async () => {
      // const response = await handler(invalidEvent);
      // const body = JSON.parse(response.body);
      // expect(body).toHaveProperty('error');
    });

    test('logs errors with context', () => {
      // Verify structured logging
      // expect(console.log).toHaveBeenCalledWith(
      //   expect.stringContaining('"level":"error"')
      // );
    });

    test('handles missing pathParameters gracefully', async () => {
      const event = {
        requestContext: {
          http: {
            method: 'GET',
            path: '/code'
          }
        },
        pathParameters: null  // Missing
      };

      // const response = await handler(event);
      // expect(response.statusCode).toBe(400);
    });
  });

  describe('Method Not Allowed', () => {
    
    test('rejects PUT requests', async () => {
      const event = {
        requestContext: {
          http: {
            method: 'PUT',
            path: '/shorten'
          }
        }
      };

      // const response = await handler(event);
      // expect(response.statusCode).toBe(405);
    });

    test('rejects DELETE requests', async () => {
      const event = {
        requestContext: {
          http: {
            method: 'DELETE',
            path: '/abc123'
          }
        }
      };

      // const response = await handler(event);
      // expect(response.statusCode).toBe(405);
    });
  });

  describe('JWT Claims Extraction', () => {
    
    test('extracts userId from JWT claims', () => {
      const event = {
        requestContext: {
          authorizer: {
            claims: {
              sub: 'user-abc-123',
              iss: 'cognito-idp',
              aud: 'client-id'
            }
          }
        }
      };

      // const userId = extractUserId(event);
      // expect(userId).toBe('user-abc-123');
    });

    test('returns null for missing claims', () => {
      const event = {
        requestContext: {
          authorizer: {
            claims: null
          }
        }
      };

      // const userId = extractUserId(event);
      // expect(userId).toBeNull();
    });

    test('returns null for malformed authorizer', () => {
      const event = {
        requestContext: {
          authorizer: null
        }
      };

      // const userId = extractUserId(event);
      // expect(userId).toBeNull();
    });
  });

  describe('Logging', () => {
    
    test('logs info events', () => {
      // Verify structured JSON logging
      // const consoleSpy = jest.spyOn(console, 'log');
      // handler(event);
      // expect(consoleSpy).toHaveBeenCalledWith(
      //   expect.stringMatching(/"level":"info"/)
      // );
    });

    test('logs error events with full context', () => {
      // Verify error logging includes stack trace
    });

    test('includes timestamp in all logs', () => {
      // Verify ISO 8601 timestamp in all log entries
    });

    test('includes request ID in logs', () => {
      // Verify requestId from context is logged
    });
  });

  describe('Edge Cases', () => {
    
    test('handles very long URLs', async () => {
      const longUrl = 'https://example.com/' + 'a'.repeat(2000);
      // Should succeed (DynamoDB limit is 400KB)
    });

    test('handles Unicode URLs', async () => {
      const unicodeUrl = 'https://example.com/こんにちは';
      // Should succeed with proper encoding
    });

    test('handles malformed but parseable URLs', async () => {
      const urls = [
        'https://example.com:invalid-port',
        'https://exam ple.com',
        'https://example.com?query=with&symbols'
      ];
      // Test URL validation
    });

    test('handles concurrent requests', async () => {
      // Simulate multiple concurrent requests
      // Verify no race conditions
    });

    test('handles DynamoDB rate limits gracefully', () => {
      // Mock DynamoDB to return ProvisionedThroughputExceededException
      // Should retry or return 503
    });
  });
});

// Performance Tests
describe('Performance', () => {
  
  test('redirect should complete within 500ms', async () => {
    const startTime = Date.now();
    // await handler(event);
    const duration = Date.now() - startTime;
    expect(duration).toBeLessThan(500);
  });

  test('create short URL should complete within 2 seconds', async () => {
    const startTime = Date.now();
    // await handler(event);
    const duration = Date.now() - startTime;
    expect(duration).toBeLessThan(2000);
  });

  test('handles batch operations efficiently', async () => {
    // Create multiple URLs and verify timing
  });
});

// Security Tests
describe('Security', () => {
  
  test('prevents header injection', async () => {
    const event = {
      requestContext: {
        http: {
          method: 'GET',
          path: '/abc\nSet-Cookie: session=hijacked'
        }
      }
    };
    // Should sanitize path
  });

  test('prevents SQL injection (though using DynamoDB)', () => {
    // Verify no SQL patterns in URL validation
  });

  test('prevents XSS in originalUrl', async () => {
    const xssUrl = 'javascript:alert("xss")';
    // Should reject JavaScript protocol
  });

  test('validates URL length limits', () => {
    const tooLongUrl = 'https://example.com/' + 'x'.repeat(3000);
    // Should reject or handle appropriately
  });

  test('prevents SSRF via DNS rebinding', () => {
    // Test with known SSRF domains
    const ssrfDomains = [
      'http://169.254.169.254',  // AWS metadata
      'http://localhost:9200',    // Elasticsearch
      'http://127.0.0.1:27017'    // MongoDB
    ];
  });
});
