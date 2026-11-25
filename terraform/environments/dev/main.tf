data "aws_caller_identity" "current" {}

locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  account_id        = data.aws_caller_identity.current.account_id
  metrics_namespace = "EnterpriseRAG"

  # Names are fixed up front so IAM policies can be scoped to them before the
  # functions and queue exist (avoids a dependency cycle between modules).
  query_function_name     = "${local.name_prefix}-query"
  ingestion_function_name = "${local.name_prefix}-ingestion"
  ingestion_dlq_name      = "${local.name_prefix}-ingestion-dlq"
}

module "s3" {
  source        = "../../modules/s3"
  name_prefix   = local.name_prefix
  force_destroy = var.force_destroy
}

module "vectors" {
  source        = "../../modules/vectors"
  name_prefix   = local.name_prefix
  dimension     = var.embedding_dimensions
  force_destroy = var.force_destroy
}

module "dynamodb" {
  source      = "../../modules/dynamodb"
  name_prefix = local.name_prefix
}

module "auth" {
  source      = "../../modules/auth"
  name_prefix = local.name_prefix
  region      = var.aws_region
  # The deployed site plus any local development origins (e.g. http://localhost:3000/).
  callback_urls = concat([module.frontend.callback_url], [for o in var.allowed_origins : "${trimsuffix(o, "/")}/"])
}

module "guardrail" {
  count       = var.enable_guardrail ? 1 : 0
  source      = "../../modules/guardrail"
  name_prefix = local.name_prefix
}

module "iam" {
  source                  = "../../modules/iam"
  name_prefix             = local.name_prefix
  region                  = var.aws_region
  account_id              = local.account_id
  query_function_name     = local.query_function_name
  ingestion_function_name = local.ingestion_function_name
  ingestion_dlq_name      = local.ingestion_dlq_name
  document_bucket_arn     = module.s3.bucket_arn
  table_arn               = module.dynamodb.table_arn
  vector_index_arn        = module.vectors.index_arn
  embedding_model_id      = var.embedding_model_id
  guardrail_arn           = var.enable_guardrail ? module.guardrail[0].guardrail_arn : null
  usage_table_arn         = module.dynamodb.usage_table_arn
  claude_endpoint         = var.claude_endpoint
  claude_model_id         = var.claude_model_id
}

module "lambda" {
  source                  = "../../modules/lambda"
  build_dir               = "${path.root}/../../../build"
  account_id              = local.account_id
  query_function_name     = local.query_function_name
  ingestion_function_name = local.ingestion_function_name
  ingestion_dlq_name      = local.ingestion_dlq_name
  query_role_arn          = module.iam.query_role_arn
  ingestion_role_arn      = module.iam.ingestion_role_arn
  document_bucket_name    = module.s3.bucket_name
  document_bucket_arn     = module.s3.bucket_arn
  log_retention_days      = var.log_retention_days

  query_environment = {
    VECTOR_BUCKET        = module.vectors.bucket_name
    VECTOR_INDEX         = module.vectors.index_name
    EMBEDDING_MODEL_ID   = var.embedding_model_id
    EMBEDDING_DIMENSIONS = tostring(var.embedding_dimensions)
    CLAUDE_ENDPOINT      = var.claude_endpoint
    CLAUDE_MODEL_ID      = var.claude_model_id
    FALLBACK_MODEL_ID    = var.fallback_model_id
    CLAUDE_EFFORT        = var.claude_effort
    TOP_K                = tostring(var.top_k)
    MAX_DISTANCE         = tostring(var.max_distance)
    GUARDRAIL_ID         = var.enable_guardrail ? module.guardrail[0].guardrail_id : ""
    GUARDRAIL_VERSION    = var.enable_guardrail ? module.guardrail[0].guardrail_version : ""
    METRICS_NAMESPACE    = local.metrics_namespace
    USAGE_TABLE          = module.dynamodb.usage_table_name
    DEMO_DAILY_LIMIT     = tostring(var.demo_daily_limit)
    USER_DAILY_LIMIT     = tostring(var.user_daily_limit)
  }

  ingestion_environment = {
    DOCUMENT_BUCKET      = module.s3.bucket_name
    DOCUMENTS_TABLE      = module.dynamodb.table_name
    VECTOR_BUCKET        = module.vectors.bucket_name
    VECTOR_INDEX         = module.vectors.index_name
    EMBEDDING_MODEL_ID   = var.embedding_model_id
    EMBEDDING_DIMENSIONS = tostring(var.embedding_dimensions)
    CHUNK_WORDS          = tostring(var.chunk_words)
    CHUNK_OVERLAP_WORDS  = tostring(var.chunk_overlap_words)
  }
}

module "apigateway" {
  source               = "../../modules/apigateway"
  name_prefix          = local.name_prefix
  query_function_name  = module.lambda.query_function_name
  query_invoke_arn     = module.lambda.query_invoke_arn
  jwt_issuer           = module.auth.issuer
  jwt_audience         = [module.auth.client_id, module.auth.web_client_id]
  allowed_origins      = concat([module.frontend.url], var.allowed_origins)
  throttle_rate_limit  = var.throttle_rate_limit
  throttle_burst_limit = var.throttle_burst_limit
  log_retention_days   = var.log_retention_days
}

module "monitoring" {
  source                  = "../../modules/monitoring"
  name_prefix             = local.name_prefix
  region                  = var.aws_region
  query_function_name     = module.lambda.query_function_name
  ingestion_function_name = module.lambda.ingestion_function_name
  ingestion_dlq_name      = module.lambda.ingestion_dlq_name
  api_id                  = module.apigateway.api_id
  metrics_namespace       = local.metrics_namespace
  alarm_email             = var.alarm_email
}

module "frontend" {
  source             = "../../modules/frontend"
  name_prefix        = local.name_prefix
  region             = var.aws_region
  source_dir         = "${path.root}/../../../frontend"
  api_url            = "${module.apigateway.invoke_url}/query"
  cognito_domain_url = module.auth.hosted_ui_url
  client_id          = module.auth.web_client_id
  demo_login_hint    = var.demo_login_hint
  demo_daily_limit   = var.demo_daily_limit
  force_destroy      = var.force_destroy
}
