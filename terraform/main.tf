provider "aws" {
  region = var.aws_region
}

module "waf" {
  source = "./waf"

  name           = "${var.env}-url-shortener"
  log_bucket_arn = var.log_bucket_arn
}

resource "aws_dynamodb_table" "urls" {
  table_name   = "${var.env}-urls"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "code"

  attribute {
    name = "code"
    type = "S"
  }

  # Global secondary index for querying URLs by user
  global_secondary_index {
    name            = "${var.env}-userId-createdAt-index"
    hash_key        = "userId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "N"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Environment = var.env
    Service     = "url-shortener"
  }
}

resource "aws_lambda_function" "shortener" {
  function_name = "${var.env}-url-shortener"
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")
  role             = aws_iam_role.lambda_role.arn

  # Production-grade concurrency settings
  reserved_concurrent_executions = var.env == "prod" ? 1000 : 100
  
  # Timeout for redirect operations
  timeout = 30
  memory_size = 256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.urls.name
      BASE_URL   = var.base_url
      ENVIRONMENT = var.env
    }
  }

  layers = []

  tracing_config {
    mode = "Active"
  }

  tags = {
    Environment = var.env
    Service     = "url-shortener"
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shortener.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.api_gateway.api_id}/*"
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
  name = "${var.env}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ],
        Effect   = "Allow",
        Resource = [
          aws_dynamodb_table.urls.arn,
          "${aws_dynamodb_table.urls.arn}/index/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "XRayAccess"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Sid    = "SSMParameterAccess"
        Action = ["ssm:GetParameter"]
        Effect = "Allow"
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.env}/url-shortener/*"
      }
    ]
  })
}

# API Gateway Module
module "api_gateway" {
  source = "./api_gateway"

  env                       = var.env
  aws_region                = var.aws_region
  log_bucket_arn            = var.log_bucket_arn
  lambda_invoke_arn         = aws_lambda_function.shortener.invoke_arn
  waf_arn                   = module.waf.waf_arn
  cognito_user_pool_id      = aws_cognito_user_pool.this.id
  cognito_user_pool_client_id = aws_cognito_user_pool_client.client.id
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