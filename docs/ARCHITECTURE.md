# Architecture notes

These notes supplement the diagram in the [README](../README.md) with the data model, the permissions, and how the system behaves when something fails.

## Data model

**S3 documents bucket.** The object key is the document's identity. Versioning keeps 30 days of earlier versions.

**S3 Vectors index `knowledge-chunks`** (1024 dimensions, float32, cosine):

| Field | Value |
|---|---|
| key | `sha256(document_key)[:32]-<chunk index, 5 digits>`, deterministic |
| data | Titan V2 embedding of the chunk |
| metadata `document_key` | filterable, for future per-document or per-department filters |
| metadata `chunk_index` | filterable |
| metadata `text` | non-filterable (outside the 2 KB filterable limit), returned with results |

**DynamoDB `documents` table** (partition key `document_key`): `etag`, `chunk_count`, `size_bytes`, `status` (`INDEXED` or `EMPTY`), `embedding_model`, `ingested_at`.

**DynamoDB `usage` table** (partition key `usage_key` = `<cognito sub>#<YYYY-MM-DD>`): `question_count`, plus `expires_at` for automatic TTL cleanup after two days. The query function increments it with one conditional `UpdateItem` (`ADD` only while the count is under the limit), so the check and the increment are atomic and concurrent requests can't exceed the quota.

The registry is what makes the pipeline safe to re-run:

- **Same ETag:** the file is skipped, with no embedding cost.
- **Fewer chunks than before:** the vectors for chunk numbers that no longer exist are deleted.
- **File deleted:** every vector the document owned is deleted, using the stored `chunk_count`.

## IAM matrix

| Permission | Ingestion role | Query role |
|---|---|---|
| `logs:CreateLogStream`, `PutLogEvents` | own log group | own log group |
| `s3:GetObject` | documents bucket | none |
| `dynamodb:GetItem`, `PutItem`, `DeleteItem` | registry table | none |
| `s3vectors:PutVectors`, `DeleteVectors` | the index | none |
| `s3vectors:QueryVectors`, `GetVectors` | none | the index (GetVectors is needed to return metadata) |
| `bedrock:InvokeModel` | Titan V2 only | Titan V2 only |
| `dynamodb:UpdateItem` | none | usage table (daily quota) |
| `bedrock-mantle:CreateInference` | none | Claude in Amazon Bedrock projects in this account and region |
| `bedrock:ApplyGuardrail` | none | the platform's guardrail |
| `sqs:SendMessage` | ingestion DLQ | none |
| X-Ray write | yes | yes |

Function names, the log groups and the DLQ name are computed up front in `environments/dev/main.tf`. That lets the IAM module scope its policies to these resources before they exist, without a dependency cycle between modules.

## Failure modes

| Failure | Behaviour | How you find out |
|---|---|---|
| Embedding or vector write fails during ingestion | Lambda retries the S3 event twice, then sends it to the SQS DLQ | `ingestion-errors` and `ingestion-dlq-not-empty` alarms; re-run with `scripts/reingest.sh` |
| Claude refuses a request | Retried once on the fallback model (Opus 4.8) by the SDK middleware; if that also refuses, the user gets a polite refusal | `model` field in the response, logs |
| Claude rate-limited | HTTP 429 with a retry message | `query-errors` alarm does not fire (handled); visible in access logs |
| Claude or Bedrock error | HTTP 502 | `api-5xx` alarm |
| Slow answers | Lambda timeout is 29 s, under API Gateway's 30 s limit | `query-latency-p95` alarm above 20 s |
| No relevant documents | "Not found" answer with no model call | `NoAnswer` metric on the dashboard; a rising rate means the documents have gaps |
| Demo account reaches its daily limit | HTTP 429 with a message saying when the quota resets; the model is never called | API access logs |
| Guardrail blocks input or output | The guardrail's message is returned with `blocked: true` | `GuardrailBlocked` metric |

## Tuning knobs

All of these are Terraform variables in `environments/dev/variables.tf`:

| Variable | Default | Effect |
|---|---|---|
| `claude_model_id` | `anthropic.claude-opus-5-5` | Quality versus cost |
| `claude_effort` | `low` | Higher effort means more reasoning and more latency |
| `top_k` | 5 | Chunks sent to the model |
| `max_distance` | 0.75 | Lower is stricter: fewer but more relevant chunks, more "not found" answers |
| `chunk_words`, `chunk_overlap_words` | 250, 40 | Smaller chunks give more precise citations but less context per chunk |
| `embedding_dimensions` | 1024 | 256 or 512 is cheaper to store; changing it re-creates the index |
| `demo_daily_limit`, `user_daily_limit` | 30, 0 | Daily questions per account; 0 means unlimited |

Measure every change with `eval/run_eval.py`.

## Web front end

```
browser --GET--> CloudFront (CSP, HSTS, DENY framing) --OAC--> private S3 bucket
browser --authorize (PKCE)--> Cognito hosted login --code--> browser --token--> Cognito
browser --POST /query, Bearer ID token--> API Gateway JWT authorizer (accepts the API and web client IDs)
```

The Content-Security-Policy allows connections only to `*.execute-api.<region>.amazonaws.com` and `*.auth.<region>.amazoncognito.com`. Wildcards keep the CloudFront policy independent of the API and login URLs, which would otherwise create a dependency cycle (the API's CORS settings need the CloudFront address).
