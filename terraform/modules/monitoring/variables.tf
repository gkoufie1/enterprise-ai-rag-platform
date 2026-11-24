variable "name_prefix" {
  type = string
}

variable "region" {
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

variable "api_id" {
  type = string
}

variable "metrics_namespace" {
  description = "Namespace of the custom metrics the query function emits (EMF)."
  type        = string
}

variable "alarm_email" {
  description = "Email for alarm notifications. Empty disables the subscription."
  type        = string
  default     = ""
}
