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
variable "claude_model_id" {
  description = "Claude model on Claude in Amazon Bedrock (anthropic.-prefixed ID)."
  type        = string
  default     = "anthropic.claude-opus-5-5"
}

variable "fallback_model_id" {
  description = "Model that retries a request the main model refuses. Empty disables the fallback."
  type        = string
  default     = "anthropic.claude-opus-4-8"
}

variable "claude_effort" {
  description = "Claude effort level. Short grounded Q&A does well at low."
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
  description = "Browser origins allowed to call the API (CORS)."
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
