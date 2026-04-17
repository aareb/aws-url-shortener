variable "name" {
  type = string
}

variable "scope" {
  type    = string
  default = "REGIONAL"
}

variable "log_bucket_arn" {
  type = string
}

resource "aws_wafv2_web_acl" "api_waf" {
  name        = var.name
  description = "WAF for URL shortener"
  scope       = var.scope

  default_action {
    allow {}
  }

  # Rate Limiting
  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }
}