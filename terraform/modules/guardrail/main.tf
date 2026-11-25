locals {
  # PROMPT_ATTACK applies to user input only, so its output strength must be NONE.
  # MISCONDUCT is MEDIUM: at HIGH it also blocks low-confidence matches, and ordinary policy
  # questions ("Can I use my personal laptop for customer data?") were blocked as misconduct.
  content_filters = {
    HATE          = { input = "HIGH", output = "HIGH" }
    INSULTS       = { input = "HIGH", output = "HIGH" }
    SEXUAL        = { input = "HIGH", output = "HIGH" }
    VIOLENCE      = { input = "HIGH", output = "HIGH" }
    MISCONDUCT    = { input = "MEDIUM", output = "MEDIUM" }
    PROMPT_ATTACK = { input = "HIGH", output = "NONE" }
  }

  # Secrets and payment data are blocked outright; contact details are masked.
  pii_actions = {
    US_SOCIAL_SECURITY_NUMBER = "BLOCK"
    CREDIT_DEBIT_CARD_NUMBER  = "BLOCK"
    AWS_ACCESS_KEY            = "BLOCK"
    AWS_SECRET_KEY            = "BLOCK"
    PASSWORD                  = "BLOCK"
    EMAIL                     = "ANONYMIZE"
    PHONE                     = "ANONYMIZE"
  }
}

resource "aws_bedrock_guardrail" "this" {
  name                      = "${var.name_prefix}-guardrail"
  description               = "Screens employee questions and generated answers."
  blocked_input_messaging   = "Sorry, I cannot help with that request. Please rephrase your question."
  blocked_outputs_messaging = "Sorry, the answer was withheld because it may contain restricted information."

  content_policy_config {
    dynamic "filters_config" {
      for_each = local.content_filters
      content {
        type            = filters_config.key
        input_strength  = filters_config.value.input
        output_strength = filters_config.value.output
      }
    }
  }

  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = local.pii_actions
      content {
        type   = pii_entities_config.key
        action = pii_entities_config.value
      }
    }
  }
}

# A version is an immutable snapshot, and the Lambda uses the version number. Publish a new
# version whenever the guardrail's policy changes, otherwise the change never takes effect.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "Managed by Terraform"

  lifecycle {
    replace_triggered_by = [aws_bedrock_guardrail.this]
  }
}
