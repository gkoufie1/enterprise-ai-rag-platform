# Packages are built by scripts/build_lambdas.sh (handler + rag_core + pip dependencies).
data "archive_file" "query" {
  type        = "zip"
  source_dir  = "${var.build_dir}/query"
  output_path = "${var.build_dir}/query.zip"
}

data "archive_file" "ingestion" {
  type        = "zip"
  source_dir  = "${var.build_dir}/ingestion"
  output_path = "${var.build_dir}/ingestion.zip"
}

# Log groups exist before the functions, so retention applies from the first invocation.
resource "aws_cloudwatch_log_group" "query" {
  name              = "/aws/lambda/${var.query_function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "ingestion" {
  name              = "/aws/lambda/${var.ingestion_function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "query" {
  function_name    = var.query_function_name
  role             = var.query_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  memory_size      = 1024
  timeout          = 29 # API Gateway HTTP APIs stop waiting at 30 s
  filename         = data.archive_file.query.output_path
  source_code_hash = data.archive_file.query.output_base64sha256

  environment {
    variables = var.query_environment
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.query.name
  }
}

resource "aws_lambda_function" "ingestion" {
  function_name    = var.ingestion_function_name
  role             = var.ingestion_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  memory_size      = 512
  timeout          = 300
  filename         = data.archive_file.ingestion.output_path
  source_code_hash = data.archive_file.ingestion.output_base64sha256

  environment {
    variables = var.ingestion_environment
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.ingestion.name
  }
}

# ---------------------------------------------------------------- automatic ingestion
# S3 invokes the ingestion function asynchronously. Lambda retries a failed event twice,
# then sends it to this dead-letter queue so no upload is silently lost.
resource "aws_sqs_queue" "ingestion_dlq" {
  name                      = var.ingestion_dlq_name
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

resource "aws_lambda_function_event_invoke_config" "ingestion" {
  function_name                = aws_lambda_function.ingestion.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600

  destination_config {
    on_failure {
      destination = aws_sqs_queue.ingestion_dlq.arn
    }
  }
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.ingestion.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = var.document_bucket_arn
  source_account = var.account_id
}

resource "aws_s3_bucket_notification" "documents" {
  bucket = var.document_bucket_name

  dynamic "lambda_function" {
    for_each = var.ingest_suffixes
    content {
      lambda_function_arn = aws_lambda_function.ingestion.arn
      events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
      filter_suffix       = lambda_function.value
    }
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}
