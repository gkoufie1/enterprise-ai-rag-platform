variable "name_prefix" {
  type = string
}

variable "dimension" {
  description = "Must match the embedding model's output size."
  type        = number
}

variable "force_destroy" {
  type    = bool
  default = false
}
