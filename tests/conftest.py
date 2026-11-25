import importlib.util
import io
import json
import sys
from pathlib import Path

import pytest

APP = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP))  # makes `rag_core` importable, as it is inside the Lambda package


def load_handler(function: str):
    spec = importlib.util.spec_from_file_location(f"{function}_handler", APP / function / "handler.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeBedrockRuntime:
    """Embeds text as a tiny deterministic vector and records guardrail calls."""

    def __init__(self, guardrail_block: set[str] | None = None):
        self.guardrail_block = guardrail_block or set()
        self.embedded: list[str] = []

    def invoke_model(self, modelId, body, **_):
        text = json.loads(body)["inputText"]
        self.embedded.append(text)
        return {"body": io.BytesIO(json.dumps({"embedding": [float(len(text)), 1.0]}).encode())}

    def apply_guardrail(self, source, content, **_):
        if source in self.guardrail_block:
            return {"action": "GUARDRAIL_INTERVENED", "outputs": [{"text": f"blocked {source.lower()}"}]}
        return {"action": "NONE", "outputs": []}


class FakeS3Vectors:
    def __init__(self, query_results=None):
        self.store: dict[str, dict] = {}
        self.query_results = query_results or []
        self.put_calls = 0

    def put_vectors(self, vectorBucketName, indexName, vectors):
        self.put_calls += 1
        for v in vectors:
            self.store[v["key"]] = v

    def delete_vectors(self, vectorBucketName, indexName, keys):
        for k in keys:
            self.store.pop(k, None)

    def query_vectors(self, **_):
        return {"vectors": self.query_results}


class FakeTable:
    def __init__(self):
        self.items: dict[str, dict] = {}

    def get_item(self, Key):
        item = self.items.get(Key["document_key"])
        return {"Item": dict(item)} if item else {}

    def put_item(self, Item):
        self.items[Item["document_key"]] = dict(Item)

    def delete_item(self, Key):
        self.items.pop(Key["document_key"], None)


class FakeUsageTable:
    """Mimics the conditional ADD the quota check uses."""

    def __init__(self):
        self.counts: dict[str, int] = {}

    def update_item(self, Key, ExpressionAttributeValues, **_):
        from botocore.exceptions import ClientError

        key = Key["usage_key"]
        current = self.counts.get(key)
        if current is not None and current >= ExpressionAttributeValues[":limit"]:
            raise ClientError({"Error": {"Code": "ConditionalCheckFailedException"}}, "UpdateItem")
        self.counts[key] = (current or 0) + 1
        return {"Attributes": {"question_count": self.counts[key]}}


class FakeS3:
    def __init__(self):
        self.objects: dict[str, tuple[bytes, str]] = {}

    def put(self, key, text, etag="etag-1"):
        self.objects[key] = (text.encode(), etag)

    def get_object(self, Bucket, Key):
        data, etag = self.objects[Key]
        return {"Body": io.BytesIO(data), "ETag": f'"{etag}"', "ContentLength": len(data)}


@pytest.fixture
def fakes():
    return {
        "bedrock-runtime": FakeBedrockRuntime(),
        "s3vectors": FakeS3Vectors(),
        "s3": FakeS3(),
        "table": FakeTable(),
    }
