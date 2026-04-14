resource "aws_wafv2_web_acl" "url_shortener_waf" {
  name        = "${var.environment}-url-shortener-waf"
  description = "Protects URL shortener from abusive traffic"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitPerIP"
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
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "UrlShortenerWAF"
    sampled_requests_enabled   = true
  }

  tags = {
    Service     = "url-shortener"
    Environment = var.environment
  }
}