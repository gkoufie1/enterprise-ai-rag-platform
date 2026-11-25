import pytest

from conftest import load_handler


@pytest.fixture
def ingestion(fakes, monkeypatch):
    module = load_handler("ingestion")
    module._clients.update(fakes)
    monkeypatch.setattr(module, "CHUNK_WORDS", 10)
    monkeypatch.setattr(module, "CHUNK_OVERLAP_WORDS", 2)
    return module


def s3_event(key, event_name="ObjectCreated:Put"):
    return {"Records": [{"eventName": event_name, "s3": {"bucket": {"name": "docs"}, "object": {"key": key}}}]}


def words(n):
    return " ".join(f"w{i}" for i in range(n))


def test_s3_event_indexes_chunks_with_metadata(ingestion, fakes):
    fakes["s3"].put("policies/remote work.md", words(25))
    result = ingestion.lambda_handler(s3_event("policies/remote+work.md"), None)

    assert result["results"] == [{"key": "policies/remote work.md", "status": "indexed", "chunks": 3}]
    stored = list(fakes["s3vectors"].store.values())
    assert len(stored) == 3
    assert {v["metadata"]["document_key"] for v in stored} == {"policies/remote work.md"}
    assert fakes["table"].items["policies/remote work.md"]["chunk_count"] == 3


def test_unchanged_document_is_skipped(ingestion, fakes):
    fakes["s3"].put("a.md", words(5))
    ingestion.lambda_handler(s3_event("a.md"), None)
    calls = fakes["s3vectors"].put_calls

    result = ingestion.lambda_handler(s3_event("a.md"), None)
    assert result["results"][0]["status"] == "unchanged"
    assert fakes["s3vectors"].put_calls == calls


def test_shrinking_document_removes_stale_vectors(ingestion, fakes):
    fakes["s3"].put("a.md", words(25), etag="v1")
    ingestion.lambda_handler(s3_event("a.md"), None)
    fakes["s3"].put("a.md", words(5), etag="v2")
    ingestion.lambda_handler(s3_event("a.md"), None)

    assert len(fakes["s3vectors"].store) == 1
    assert fakes["table"].items["a.md"]["chunk_count"] == 1


def test_object_removed_deletes_vectors_and_registry(ingestion, fakes):
    fakes["s3"].put("a.md", words(25))
    ingestion.lambda_handler(s3_event("a.md"), None)
    result = ingestion.lambda_handler(s3_event("a.md", "ObjectRemoved:Delete"), None)

    assert result["results"][0]["status"] == "deleted"
    assert fakes["s3vectors"].store == {}
    assert "a.md" not in fakes["table"].items


def test_unsupported_file_type_is_skipped(ingestion, fakes):
    result = ingestion.lambda_handler(s3_event("scan.pdf"), None)
    assert result["results"][0]["status"] == "skipped_unsupported_type"


def test_manual_invocation_requires_key(ingestion):
    with pytest.raises(ValueError):
        ingestion.lambda_handler({}, None)


def test_changed_index_config_reindexes_unchanged_files(ingestion, fakes, monkeypatch):
    fakes["s3"].put("a.md", words(5))
    ingestion.lambda_handler(s3_event("a.md"), None)
    monkeypatch.setattr(ingestion, "INDEX_CONFIG", "new-chunker")
    assert ingestion.lambda_handler(s3_event("a.md"), None)["results"][0]["status"] == "indexed"


def test_manual_force_reindexes(ingestion, fakes):
    fakes["s3"].put("a.md", words(5))
    ingestion.lambda_handler(s3_event("a.md"), None)
    result = ingestion.lambda_handler({"bucket": "docs", "key": "a.md", "force": True}, None)
    assert result["results"][0]["status"] == "indexed"
