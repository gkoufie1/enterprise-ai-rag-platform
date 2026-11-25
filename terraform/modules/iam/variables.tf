variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "query_function_name" {
  type = string
}

variable "ingestion_function_name" {
  type = string
}

variable "ingestion_dlq_name" {
  type = string
}

variable "document_bucket_arn" {
  type = string
}

variable "table_arn" {
  type = string
}

variable "vector_index_arn" {
  type = string
}

variable "embedding_model_id" {
  type = string
}

variable "guardrail_arn" {
  description = "Null when the guardrail is disabled."
  type        = string
  default     = null
}

variable "claude_endpoint" {
  description = "runtime or mantle; decides which Bedrock permission the query role gets."
  type        = string
}

variable "claude_model_id" {
  description = "For the runtime endpoint: the inference profile ID (e.g. us.anthropic.claude-haiku-4-5-20251001-v1:0)."
  type        = string
}

variable "usage_table_arn" {
  description = "Table holding daily question counters."
  type        = string
}
