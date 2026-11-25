variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "callback_urls" {
  description = "Front-end URLs the hosted login may redirect back to (sign-in and sign-out)."
  type        = list(string)
}
