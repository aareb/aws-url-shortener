variable "name" {}
variable "scope" { default = "REGIONAL" }
variable "api_gateway_arn" {}
variable "log_bucket_arn" {}

resource "aws_wafv2_web_acl" "this" {
  name  = var.name
  scope = var.scope

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "url-shortener-waf"
    sampled_requests_enabled   = true
  }
}
resource "aws_wafv2_web_acl" "this" {
  name  = var.name
  scope = var.scope

  default_action { allow {} }

# Rate Limiting
  rule {
    name     = "rate-limit"
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
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }
}
#bot control
rule {
  name     = "aws-bot-control"
  priority = 2

  override_action {
    none {}
  }

  statement {
    managed_rule_group_statement {
      name        = "AWSManagedRulesBotControlRuleSet"
      vendor_name = "AWS"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "bot-control"
    sampled_requests_enabled   = true
  }
}
# Endpoint-specific rule
rule {
  name     = "protect-shortener-path"
  priority = 3

  action { allow {} }

  statement {
    byte_match_statement {
      positional_constraint = "STARTS_WITH"
      search_string         = "/"
      field_to_match {
        uri_path {}
      }
      text_transformation {
        priority = 0
        type     = "NONE"
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "path-match"
    sampled_requests_enabled   = true
  }
}