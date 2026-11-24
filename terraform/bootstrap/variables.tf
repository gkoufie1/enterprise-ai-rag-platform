variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "enterprise-ai-rag"
}

variable "github_repository" {
  description = "owner/repo allowed to assume the plan role. Empty skips the GitHub OIDC setup."
  type        = string
  default     = ""
}

variable "create_github_oidc_provider" {
  description = "Set false if this AWS account already has the token.actions.githubusercontent.com provider."
  type        = bool
  default     = true
}
