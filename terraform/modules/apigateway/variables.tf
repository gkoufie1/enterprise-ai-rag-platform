variable "name_prefix" {
  type = string
}

variable "query_function_name" {
  type = string
}

variable "query_invoke_arn" {
  type = string
}

variable "jwt_issuer" {
  type = string
}

variable "jwt_audience" {
  type = list(string)
}

variable "allowed_origins" {
  description = "Browser origins allowed by CORS."
  type        = list(string)
}

variable "throttle_burst_limit" {
  type    = number
  default = 10
}

variable "throttle_rate_limit" {
  description = "Steady-state requests per second across the API."
  type        = number
  default     = 5
}

variable "log_retention_days" {
  type    = number
  default = 30
}
