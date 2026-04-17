provider "aws" {
  region = var.aws_region
}

module "waf" {
  source = "./waf"

  name           = "${var.env}-url-shortener"
  log_bucket_arn = var.log_bucket_arn
}

resource "aws_dynamodb_table" "urls" {
  name         = "${var.env}-urls"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "code"

  attribute {
    name = "code"
    type = "S"
  }
  ttl {
  attribute_name = "expiresAt"
  enabled        = true
}
}

resource "aws_lambda_function" "shortener" {
  function_name = "${var.env}-url-shortener"
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")
  role             = aws_iam_role.lambda_role.arn

  reserved_concurrent_executions = 50
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.urls.name
      BASE_URL   = var.base_url
    }
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shortener.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_iam_role_policy" "ssm_access" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["ssm:GetParameter"]
      Resource = aws_ssm_parameter.jwt_secret.arn
    }]
  })
}
resource "aws_iam_role" "lambda_role" {
  name = "${var.env}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = "logs:*",
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# API Gateway Configuration
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.env}-url-shortener-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  connection_type  = "INTERNET"
  integration_method = "POST"
  integration_uri  = aws_lambda_function.shortener.invoke_arn
}

resource "aws_apigatewayv2_route" "redirect" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /{code}"

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "shorten" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /shorten"

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.lambda_logs.arn
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

# WAF Association
resource "aws_wafv2_web_acl_association" "api_waf_assoc" {
  resource_arn = aws_apigatewayv2_stage.default.arn
  web_acl_arn  = module.waf.waf_arn
}

# CloudWatch Alarms
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