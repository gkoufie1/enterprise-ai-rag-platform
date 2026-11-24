import pytest

from rag_core.chunking import chunk_text
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
