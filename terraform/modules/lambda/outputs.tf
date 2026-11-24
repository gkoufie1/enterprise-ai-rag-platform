output "query_function_name" {
  value = aws_lambda_function.query.function_name
}

output "query_invoke_arn" {
  value = aws_lambda_function.query.invoke_arn
}

output "ingestion_function_name" {
  value = aws_lambda_function.ingestion.function_name
}

output "ingestion_dlq_name" {
  value = aws_sqs_queue.ingestion_dlq.name
}

output "ingestion_dlq_url" {
  value = aws_sqs_queue.ingestion_dlq.url
}
