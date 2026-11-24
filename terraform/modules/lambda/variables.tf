variable "build_dir" {
  description = "Directory containing the built query/ and ingestion/ packages."
  type        = string
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

variable "query_role_arn" {
  type = string
}

variable "ingestion_role_arn" {
  type = string
}

variable "query_environment" {
  type = map(string)
}

variable "ingestion_environment" {
  type = map(string)
}

variable "document_bucket_name" {
  type = string
}

variable "document_bucket_arn" {
  type = string
}

variable "ingest_suffixes" {
  description = "File suffixes that trigger ingestion. Must match what the ingestion code supports."
  type        = list(string)
  default     = [".md", ".txt"]
}

variable "log_retention_days" {
  type    = number
  default = 30
}
