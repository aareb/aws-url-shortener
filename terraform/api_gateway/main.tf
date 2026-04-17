variable "env" {}
variable "aws_region" {}
variable "log_bucket_arn" {}
variable "lambda_invoke_arn" {}
variable "waf_arn" {}
variable "cognito_user_pool_id" {}
variable "cognito_user_pool_client_id" {}

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.env}-url-shortener-api"
  protocol_type = "HTTP"
  description   = "URL Shortener API - ${var.env} environment"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    expose_headers = ["Content-Type"]
  }

  tags = {
    Environment = var.env
    Service     = "url-shortener"
  }
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.env}-jwt-authorizer"

  jwt_configuration {
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}"
    audience = [var.cognito_user_pool_client_id]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = var.lambda_invoke_arn
  payload_format_version = "2.0"
}

# POST /shorten - Create short URL (requires authentication)
resource "aws_apigatewayv2_route" "shorten" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /shorten"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# GET /{code} - Redirect to original URL (public, no auth)
resource "aws_apigatewayv2_route" "redirect" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /{code}"

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# OPTIONS for CORS preflight
resource "aws_apigatewayv2_route" "cors_options" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = var.log_bucket_arn
    format = jsonencode({
      requestId               = "$context.requestId"
      ip                      = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      status                  = "$context.status"
      protocol                = "$context.protocol"
      responseLength          = "$context.responseLength"
      integrationLatency      = "$context.integration.latency"
      integrationErrorMessage = "$context.integrationErrorMessage"
      error                   = "$context.error.message"
      errorType               = "$context.error.messageString"
    })
  }

  tags = {
    Environment = var.env
    Service     = "url-shortener"
  }
}

# WAF association for API Gateway
resource "aws_wafv2_web_acl_association" "api_waf" {
  resource_arn = aws_apigatewayv2_stage.default.arn
  web_acl_arn  = var.waf_arn
}

# CloudWatch Alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.env}-api-5xx-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "5XX"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alert when API Gateway returns 5XX errors"

  dimensions = {
    ApiName = aws_apigatewayv2_api.api.name
    Stage   = aws_apigatewayv2_stage.default.name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${var.env}-api-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Average"
  threshold           = 1000  # 1 second
  alarm_description   = "Alert when API latency exceeds 1 second"

  dimensions = {
    ApiName = aws_apigatewayv2_api.api.name
    Stage   = aws_apigatewayv2_stage.default.name
  }
}