# Outputs wait for the policies, so a function is never created with a role that
# cannot yet reach its DLQ or log group.
output "ingestion_role_arn" {
  value      = aws_iam_role.ingestion.arn
  depends_on = [aws_iam_role_policy.ingestion, aws_iam_role_policy_attachment.ingestion_xray]
}

output "query_role_arn" {
  value      = aws_iam_role.query.arn
  depends_on = [aws_iam_role_policy.query, aws_iam_role_policy_attachment.query_xray]
}
