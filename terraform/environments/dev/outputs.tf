output "query_api_url" {
  value = "${module.apigateway.invoke_url}/query"
}

output "document_bucket_name" {
  value = module.s3.bucket_name
}

output "user_pool_id" {
  value = module.auth.user_pool_id
}

output "user_pool_client_id" {
  value = module.auth.client_id
}

output "query_function_name" {
  value = module.lambda.query_function_name
}

output "ingestion_function_name" {
  value = module.lambda.ingestion_function_name
}

output "ingestion_dlq_url" {
  value = module.lambda.ingestion_dlq_url
}

output "vector_bucket_name" {
  value = module.vectors.bucket_name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${module.monitoring.dashboard_name}"
}
