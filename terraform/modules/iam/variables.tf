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
