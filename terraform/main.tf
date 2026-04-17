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