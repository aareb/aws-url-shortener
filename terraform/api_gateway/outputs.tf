output "api_endpoint" {
  description = "Base URL of the API Gateway"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.api.id
}

output "stage_name" {
  description = "API Gateway stage name"
  value       = aws_apigatewayv2_stage.default.name
}

output "stage_arn" {
  description = "API Gateway stage ARN"
  value       = aws_apigatewayv2_stage.default.arn
}