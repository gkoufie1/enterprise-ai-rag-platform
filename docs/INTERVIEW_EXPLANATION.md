# Explaining this project in an interview

## 30-second version

I built a serverless RAG platform on AWS that answers employee questions from internal documents, with citations. Uploading a document to S3 triggers a Lambda that chunks it, embeds it with Titan V2 and stores the vectors in S3 Vectors. A question goes through API Gateway with a Cognito JWT authorizer to a Lambda that checks it with Bedrock Guardrails, retrieves the closest chunks, and asks Claude on Bedrock to answer only from those chunks with native citations. Everything is in Terraform with least-privilege IAM, alarms and a dashboard, and CI runs tests, a security scan and a Terraform plan through GitHub OIDC.

## Two-minute walkthrough

1. **Problem:** knowledge is scattered, people waste time searching, and a generic chatbot invents answers.
2. **Ingestion:** S3 events trigger ingestion. A DynamoDB registry of ETags and chunk counts makes it idempotent and lets me delete stale vectors when a document shrinks or is removed. Failures are retried twice and then sent to a DLQ with an alarm.
3. **Retrieval:** Titan V2 embeddings and S3 Vectors with cosine distance. I drop chunks above a distance threshold, and if nothing is left I return "not found" without calling the model. That prevents made-up answers and saves money.
4. **Generation:** each chunk is passed to Claude as its own document with citations enabled, so every citation maps back to an exact document and chunk. The system prompt restricts answers to the documents and treats their text as data, which defends against prompt injection hidden in a document.
5. **Safety and security:** guardrails on input and output, a Cognito JWT on the API, throttling, one IAM role per function, TLS-only encrypted buckets.
6. **Operations:** custom metrics in Embedded Metric Format (tokens, latency, no-answer rate, guardrail blocks), alarms to SNS, X-Ray tracing.
7. **Quality:** unit tests with fake AWS clients, plus an evaluation set that measures retrieval hit rate, citation accuracy, abstention and blocked attacks.

## Questions you are likely to get

**Why S3 Vectors and not OpenSearch?**
OpenSearch Serverless has a minimum always-on capacity cost, and this workload is a lightly used internal tool. S3 Vectors bills only for storage and queries. For sustained high query rates or hybrid keyword search, I would move to OpenSearch.

**Why not Bedrock Knowledge Bases?**
It would replace most of my ingestion code, and for a team shipping fast it is a good choice. I built the pipeline myself to control chunking, idempotency and deletes and to test each step. The vectors and metadata layout would move over to Knowledge Bases easily.

**How do you stop hallucinations?**
I use four layers:
- A distance threshold, so the model only sees relevant chunks.
- An abstain path that skips the model when nothing relevant is found.
- A prompt that restricts answers to the provided documents.
- Native citations, so every claim can be checked against the source text.

The evaluation set tests both answering and abstaining.

**How do you handle prompt injection?**
At two points. Bedrock Guardrails' prompt-attack filter checks the user's question. Documents are passed as document blocks, and the system prompt says their content is reference material, not instructions.

**What happens when a document changes?**
The S3 event re-triggers ingestion. The new ETag differs from the registry, so the document is re-embedded. Deterministic vector keys overwrite the old chunks, and extra chunks from the longer old version are deleted.

**How would you scale this or make it multi-tenant?**
- **Access control:** add a department metadata field and filter vector search on it using the user's Cognito groups.
- **Ingestion throughput:** batch embeddings and use SQS between S3 and Lambda to control concurrency.
- **Answer latency:** add response streaming for long answers.

**What does it cost?**
Close to zero when idle because everything is serverless. A question costs about a cent or two with Opus 5.5, and much less with a smaller model. Questions with no relevant documents never call the model.

**What would you do next?**
PDF ingestion with Textract, a small web front end with Cognito's hosted login, per-department access control, conversation memory, and running the evaluation in CI against a staging environment.
