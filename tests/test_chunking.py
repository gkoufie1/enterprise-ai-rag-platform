import pytest

from rag_core.chunking import chunk_document, chunk_text
from rag_core.keys import vector_key


def test_empty_text_gives_no_chunks():
    assert chunk_text("   \n ") == []


def test_short_text_is_one_chunk():
    assert chunk_text("a b c", chunk_words=10, overlap_words=2) == ["a b c"]


def test_chunks_overlap_and_cover_every_word():
    words = [f"w{i}" for i in range(25)]
    chunks = chunk_text(" ".join(words), chunk_words=10, overlap_words=3)
    assert chunks[0].split() == words[0:10]
    assert chunks[1].split() == words[7:17]
    assert chunks[-1].split()[-1] == "w24"
    covered = {w for c in chunks for w in c.split()}
    assert covered == set(words)


def test_no_trailing_chunk_made_only_of_overlap():
    chunks = chunk_text(" ".join(str(i) for i in range(10)), chunk_words=10, overlap_words=3)
    assert len(chunks) == 1


@pytest.mark.parametrize("size,overlap", [(0, 0), (10, 10), (10, -1)])
def test_invalid_settings_rejected(size, overlap):
    with pytest.raises(ValueError):
        chunk_text("a b c", chunk_words=size, overlap_words=overlap)


def test_vector_keys_are_deterministic_and_distinct():
    assert vector_key("docs/a.md", 0) == vector_key("docs/a.md", 0)
    assert vector_key("docs/a.md", 0) != vector_key("docs/a.md", 1)
    assert vector_key("docs/a.md", 0) != vector_key("docs/b.md", 0)


SAMPLE = """# Cloud Security Standard

Owner: Security Engineering.

## Identity and access
All cloud access uses single sign-on with MFA.

## Logging and monitoring
Audit logs are kept for one year.
"""


def test_markdown_is_split_by_section_with_context_labels():
    chunks = chunk_document(SAMPLE, chunk_words=150, overlap_words=30)
    assert chunks == [
        "Cloud Security Standard\nOwner: Security Engineering.",
        "Cloud Security Standard > Identity and access\nAll cloud access uses single sign-on with MFA.",
        "Cloud Security Standard > Logging and monitoring\nAudit logs are kept for one year.",
    ]


def test_long_sections_are_windowed_and_keep_their_label():
    text = "# Guide\n\n## Long part\n" + " ".join(f"w{i}" for i in range(25))
    chunks = chunk_document(text, chunk_words=10, overlap_words=2)
    assert len(chunks) == 3
    assert all(c.startswith("Guide > Long part\n") for c in chunks)


def test_plain_text_without_headings_falls_back_to_windows():
    assert chunk_document("just some plain text", chunk_words=10, overlap_words=2) == ["just some plain text"]
