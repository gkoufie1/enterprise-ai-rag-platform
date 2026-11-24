# Amazon S3 Vectors: serverless vector storage, billed per GB stored and per query,
# with no always-on cluster cost (unlike OpenSearch Serverless).
resource "aws_s3vectors_vector_bucket" "this" {
  vector_bucket_name = "${var.name_prefix}-vectors"
  force_destroy      = var.force_destroy
}

resource "aws_s3vectors_index" "chunks" {
  vector_bucket_name = aws_s3vectors_vector_bucket.this.vector_bucket_name
  index_name         = "knowledge-chunks"
  data_type          = "float32"
  dimension          = var.dimension
  distance_metric    = "cosine"

  # Chunk text is returned with query results but never filtered on. Declaring it
  # non-filterable lifts it out of the 2 KB filterable-metadata limit.
  metadata_configuration {
    non_filterable_metadata_keys = ["text"]
  }
}
