# Cognito user pool that issues the JWTs the API Gateway authorizer checks.
# Self sign-up is disabled: an administrator creates every user.
resource "aws_cognito_user_pool" "this" {
  name                = "${var.name_prefix}-users"
  user_pool_tier      = "LITE"
  username_attributes = ["email"]
  mfa_configuration   = "OPTIONAL"
  deletion_protection = var.deletion_protection ? "ACTIVE" : "INACTIVE"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_client" "api" {
  name            = "${var.name_prefix}-api-client"
  user_pool_id    = aws_cognito_user_pool.this.id
  generate_secret = false

  # USER_PASSWORD_AUTH keeps the demo scriptable from the CLI. A browser front end
  # should use the authorization-code flow with PKCE through a hosted login page instead.
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
  id_token_validity             = 60
  access_token_validity         = 60
  refresh_token_validity        = 1

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }
}
