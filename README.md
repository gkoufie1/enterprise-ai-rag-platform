# Enterprise AI RAG Platform on AWS

A serverless retrieval-augmented generation (RAG) platform. Employees ask questions in plain English and get short answers grounded in internal documents, with citations to the exact passages. Everything is defined in Terraform and checked in CI.

![CI](https://github.com/gkoufie1/enterprise-ai-rag-platform/actions/workflows/rag-platform.yml/badge.svg)

## The problem

Policies, runbooks and onboarding guides are spread across wikis and drives. People spend time searching, support teams answer the same questions repeatedly, and generic chatbots make up answers because they have never seen the company's documents.

## What this platform does

- **Ingests documents automatically.** Dropping a Markdown or text file into S3 triggers chunking and embedding. Editing or deleting the file updates or removes its vectors.
- **Answers from the documents only.** Each question is embedded, the closest chunks are found with vector search, and Claude answers using only those chunks.
- **Shows its sources.** Every answer comes with citations that point to the document, the chunk and the exact sentence used.
- **Says "I don't know".** If nothing relevant is found, it says so instead of guessing.
- **Is secured and observable.** Cognito sign-in, Bedrock Guardrails on input and output, least-privilege IAM, alarms, a dashboard and tracing.

## Architecture

```mermaid
flowchart LR
    subgraph Ingestion
        U1[Document owner] -->|upload .md / .txt| S3[(S3 documents bucket<br/>versioned, encrypted, TLS only)]
        S3 -->|ObjectCreated / ObjectRemoved| IL[Ingestion Lambda]
        IL -->|chunk + embed| TE[Bedrock<br/>Titan Text Embeddings V2]
        IL -->|put / delete vectors| SV[(S3 Vectors index)]
        IL -->|ETag + chunk count| DDB[(DynamoDB<br/>document registry)]
        IL -. failed after retries .-> DLQ[[SQS dead-letter queue]]
    end

    subgraph Query
        U2[Employee] -->|sign in| COG[Cognito user pool]
        U2 -->|POST /query + JWT| APIGW[API Gateway HTTP API<br/>JWT authorizer, throttling]
        APIGW --> QL[Query Lambda]
        QL -->|check question| GR[Bedrock Guardrails]
        QL -->|embed question| TE
        QL -->|top-k similarity search| SV
        QL -->|chunks as cited documents| CL[Claude on Amazon Bedrock]
        QL -->|check answer| GR
    end

    subgraph Operations
        QL & IL --> CW[CloudWatch logs, EMF metrics,<br/>alarms, dashboard, X-Ray]
        CW --> SNS[SNS alarm email]
        GH[GitHub Actions] -->|lint, test, validate, scan, plan| TF[Terraform + S3 remote state]
    end
```

### How a question is answered

1. API Gateway rejects the request unless it carries a valid Cognito JWT. It also throttles traffic, which caps spend.
2. The query Lambda checks the question with a **Bedrock Guardrail**. Prompt-injection attempts, harmful content and secrets are blocked before any model sees them.
3. The question is embedded with **Titan Text Embeddings V2**. **S3 Vectors** returns the 5 closest chunks, and chunks further than a cosine-distance threshold are dropped.
4. If nothing relevant remains, the API answers "not found" without calling the language model, so these requests cost almost nothing.
5. Otherwise each chunk is sent to **Claude** (Opus 5.5 on Amazon Bedrock) as a separate document with citations enabled. The system prompt tells Claude to answer only from those documents and to treat their text as data, not instructions.
6. The answer goes through the guardrail a second time, which masks or blocks PII. The response carries the answer, citations, sources, the model used and token usage.

### How a document is ingested

S3 sends an event to the ingestion Lambda, which:

1. Compares the file's ETag with the DynamoDB registry and skips files that haven't changed.
2. Splits the text into 250-word chunks with a 40-word overlap and embeds each chunk.
3. Writes the vectors with deterministic keys, so a re-upload overwrites the old vectors in place.
4. Deletes the vectors for chunk numbers that no longer exist when a document gets shorter. Deleting a file removes all of its vectors.
5. Retries failures twice, then sends them to a dead-letter queue, which raises an alarm.

## Tech stack

| Layer | Service | Why this choice |
|---|---|---|
| Infrastructure as code | Terraform (modules, S3 remote state with native locking) | Repeatable environments, reviewable changes |
| Document storage | Amazon S3 | Versioned, encrypted, event source for ingestion |
| Embeddings | Amazon Titan Text Embeddings V2 (Bedrock) | Managed, 1024-dimension normalized vectors |
| Vector store | Amazon S3 Vectors | Pay per use with no idle cluster cost, a good fit for RAG at this scale |
| Generation | Claude Opus 5.5 on Claude in Amazon Bedrock | Strong grounded answers with native citations; stays inside the AWS account boundary |
| Safety | Amazon Bedrock Guardrails | Prompt-attack, content and PII filters on input and output |
| API | API Gateway HTTP API + Cognito JWT authorizer | Authenticated, throttled, access-logged |
| Compute | AWS Lambda (Python 3.13, arm64) | Serverless, scales to zero |
| Registry | DynamoDB (on demand, PITR) | Idempotent ingestion and clean deletes |
| Observability | CloudWatch Logs, EMF custom metrics, alarms, dashboard, X-Ray, SNS | Tokens, latency, no-answer rate, guardrail blocks |
| CI | GitHub Actions: ruff, pytest, terraform validate, Checkov, terraform plan via OIDC | No long-lived AWS keys in CI |

## Repository layout

```
app/
  rag_core/            shared code: chunking, embeddings, vector keys
  ingestion/handler.py S3 event -> chunks -> embeddings -> S3 Vectors
  query/handler.py     guardrail -> retrieval -> Claude with citations -> guardrail
terraform/
  bootstrap/           state bucket + GitHub OIDC plan role (applied once)
  environments/dev/    wires the modules together
  modules/             s3, vectors, dynamodb, auth, guardrail, iam, lambda, apigateway, monitoring
tests/                 unit tests with fake AWS and Claude clients
eval/                  15-question evaluation set and scoring script
scripts/               build, upload, create user, get token, query, re-ingest
sample-docs/           five fictional company documents to try it with
docs/                  architecture notes, interview guide, video script
```

## Deploy it

### Prerequisites

- An AWS account and the AWS CLI configured with admin credentials for the deployment.
- Terraform 1.10 or later, Python 3.13 or later, `jq`.
- **Bedrock model access** in your region, in the [Bedrock console](https://console.aws.amazon.com/bedrock/home#/modelaccess). You need Titan Text Embeddings V2 and Claude Opus 5.5 (`anthropic.claude-opus-5-5`); Opus 4.8 is used as the refusal fallback. Opus 5.5 may need an access request first. If you don't have it, set `claude_model_id` to a model you can use, such as `anthropic.claude-sonnet-5`.

### 1. Create the state bucket (once per account)

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="github_repository=gkoufie1/enterprise-ai-rag-platform"   # omit the variable to skip the CI plan role
```

### 2. Build and deploy

```bash
bash scripts/build_lambdas.sh                        # Lambda packages for Linux arm64

cd terraform/environments/dev
cp backend.hcl.example backend.hcl                   # set the bucket from step 1
cp terraform.tfvars.example terraform.tfvars         # set alarm_email, allowed_origins
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

Confirm the SNS subscription email so alarms reach you.

### 3. Load documents and ask a question

```bash
bash scripts/upload_docs.sh                          # ingestion starts automatically

export RAG_PASSWORD='Choose-a-Strong-Passw0rd!'
bash scripts/create_user.sh you@example.com
export RAG_TOKEN="$(bash scripts/get_token.sh you@example.com)"

bash scripts/query_api.sh "Can I use my personal laptop for customer data when working remotely?"
```

Example response:

```json
{
  "question": "Can I use my personal laptop for customer data when working remotely?",
  "answer": "No. Remote work must be done on a company-managed laptop, and personal devices may not be used to access customer data...",
  "citations": [
    {
      "document_key": "remote-work-policy.md",
      "chunk_index": 0,
      "cited_text": "Personal computers, tablets and phones may not be used to access customer data."
    }
  ],
  "sources": [{ "document_key": "remote-work-policy.md", "chunk_index": 0, "distance": 0.31 }],
  "model": "anthropic.claude-opus-5-5",
  "usage": { "input_tokens": 1874, "output_tokens": 96 }
}
```

(Illustrative; your text, distances and token counts will differ.)

## Evaluation

`eval/questions.jsonl` holds 15 cases: 12 answerable questions with the document that should be cited and keywords the answer must contain, 2 questions the documents can't answer (the system should abstain), and 1 prompt-injection attempt (the guardrail should block it).

```bash
export RAG_API_URL="$(terraform -chdir=terraform/environments/dev output -raw query_api_url)"
python eval/run_eval.py
```

It reports retrieval hit rate, citation accuracy, keyword accuracy, correct abstentions and blocked attacks, then writes `eval/results.json`. Re-run it after changing the chunk size, `top_k`, the distance threshold, the model or the prompt, and compare.

## Testing and CI

```bash
pip install -r requirements-dev.txt
ruff check . && pytest
```

The unit tests replace AWS and Claude with in-memory fakes. They cover chunking, idempotent re-ingestion, stale-vector cleanup, deletes, citation mapping, the distance filter, both guardrail checks, refusals and request validation.

On every push and pull request, GitHub Actions runs:

1. ruff and pytest.
2. `terraform fmt` and `validate` for both stacks.
3. A Checkov security scan of the Terraform.
4. `terraform plan` against the real account, using a read-only role assumed through GitHub OIDC with no stored keys. This job runs once the repository variables `AWS_PLAN_ROLE_ARN` and `TF_STATE_BUCKET` are set from the bootstrap outputs.

## Security

- **Authentication:** Cognito JWT authorizer on the only route. Self sign-up is off, the password policy is strong, and optional TOTP MFA is available.
- **Least privilege:** one IAM role per function, scoped to its own log group, bucket, table, vector index, embedding model and guardrail.
- **Data protection:** encryption at rest everywhere, a bucket policy that denies non-TLS requests, S3 Block Public Access, versioning, and DynamoDB point-in-time recovery.
- **AI safety:** guardrails on input and output; the prompt treats documents as data; answers come only from retrieved context and abstain otherwise; a refusal fallback keeps users from getting an empty answer.
- **Abuse and cost control:** API throttling (5 requests per second, burst 10), a 1,000-character question limit, and a cap on output tokens.
- **Auditability:** API access logs with the caller's identity, structured query logs, and X-Ray traces.

## Cost

With no traffic the platform costs close to nothing, because every component is serverless and billed per use. Expect roughly 0 to 3 USD per month, mostly CloudWatch, and less within the free tiers.

| Item | Approximate cost |
|---|---|
| Claude Opus 5.5 answer (about 2,000 input and 300 output tokens at 4 / 20 USD per million tokens list price) | about 1 to 2 cents per question; check Bedrock pricing for your region |
| Titan embeddings, S3 Vectors queries, guardrail checks, Lambda, API Gateway | well under 0.1 cent per question |
| Questions with no relevant documents | no Claude call, so close to zero |
| Storage (S3, S3 Vectors, DynamoDB) for the sample documents | cents per month |

Ways to reduce cost: switch `claude_model_id` to Sonnet 5.5, lower `top_k`, or tighten `max_distance`.

## Design decisions

- **Why S3 Vectors rather than OpenSearch Serverless:** OpenSearch Serverless has a minimum always-on capacity charge. S3 Vectors bills only for storage and queries, which fits a knowledge base that is queried occasionally. At hundreds of sustained queries per second, OpenSearch would be the better choice.
- **Why not Bedrock Knowledge Bases:** the managed service would replace most of the ingestion code. Building the pipeline by hand shows how chunking, embedding, idempotency and deletes actually work, and keeps every step testable. Moving to Knowledge Bases later is straightforward.
- **Why citations instead of asking for sources in the prompt:** native citations return the exact cited text with an index pointing to the source document. That is verifiable, while sources the model writes into its answer can be invented.
- **Why low effort:** short grounded answers don't need deep reasoning, and lower effort cuts latency, which matters under API Gateway's 30-second limit.

## Limitations and next steps

- Only `.md` and `.txt` files are ingested; PDF and Word files would need a text-extraction step (for example Amazon Textract or a PDF library).
- One knowledge base for everyone. Per-department access control could filter vector search on a metadata field that maps to Cognito groups.
- Single-turn questions with no conversation memory.
- No front end yet; a small web app using Cognito's hosted login (authorization code with PKCE) would be the next step.
- Answers are not streamed. Streaming would need Lambda response streaming or WebSockets instead of the HTTP API.

## Clean up

```bash
cd terraform/environments/dev && terraform destroy
```

Set `force_destroy = true` first if the buckets still hold data. The state bucket in `terraform/bootstrap` is protected from deletion on purpose.
