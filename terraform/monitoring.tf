resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.shortener.function_name}"
  retention_in_days = 14

  tags = {
    Environment = var.env
    Service     = "url-shortener"
  }
}