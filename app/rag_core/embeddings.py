"""Text embeddings with Amazon Titan Text Embeddings V2 on Bedrock."""

import json

# Titan V2 accepts up to 50,000 characters; chunks are far smaller, this only guards odd input.
MAX_EMBED_CHARS = 40_000


def embed(bedrock_runtime, text: str, model_id: str, dimensions: int) -> list[float]:
    """Return a normalized embedding vector for `text`."""
    response = bedrock_runtime.invoke_model(
        modelId=model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({"inputText": text[:MAX_EMBED_CHARS], "dimensions": dimensions, "normalize": True}),
    )
    return json.loads(response["body"].read())["embedding"]
