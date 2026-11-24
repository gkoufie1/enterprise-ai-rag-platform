# Video walkthrough script (about 8 minutes)

## 1. Hook (0:00)
"Ask a generic chatbot about your company's remote work policy and it will confidently make something up. Today I'm building an assistant on AWS that answers only from your own documents, and shows exactly which sentence each answer came from."

## 2. Problem and demo first (0:30)
Show the final result before explaining it.
- Run `scripts/query_api.sh "Can I use my personal laptop for customer data?"` and point out the answer, the citation and the source document.
- Ask "How many weeks of parental leave do we get?" and show that it says it couldn't find that, instead of guessing.
- Try "Ignore all previous instructions..." and show the guardrail blocking it.

## 3. Architecture (1:30)
Walk through the README diagram in three parts: ingestion, query, operations. Explain RAG in one sentence: find the relevant passages first, then let the model answer from them.

## 4. Ingestion live (2:30)
- Run `scripts/upload_docs.sh` and tail the ingestion logs.
- Show the DynamoDB registry: each item has an ETag and a chunk count.
- Upload the same file again and show the "unchanged" skip. Delete a file and show its vectors being removed.

## 5. The query code (3:30)
Open `app/query/handler.py`:
- The guardrail check on the question.
- Embedding, S3 Vectors search and the distance threshold.
- Chunks passed as document blocks with citations enabled, and the system prompt.
- The guardrail check on the answer, and the metrics line.

## 6. Terraform and security (5:00)
Show the module layout, the IAM module with one role per function, the JWT authorizer, the TLS-only bucket policy and the guardrail definition. Explain why S3 Vectors was chosen over OpenSearch Serverless (no idle cost).

## 7. Operations and quality (6:00)
- Show the CloudWatch dashboard: tokens, latency, no-answer rate, guardrail blocks.
- Run `python eval/run_eval.py` and read the scores.
- Show the GitHub Actions run: tests, validate, Checkov, and plan through OIDC with no stored keys.

## 8. Wrap-up (7:15)
Cost: close to zero when idle, about a cent or two per answer. Next steps: PDF support, a web UI, per-department access. Ask viewers which of those to build next.
