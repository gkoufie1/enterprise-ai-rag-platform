output "api_id" {
  value = aws_apigatewayv2_api.api.id
}

output "invoke_url" {
  value = aws_apigatewayv2_api.api.api_endpoint
}
