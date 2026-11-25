output "url" {
  value = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "callback_url" {
  description = "Exact redirect URI registered with Cognito (note the trailing slash)."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}/"
}

output "distribution_id" {
  value = aws_cloudfront_distribution.site.id
}
