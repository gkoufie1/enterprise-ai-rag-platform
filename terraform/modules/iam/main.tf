# One role per function, each scoped to exactly the resources that function touches.
locals {
  log_arn_prefix     = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda"
  embedding_model    = "arn:aws:bedrock:${var.region}::foundation-model/${var.embedding_model_id}"
  ingestion_dlq_arn  = "arn:aws:sqs:${var.region}:${var.account_id}:${var.ingestion_dlq_name}"
  mantle_project_arn = "arn:aws:bedrock-mantle:${var.region}:${var.account_id}:project/*"
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

# ---------------------------------------------------------------- ingestion
resource "aws_iam_role" "ingestion" {
  name               = "${var.name_prefix}-ingestion-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

data "aws_iam_policy_document" "ingestion" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.log_arn_prefix}/${var.ingestion_function_name}:*"]
  }
  statement {
    sid       = "ReadDocuments"
    actions   = ["s3:GetObject"]
    resources = ["${var.document_bucket_arn}/*"]
  }
  statement {
    sid       = "DocumentRegistry"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [var.table_arn]
  }
  statement {
    sid       = "WriteVectors"
    actions   = ["s3vectors:PutVectors", "s3vectors:DeleteVectors"]
    resources = [var.vector_index_arn]
  }
  statement {
    sid       = "Embeddings"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.embedding_model]
  }
  statement {
    sid       = "FailedEventsToDLQ"
    actions   = ["sqs:SendMessage"]
    resources = [local.ingestion_dlq_arn]
  }
}

resource "aws_iam_role_policy" "ingestion" {
  name   = "ingestion"
  role   = aws_iam_role.ingestion.id
  policy = data.aws_iam_policy_document.ingestion.json
}

resource "aws_iam_role_policy_attachment" "ingestion_xray" {
  role       = aws_iam_role.ingestion.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ---------------------------------------------------------------- query
resource "aws_iam_role" "query" {
  name               = "${var.name_prefix}-query-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

data "aws_iam_policy_document" "query" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.log_arn_prefix}/${var.query_function_name}:*"]
  }
  statement {
    # GetVectors is required alongside QueryVectors when returnMetadata=true.
    sid       = "SearchVectors"
    actions   = ["s3vectors:QueryVectors", "s3vectors:GetVectors"]
    resources = [var.vector_index_arn]
  }
  statement {
    sid       = "Embeddings"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.embedding_model]
  }
  statement {
    sid       = "DailyQuota"
    actions   = ["dynamodb:UpdateItem"]
    resources = [var.usage_table_arn]
  }
  statement {
    # Claude in Amazon Bedrock (the bedrock-mantle Messages API endpoint).
    sid       = "ClaudeInference"
    actions   = ["bedrock-mantle:CreateInference"]
    resources = [local.mantle_project_arn]
  }
  dynamic "statement" {
    for_each = var.guardrail_arn == null ? [] : [var.guardrail_arn]
    content {
      sid       = "Guardrail"
      actions   = ["bedrock:ApplyGuardrail"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "query" {
  name   = "query"
  role   = aws_iam_role.query.id
  policy = data.aws_iam_policy_document.query.json
}

resource "aws_iam_role_policy_attachment" "query_xray" {
  role       = aws_iam_role.query.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
