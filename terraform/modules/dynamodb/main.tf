# Document registry: one item per source document (ETag, chunk count, status).
# Makes ingestion idempotent and lets deletes find every vector a document owns.
resource "aws_dynamodb_table" "documents" {
  name                        = "${var.name_prefix}-documents"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "document_key"
  deletion_protection_enabled = var.deletion_protection

  attribute {
    name = "document_key"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# Daily question counters per user (sub#YYYY-MM-DD). Items expire automatically after two days.
resource "aws_dynamodb_table" "usage" {
  name         = "${var.name_prefix}-usage"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "usage_key"

  attribute {
    name = "usage_key"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }
}
