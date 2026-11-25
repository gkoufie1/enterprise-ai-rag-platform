variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "source_dir" {
  description = "Folder with index.html, app.js and styles.css."
  type        = string
}

variable "api_url" {
  description = "Full URL of the POST /query endpoint."
  type        = string
}

variable "cognito_domain_url" {
  description = "Hosted login base URL, https://<prefix>.auth.<region>.amazoncognito.com."
  type        = string
}

variable "client_id" {
  description = "Cognito web app client ID."
  type        = string
}

variable "demo_login_hint" {
  description = "Text shown on the sign-in screen, such as the public demo credentials. Empty hides the box."
  type        = string
  default     = ""
}

variable "demo_daily_limit" {
  type    = number
  default = 0
}

variable "force_destroy" {
  type    = bool
  default = false
}
