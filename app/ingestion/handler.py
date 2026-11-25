"""Ingestion Lambda: S3 document -> chunks -> Titan embeddings -> S3 Vectors.

Triggered by S3 ObjectCreated / ObjectRemoved events. Can also be invoked directly with
{"key": "...", "bucket": "...(optional)", "action": "ingest" | "delete", "force": true|false}
to re-ingest by hand.

A DynamoDB registry records each document's ETag and chunk count, which makes ingestion
idempotent (unchanged files are skipped) and lets us delete stale vectors when a document
shrinks or is removed.
"""

import logging
import os
import urllib.parse
from datetime import UTC, datetime

import boto3
from botocore.config import Config

from rag_core.chunking import CHUNKER_VERSION, chunk_document
from rag_core.embeddings import embed
from rag_core.keys import vector_key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SUPPORTED_SUFFIXES = (".txt", ".md")
MAX_DOCUMENT_BYTES = 5 * 1024 * 1024
PUT_BATCH_SIZE = 100  # S3 Vectors allows 500 per call; 100 keeps request bodies small
DELETE_BATCH_SIZE = 500

DOCUMENT_BUCKET = os.environ.get("DOCUMENT_BUCKET", "")
DOCUMENTS_TABLE = os.environ.get("DOCUMENTS_TABLE", "")
VECTOR_BUCKET = os.environ.get("VECTOR_BUCKET", "")
VECTOR_INDEX = os.environ.get("VECTOR_INDEX", "")
EMBEDDING_MODEL_ID = os.environ.get("EMBEDDING_MODEL_ID", "amazon.titan-embed-text-v2:0")
EMBEDDING_DIMENSIONS = int(os.environ.get("EMBEDDING_DIMENSIONS", "1024"))
CHUNK_WORDS = int(os.environ.get("CHUNK_WORDS", "150"))
CHUNK_OVERLAP_WORDS = int(os.environ.get("CHUNK_OVERLAP_WORDS", "30"))

# Everything that shapes the vectors. A document is re-indexed when its content (ETag) or any of
# these change, so tuning chunking or switching embedding models re-indexes on the next upload.
INDEX_CONFIG = f"{CHUNKER_VERSION}|{CHUNK_WORDS}/{CHUNK_OVERLAP_WORDS}|{EMBEDDING_MODEL_ID}|{EMBEDDING_DIMENSIONS}"

# Explicit timeouts so a slow dependency fails fast instead of consuming the Lambda timeout.
AWS_CONFIG = Config(connect_timeout=5, read_timeout=20, retries={"max_attempts": 3, "mode": "standard"})

_clients: dict = {}


def _client(name: str):
    if name not in _clients:
        _clients[name] = boto3.client(name, config=AWS_CONFIG)
    return _clients[name]


def _table():
    if "table" not in _clients:
        _clients["table"] = boto3.resource("dynamodb", config=AWS_CONFIG).Table(DOCUMENTS_TABLE)
    return _clients["table"]


def lambda_handler(event, context):
    results = [_run(job) for job in parse_event(event)]
    logger.info("ingestion finished: %s", results)
    return {"results": results}


def parse_event(event: dict) -> list[dict]:
    """Normalize S3 notifications and manual invocations into a list of jobs."""
    if "Records" in event:
        jobs = []
        for record in event["Records"]:
            s3 = record["s3"]
            jobs.append(
                {
                    "bucket": s3["bucket"]["name"],
                    "key": urllib.parse.unquote_plus(s3["object"]["key"]),
                    "action": "delete" if record["eventName"].startswith("ObjectRemoved") else "ingest",
                }
            )
        return jobs

    if not event.get("key"):
        raise ValueError("manual invocation needs a 'key'")
    action = event.get("action", "ingest")
    if action not in ("ingest", "delete"):
        raise ValueError("action must be 'ingest' or 'delete'")
    return [
        {
            "bucket": event.get("bucket", DOCUMENT_BUCKET),
            "key": event["key"],
            "action": action,
            "force": bool(event.get("force", False)),
        }
    ]


def _run(job: dict) -> dict:
    if job["action"] == "delete":
        return delete_document(job["key"])
    return ingest_document(job["bucket"], job["key"], force=job.get("force", False))


def ingest_document(bucket: str, key: str, force: bool = False) -> dict:
    if not key.lower().endswith(SUPPORTED_SUFFIXES):
        logger.info("skipping unsupported file type: %s", key)
        return {"key": key, "status": "skipped_unsupported_type"}

    obj = _client("s3").get_object(Bucket=bucket, Key=key)
    etag = obj["ETag"].strip('"')
    size = obj["ContentLength"]
    if size > MAX_DOCUMENT_BYTES:
        logger.warning("skipping %s: %d bytes exceeds the %d byte limit", key, size, MAX_DOCUMENT_BYTES)
        return {"key": key, "status": "skipped_too_large"}

    existing = _table().get_item(Key={"document_key": key}).get("Item") or {}
    up_to_date = existing.get("etag") == etag and existing.get("index_config") == INDEX_CONFIG
    if up_to_date and existing.get("status") == "INDEXED" and not force:
        return {"key": key, "status": "unchanged"}

    text = obj["Body"].read().decode("utf-8", errors="replace")
    chunks = chunk_document(text, CHUNK_WORDS, CHUNK_OVERLAP_WORDS)

    vectors = [
        {
            "key": vector_key(key, i),
            "data": {"float32": embed(_client("bedrock-runtime"), chunk, EMBEDDING_MODEL_ID, EMBEDDING_DIMENSIONS)},
            "metadata": {"document_key": key, "chunk_index": i, "text": chunk},
        }
        for i, chunk in enumerate(chunks)
    ]
    for start in range(0, len(vectors), PUT_BATCH_SIZE):
        _client("s3vectors").put_vectors(
            vectorBucketName=VECTOR_BUCKET,
            indexName=VECTOR_INDEX,
            vectors=vectors[start : start + PUT_BATCH_SIZE],
        )

    # The document got shorter: remove vectors for chunk indexes that no longer exist.
    previous_count = int(existing.get("chunk_count", 0))
    if previous_count > len(chunks):
        _delete_vectors([vector_key(key, i) for i in range(len(chunks), previous_count)])

    _table().put_item(
        Item={
            "document_key": key,
            "etag": etag,
            "chunk_count": len(chunks),
            "size_bytes": size,
            "status": "INDEXED" if chunks else "EMPTY",
            "embedding_model": EMBEDDING_MODEL_ID,
            "index_config": INDEX_CONFIG,
            "ingested_at": datetime.now(UTC).isoformat(),
        }
    )
    return {"key": key, "status": "indexed", "chunks": len(chunks)}


def delete_document(key: str) -> dict:
    existing = _table().get_item(Key={"document_key": key}).get("Item")
    if not existing:
        return {"key": key, "status": "not_indexed"}
    _delete_vectors([vector_key(key, i) for i in range(int(existing.get("chunk_count", 0)))])
    _table().delete_item(Key={"document_key": key})
    return {"key": key, "status": "deleted"}


def _delete_vectors(keys: list[str]) -> None:
    for start in range(0, len(keys), DELETE_BATCH_SIZE):
        _client("s3vectors").delete_vectors(
            vectorBucketName=VECTOR_BUCKET,
            indexName=VECTOR_INDEX,
            keys=keys[start : start + DELETE_BATCH_SIZE],
        )
