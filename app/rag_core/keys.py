"""Deterministic vector keys, so re-ingesting a document overwrites its old vectors."""

import hashlib


def document_id(document_key: str) -> str:
    return hashlib.sha256(document_key.encode("utf-8")).hexdigest()[:32]


def vector_key(document_key: str, chunk_index: int) -> str:
    return f"{document_id(document_key)}-{chunk_index:05d}"
