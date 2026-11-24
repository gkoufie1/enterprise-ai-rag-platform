resource "aws_sns_topic" "alarms" {
  name              = "${var.name_prefix}-alarms"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarms = {
    query-errors = {
      description = "The query function raised errors."
      namespace   = "AWS/Lambda"
      metric      = "Errors"
      statistic   = "Sum"
      threshold   = 1
      dimensions  = { FunctionName = var.query_function_name }
    }
    query-throttles = {
      description = "The query function was throttled (concurrency limit reached)."
      namespace   = "AWS/Lambda"
      metric      = "Throttles"
      statistic   = "Sum"
      threshold   = 1
      dimensions  = { FunctionName = var.query_function_name }
    }
    ingestion-errors = {
      description = "Document ingestion failed. Check the function logs and the DLQ."
      namespace   = "AWS/Lambda"
      metric      = "Errors"
      statistic   = "Sum"
      threshold   = 1
      dimensions  = { FunctionName = var.ingestion_function_name }
    }
    ingestion-dlq-not-empty = {
      description = "An upload failed ingestion after all retries and is waiting in the DLQ."
      namespace   = "AWS/SQS"
      metric      = "ApproximateNumberOfMessagesVisible"
      statistic   = "Maximum"
      threshold   = 1
      dimensions  = { QueueName = var.ingestion_dlq_name }
    }
    api-5xx = {
      description = "The query API returned server errors."
      namespace   = "AWS/ApiGateway"
      metric      = "5xx"
      statistic   = "Sum"
      threshold   = 1
      dimensions  = { ApiId = var.api_id }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.name_prefix}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = each.value.statistic
  dimensions          = each.value.dimensions
  period              = 300
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

# p95 latency close to the 30 s API Gateway limit means users are about to see timeouts.
resource "aws_cloudwatch_metric_alarm" "query_latency_p95" {
  alarm_name          = "${var.name_prefix}-query-latency-p95"
  alarm_description   = "p95 query latency is above 20 s; API Gateway times out at 30 s."
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  extended_statistic  = "p95"
  dimensions          = { FunctionName = var.query_function_name }
  period              = 300
  evaluation_periods  = 2
  threshold           = 20000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-rag"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "API requests and errors"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", var.api_id],
            [".", "4xx", ".", "."],
            [".", "5xx", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Query latency (ms)"
          region = var.region
          period = 300
          metrics = [
            [var.metrics_namespace, "QueryLatency", "FunctionName", var.query_function_name, { stat = "p50", label = "p50" }],
            [var.metrics_namespace, "QueryLatency", "FunctionName", var.query_function_name, { stat = "p95", label = "p95" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Claude tokens"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            [var.metrics_namespace, "InputTokens", "FunctionName", var.query_function_name],
            [".", "OutputTokens", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Answer quality signals"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            [var.metrics_namespace, "NoAnswer", "FunctionName", var.query_function_name],
            [".", "GuardrailBlocked", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title  = "Lambda errors and throttles"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.query_function_name, { label = "query errors" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.ingestion_function_name, { label = "ingestion errors" }],
            ["AWS/Lambda", "Throttles", "FunctionName", var.query_function_name, { label = "query throttles" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          title  = "Ingestion"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.ingestion_function_name, { stat = "Sum" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.ingestion_dlq_name, { stat = "Maximum", label = "DLQ depth" }],
          ]
        }
      },
    ]
  })
}
