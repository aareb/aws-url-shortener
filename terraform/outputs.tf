output "api_endpoint" {
  description = "Base URL of the API Gateway"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "dynamodb_table_name" {
  description = "DynamoDB table used for URL storage"
  value       = aws_dynamodb_table.urls.name
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.shortener.function_name
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.client.id
}

output "cognito_issuer_url" {
  description = "JWT issuer URL for Cognito"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}