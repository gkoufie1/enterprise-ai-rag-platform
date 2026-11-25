variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "enterprise-ai-rag"
}

variable "environment" {
  type    = string
  default = "dev"
}

# ---------------------------------------------------------------- models
variable "claude_endpoint" {
  description = <<-EOT
    How the query function reaches Claude on Amazon Bedrock:
      runtime - classic bedrock-runtime InvokeModel with an inference profile ID
                (e.g. us.anthropic.claude-haiku-4-5-20251001-v1:0). Available to most accounts.
      mantle  - Claude in Amazon Bedrock Messages API (e.g. anthropic.claude-opus-5-5). Needed for
                the newest models, which AWS enables per account.
  EOT
  type        = string
  default     = "runtime"

  validation {
    condition     = contains(["runtime", "mantle"], var.claude_endpoint)
    error_message = "claude_endpoint must be runtime or mantle."
  }
}

variable "claude_model_id" {
  description = "Model ID for the chosen endpoint. To upgrade: claude_endpoint = \"mantle\", claude_model_id = \"anthropic.claude-opus-5-5\"."
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "fallback_model_id" {
  description = "mantle endpoint only: model that retries a request the main model refuses (e.g. anthropic.claude-opus-4-8). Empty disables it."
  type        = string
  default     = ""
}

variable "claude_effort" {
  description = "Claude effort level (mantle endpoint only). Short grounded Q&A does well at low."
  type        = string
  default     = "low"

  validation {
    condition     = contains(["low", "medium", "high", "xhigh", "max"], var.claude_effort)
    error_message = "claude_effort must be one of low, medium, high, xhigh, max."
  }
}

variable "embedding_model_id" {
  type    = string
  default = "amazon.titan-embed-text-v2:0"
}

variable "embedding_dimensions" {
  description = "Titan V2 supports 256, 512 or 1024. Changing it requires re-creating the vector index."
  type        = number
  default     = 1024

  validation {
    condition     = contains([256, 512, 1024], var.embedding_dimensions)
    error_message = "embedding_dimensions must be 256, 512 or 1024."
  }
}

# ---------------------------------------------------------------- retrieval
variable "top_k" {
  type    = number
  default = 5
}

variable "max_distance" {
  description = "Cosine distance above which a retrieved chunk is treated as irrelevant."
  type        = number
  default     = 0.75
}

variable "chunk_words" {
  type    = number
  default = 250
}

variable "chunk_overlap_words" {
  type    = number
  default = 40
}

# ---------------------------------------------------------------- security and operations
variable "enable_guardrail" {
  type    = bool
  default = true
}

variable "allowed_origins" {
  description = "Extra browser origins allowed to call the API and sign in, for local development. The deployed site is always allowed."
  type        = list(string)
  default     = ["http://localhost:3000"]
}

variable "throttle_rate_limit" {
  type    = number
  default = 5
}

variable "throttle_burst_limit" {
  type    = number
  default = 10
}

variable "alarm_email" {
  description = "Email address subscribed to alarm notifications (confirm the email AWS sends)."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "force_destroy" {
  description = "Let terraform destroy delete buckets that still contain data. Keep false outside dev."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- front end and demo access
variable "demo_daily_limit" {
  description = "Questions per day for each account in the Cognito 'demo' group (everyone using a shared demo login shares it). 0 = unlimited."
  type        = number
  default     = 30
}

variable "user_daily_limit" {
  description = "Questions per day for each other user. 0 = unlimited."
  type        = number
  default     = 0
}

variable "demo_login_hint" {
  description = "Shown on the sign-in screen, e.g. \"Email: demo@example.com  Password: ...\". Empty hides it."
  type        = string
  default     = ""
}
