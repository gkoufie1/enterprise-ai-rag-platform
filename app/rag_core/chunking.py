"""Split documents into chunks for embedding.

Markdown documents are split at headings first, so each chunk covers one topic and its
embedding is not diluted by unrelated sections. Each chunk is prefixed with the document
title and section heading, which gives the embedding (and the model) its context.
"""

import re

# Bump when the chunking logic changes: ingestion re-indexes documents chunked by an older version.
CHUNKER_VERSION = "2-sections"

_HEADING = re.compile(r"^(#{1,6})\s+(.*\S)\s*$")


def chunk_text(text: str, chunk_words: int = 250, overlap_words: int = 40) -> list[str]:
    """Return overlapping windows of roughly `chunk_words` words.

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


def chunk_document(text: str, chunk_words: int = 150, overlap_words: int = 30) -> list[str]:
    """Chunk a document section by section (Markdown headings), falling back to word windows.

    Sections shorter than `chunk_words` become one chunk; longer ones are windowed. Every chunk
    starts with "Document title > Section heading" so it stays meaningful on its own.
    """
    title, sections = _split_sections(text)
    chunks = []
    for heading, body in sections:
        label = " > ".join(part for part in (title, heading) if part)
        for window in chunk_text(body, chunk_words, overlap_words):
            chunks.append(f"{label}\n{window}" if label else window)
    return chunks


def _split_sections(text: str) -> tuple[str, list[tuple[str, str]]]:
    """Return (document title, [(section heading, section body), ...])."""
    title = ""
    sections: list[tuple[str, list[str]]] = [("", [])]
    for line in text.splitlines():
        match = _HEADING.match(line)
        if match:
            level, heading = len(match.group(1)), match.group(2)
            if level == 1 and not title:
                title = heading
                continue
            sections.append((heading, []))
        else:
            sections[-1][1].append(line)
    return title, [(heading, "\n".join(lines)) for heading, lines in sections if "".join(lines).strip()]
