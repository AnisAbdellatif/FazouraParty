#!/usr/bin/env python3
"""Tests for fazoura_pack.py.

    python3 -m unittest discover tools

What matters here is that a package this builds is one the server will take, so the
assertions are about the shape `Fazoura.Quizzes.Archive` reads back and the checks
`Fazoura.Uploads` makes — the things a folder can get wrong before anyone tries to
upload it.
"""

from __future__ import annotations

import base64
import contextlib
import io
import json
import tempfile
import unittest
import zipfile
import zlib
from pathlib import Path

import fazoura_pack


def png(width: int = 1, height: int = 1) -> bytes:
    """A real 1x1 PNG. The server validates structurally, not by magic bytes alone."""

    def chunk(kind: bytes, data: bytes) -> bytes:
        payload = kind + data
        return (
            len(data).to_bytes(4, "big")
            + payload
            + (zlib.crc32(payload) & 0xFFFFFFFF).to_bytes(4, "big")
        )

    header = width.to_bytes(4, "big") + height.to_bytes(4, "big") + bytes([8, 0, 0, 0, 0])
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(height * (width + 1))))
        + chunk(b"IEND", b"")
    )


def quiz(**overrides) -> dict:
    document = {
        "format_version": 1,
        "version": "1.0",
        "title": "Film Night",
        "tags": ["movies"],
        "questions": [
            {
                "type": "text",
                "prompt": "Which film opens on a red door?",
                "accepted_answers": ["The Matrix"],
                "difficulty": "medium",
            }
        ],
    }
    document.update(overrides)
    return document


def photo_question(image: dict) -> dict:
    return {
        "type": "text_photo",
        "prompt": "Which film?",
        "accepted_answers": ["The Matrix"],
        "image": image,
    }


class PackTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name) / "film-night"
        (self.folder / "media").mkdir(parents=True)

    def write_quiz(self, document: dict, name: str = "film-night.json") -> Path:
        path = self.folder / name
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def write_photo(self, name: str, data: bytes = None) -> None:
        (self.folder / "media" / name).write_bytes(png() if data is None else data)

    def pack(self, out: str = "out.fazoura") -> Path:
        target = Path(self.tmp.name) / out
        with contextlib.redirect_stdout(io.StringIO()):
            status = fazoura_pack.main([str(self.folder), "--out", str(target)])
        self.assertEqual(status, 0, "packing should have succeeded")
        return target

    def read(self, target: Path) -> tuple[dict, dict]:
        with zipfile.ZipFile(target) as package:
            names = package.namelist()
            manifest = json.loads(package.read("manifest.json"))
            media = {name: package.read(name) for name in names if name.startswith("media/")}
        return manifest, media

    def fails_with(self, expected: str) -> None:
        with self.assertRaises(fazoura_pack.PackError) as caught:
            fazoura_pack.build(self.folder, fazoura_pack.find_document(self.folder, None))
        self.assertIn(expected, str(caught.exception))

    ## The happy path

    def test_a_quiz_with_no_photos_is_just_a_manifest(self):
        self.write_quiz(quiz())

        manifest, media = self.read(self.pack())

        # The document sits under `quiz`, which is where the server and the app look.
        self.assertEqual(manifest["quiz"]["title"], "Film Night")
        self.assertEqual(media, {})

    def test_a_photo_beside_the_document_travels_with_it(self):
        self.write_photo("matrix.png")
        self.write_quiz(
            quiz(
                questions=[
                    photo_question({"path": "media/matrix.png", "alt": "A red door"})
                ]
            )
        )

        manifest, media = self.read(self.pack())
        image = manifest["quiz"]["questions"][0]["image"]

        self.assertEqual(image["alt"], "A red door")
        self.assertIn(image["path"], media)
        self.assertEqual(media[image["path"]], png())

    def test_a_photo_can_be_inline_base64_instead(self):
        # How the app keeps photos on the device, so a folder exported from it works.
        self.write_quiz(
            quiz(
                questions=[
                    photo_question({"data": base64.b64encode(png()).decode(), "alt": "A still"})
                ]
            )
        )

        manifest, media = self.read(self.pack())
        image = manifest["quiz"]["questions"][0]["image"]

        self.assertEqual(list(media.values()), [png()])
        self.assertTrue(image["path"].startswith("media/"))
        self.assertNotIn("data", image)

    def test_the_same_photo_twice_is_stored_once(self):
        self.write_photo("a.png")
        self.write_photo("b.png")
        self.write_quiz(
            quiz(
                questions=[
                    photo_question({"path": "media/a.png"}),
                    photo_question({"path": "media/b.png"}),
                ]
            )
        )

        manifest, media = self.read(self.pack())
        first, second = (q["image"]["path"] for q in manifest["quiz"]["questions"])

        # The name comes from the bytes, so two copies of one picture collapse.
        self.assertEqual(first, second)
        self.assertEqual(len(media), 1)

    def test_a_server_key_or_url_never_travels(self):
        self.write_photo("matrix.png")
        self.write_quiz(
            quiz(
                questions=[
                    photo_question(
                        {
                            "path": "media/matrix.png",
                            "key": "5b0e4f1c9a2d7e3f.jpg",
                            "url": "https://example.test/uploads/5b0e4f1c9a2d7e3f.jpg",
                        }
                    )
                ]
            )
        )

        manifest, _media = self.read(self.pack())
        image = manifest["quiz"]["questions"][0]["image"]

        # Both mean something only on the server that issued them.
        self.assertEqual(set(image), {"path"})

    def test_packing_the_same_folder_twice_gives_the_same_bytes(self):
        self.write_photo("matrix.png")
        self.write_quiz(quiz(questions=[photo_question({"path": "media/matrix.png"})]))

        self.assertEqual(
            self.pack("first.fazoura").read_bytes(), self.pack("second.fazoura").read_bytes()
        )

    ## What a folder can get wrong

    def test_a_folder_with_several_documents_asks_which(self):
        self.write_quiz(quiz())
        self.write_quiz(quiz(), name="other.json")

        with self.assertRaises(fazoura_pack.PackError) as caught:
            fazoura_pack.find_document(self.folder, None)
        self.assertIn("--quiz", str(caught.exception))

    def test_a_folder_with_no_document_says_so(self):
        with self.assertRaises(fazoura_pack.PackError) as caught:
            fazoura_pack.find_document(self.folder, None)
        self.assertIn("no .json quiz document", str(caught.exception))

    def test_a_missing_photo(self):
        self.write_quiz(quiz(questions=[photo_question({"path": "media/gone.png"})]))
        self.fails_with("media/gone.png")

    def test_a_photo_outside_the_folder(self):
        self.write_quiz(quiz(questions=[photo_question({"path": "../../../etc/passwd"})]))
        self.fails_with("outside")

    def test_a_photo_that_is_not_an_image_the_server_takes(self):
        self.write_photo("matrix.png", b"GIF89a not one of ours")
        self.write_quiz(quiz(questions=[photo_question({"path": "media/matrix.png"})]))
        self.fails_with("not a JPEG, PNG or WebP")

    def test_a_photo_over_the_two_megabyte_limit(self):
        self.write_photo("huge.png", png() + b"\x00" * (2 * 1024 * 1024))
        self.write_quiz(quiz(questions=[photo_question({"path": "media/huge.png"})]))
        self.fails_with("over the 2 MB limit")

    def test_a_photo_question_with_no_image_at_all(self):
        self.write_quiz(
            quiz(
                questions=[
                    {
                        "type": "text_photo",
                        "prompt": "Which film?",
                        "accepted_answers": ["The Matrix"],
                    }
                ]
            )
        )
        self.fails_with("needs an image")

    def test_the_document_checks_the_server_would_make_anyway(self):
        for document, expected in [
            (quiz(format_version=2), "format_version"),
            (quiz(title="  "), "needs a title"),
            (quiz(tags=[]), "1 to 10 tags"),
            (quiz(questions=[]), "at least one question"),
            (quiz(questions=[{"type": "audio", "prompt": "?", "accepted_answers": ["a"]}]), "type"),
            (quiz(questions=[{"type": "text", "prompt": " ", "accepted_answers": ["a"]}]), "prompt"),
            (quiz(questions=[{"type": "text", "prompt": "?", "accepted_answers": [" "]}]), "answers"),
        ]:
            with self.subTest(expected=expected):
                self.write_quiz(document)
                self.fails_with(expected)

    def test_a_document_that_is_not_json(self):
        (self.folder / "film-night.json").write_text("{not json", encoding="utf-8")
        with self.assertRaises(fazoura_pack.PackError) as caught:
            fazoura_pack.read_document(self.folder / "film-night.json")
        self.assertIn("not valid JSON", str(caught.exception))

    def test_a_folder_that_is_not_there(self):
        with contextlib.redirect_stderr(io.StringIO()) as complaint:
            self.assertEqual(fazoura_pack.main([str(self.folder / "nope")]), 1)
        self.assertIn("is not a folder", complaint.getvalue())


if __name__ == "__main__":
    unittest.main()
