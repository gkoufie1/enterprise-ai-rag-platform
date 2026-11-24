variable "name_prefix" {
  type = string
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete a bucket that still holds documents."
  type        = bool
  default     = false
}

variable "noncurrent_version_days" {
  type    = number
  default = 30
}
