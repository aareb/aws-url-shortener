resource "aws_wafv2_web_acl" "api_waf" {
  name        = "${var.environment}-url-shortener-waf"
  description = "WAF for URL shortener API"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "UrlShortenerWAF"
    sampled_requests_enabled   = true
  }
}
