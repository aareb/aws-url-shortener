resource "aws_apigatewayv2_api" "api" {
  name          = "${var.env}-url-shortener-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
    audience = [aws_cognito_user_pool_client.client.id]
  }

  name = "jwt-authorizer"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  connection_type  = "INTERNET"
  integration_method = "POST"
  integration_uri  = aws_lambda_function.shortener.invoke_arn
}

resource "aws_apigatewayv2_route" "shorten" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /shorten"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "redirect" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /{code}"

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
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }
}

## WAF association
resource "aws_wafv2_web_acl_association" "api_waf_assoc" {
  resource_arn = aws_apigatewayv2_stage.default.arn
  web_acl_arn  = module.waf.waf_arn
}

## Lambda error alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.env}-url-shortener-lambda-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1

  dimensions = {
    FunctionName = aws_lambda_function.shortener.function_name
  }

  alarm_description = "Alert when Lambda function errors occur"
}

## API Gateway 5XX alarm
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.env}-url-shortener-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 5

  dimensions = {
    ApiId = aws_apigatewayv2_api.api.id
    Stage = aws_apigatewayv2_stage.default.name
  }

  alarm_description = "API Gateway 5XX errors detected"
}