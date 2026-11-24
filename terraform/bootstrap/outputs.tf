output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "github_plan_role_arn" {
  description = "Store as the AWS_PLAN_ROLE_ARN repository variable in GitHub."
  value       = var.github_repository == "" ? null : aws_iam_role.github_plan[0].arn
}
