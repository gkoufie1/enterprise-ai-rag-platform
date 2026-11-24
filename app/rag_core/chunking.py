"""Split documents into overlapping word windows for embedding."""


def chunk_text(text: str, chunk_words: int = 250, overlap_words: int = 40) -> list[str]:
    """Return overlapping chunks of roughly `chunk_words` words.

    Overlap keeps a sentence that straddles a boundary retrievable from either side.
    """
    if chunk_words <= 0:
        raise ValueError("chunk_words must be positive")
    if not 0 <= overlap_words < chunk_words:
        raise ValueError("overlap_words must be >= 0 and smaller than chunk_words")

    words = text.split()
    if not words:
        return []

    step = chunk_words - overlap_words
    chunks = []
    for start in range(0, len(words), step):
        chunks.append(" ".join(words[start : start + chunk_words]))
        if start + chunk_words >= len(words):
            break
    return chunks
