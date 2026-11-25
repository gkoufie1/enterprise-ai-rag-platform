output "table_name" {
  value = aws_dynamodb_table.documents.name
}

output "table_arn" {
  value = aws_dynamodb_table.documents.arn
}

output "usage_table_name" {
  value = aws_dynamodb_table.usage.name
}

output "usage_table_arn" {
  value = aws_dynamodb_table.usage.arn
}
