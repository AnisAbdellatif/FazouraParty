#!/usr/bin/env python3
"""Build a `.fazoura` package from a folder of quiz JSON and photos.

A `.fazoura` package is one ZIP holding a quiz and the photos its questions use
(protocol/QUIZ_FORMAT.md §5.3b):

    manifest.json        the quiz document, under "quiz"
    media/<hash>.<ext>   one file per photo

It is what `GET /api/quizzes/:id/archive` sends, what the app imports, and what the
admin dashboard accepts. This script builds one from a folder laid out the way
`server/priv/quizzes` is — a quiz document with its photos beside it:

    film-night/
      film-night.json
      media/matrix.jpg
      media/casablanca.png

    $ tools/fazoura_pack.py film-night
    film-night.fazoura · 12 questions · 2 photos · 1.4 MB

Photos are named in the document the same way a preset names them, by a path relative
to the folder:

    "image": { "path": "media/matrix.jpg", "alt": "A man dodging bullets" }

A question may instead carry `"data"` (base64), which is how the app keeps photos on
the device; either is accepted and both come out as files in the package.

Every photo is checked the way the server checks an upload — JPEG, PNG or WebP by
content rather than by filename, and at most 2 MB — so a package this builds is one the
server will take. Inside the package a photo is named by a digest of its own bytes, so
the same picture used twice is stored once, and building the same folder twice produces
the same file.

Python 3.9+, standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path
from typing import Any

# What `Fazoura.Uploads` accepts, checked the same way: by the bytes, not the name.
MAX_PHOTO_BYTES = 2 * 1024 * 1024

# What `Fazoura.Quizzes.Archive` reads back.
MAX_PACKAGE_BYTES = 32 * 1024 * 1024

# Every entry gets this timestamp so that packing a folder twice gives byte-identical
# files. ZIP cannot store a year before 1980.
FIXED_TIMESTAMP = (1980, 1, 1, 0, 0, 0)


class PackError(Exception):
    """Something about the folder that the user has to fix."""


def detect(data: bytes) -> str | None:
    """The file extension for an image the server accepts, or None."""
    if data[:3] == b"\xff\xd8\xff":
        return "jpg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def find_document(folder: Path, given: Path | None) -> Path:
    """The quiz document in `folder`, or the one the caller named."""
    if given is not None:
        if not given.is_file():
            raise PackError(f"{given} is not a file")
        return given

    candidates = sorted(
        path
        for path in folder.glob("*.json")
        if path.name not in ("manifest.json", "package.json")
    )
    if not candidates:
        raise PackError(f"{folder} holds no .json quiz document (use --quiz to name one)")
    if len(candidates) > 1:
        names = ", ".join(path.name for path in candidates)
        raise PackError(f"{folder} holds several documents ({names}) — name one with --quiz")
    return candidates[0]


def read_document(path: Path) -> dict[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise PackError(f"{path} is not valid JSON: {error}") from error
    except OSError as error:
        raise PackError(f"{path}: {error}") from error

    if not isinstance(document, dict):
        raise PackError(f"{path} must hold a quiz document (an object), not a {type(document).__name__}")
    return document


def photo_bytes(folder: Path, image: dict[str, Any], where: str) -> bytes:
    """The photo a question names, by a path beside the document or inline base64."""
    path, data = image.get("path"), image.get("data")

    if isinstance(path, str):
        # Resolved against the folder and checked afterwards, so `..` in the middle of
        # a path cannot climb out of it either.
        resolved = (folder / path).resolve()
        if not resolved.is_relative_to(folder.resolve()):
            raise PackError(f"{where}: {path} is outside {folder}")
        try:
            return resolved.read_bytes()
        except OSError as error:
            raise PackError(f"{where}: {path}: {error}") from error

    if isinstance(data, str):
        import base64
        import binascii

        try:
            return base64.b64decode(data, validate=True)
        except (binascii.Error, ValueError) as error:
            raise PackError(f"{where}: image.data is not valid base64: {error}") from error

    raise PackError(f'{where}: a photo question needs an image with a "path" or "data"')


FORMAT_VERSION = "1.0"


def readable_format(version: Any) -> bool:
    """Whether a document written for `version` can be read as FORMAT_VERSION.

    The major has to match; the minor need not, because a minor only ever adds
    keys an older reader ignores. A plain integer is a document from before the
    format carried a minor at all, and is that major.
    """
    if isinstance(version, bool):
        return False
    if isinstance(version, int):
        version = f"{version}.0"
    if not isinstance(version, str):
        return False
    return version.split(".", 1)[0] == FORMAT_VERSION.split(".", 1)[0]


def check_document(document: dict[str, Any]) -> list[dict[str, Any]]:
    """The checks the server would make anyway, made here where they are readable."""
    if not readable_format(document.get("format_version")):
        raise PackError(
            f'the document needs "format_version": "{FORMAT_VERSION}" '
            "(QUIZ_FORMAT.md §2.1)"
        )

    title = document.get("title")
    if not isinstance(title, str) or not title.strip():
        raise PackError("the document needs a title")

    tags = document.get("tags")
    if not isinstance(tags, list) or not 1 <= len(tags) <= 10:
        raise PackError("the document needs 1 to 10 tags (QUIZ_FORMAT.md §2.3)")

    questions = document.get("questions")
    if not isinstance(questions, list) or not questions:
        raise PackError("the document needs at least one question")

    for index, question in enumerate(questions, start=1):
        if not isinstance(question, dict):
            raise PackError(f"question {index} is not an object")
        if question.get("type") not in ("text", "text_photo"):
            raise PackError(f'question {index}: type must be "text" or "text_photo"')
        if not isinstance(question.get("prompt"), str) or not question["prompt"].strip():
            raise PackError(f"question {index} has no prompt")
        answers = question.get("accepted_answers")
        if not isinstance(answers, list) or not any(
            isinstance(answer, str) and answer.strip() for answer in answers
        ):
            raise PackError(f"question {index} has no accepted answers")

    return questions


def build(folder: Path, document_path: Path) -> tuple[dict[str, Any], dict[str, bytes]]:
    """The manifest document and the photos it names, ready to be written."""
    document = read_document(document_path)
    questions = check_document(document)
    photos: dict[str, bytes] = {}
    packed: list[dict[str, Any]] = []

    for index, question in enumerate(questions, start=1):
        where = f"question {index}"
        image = question.get("image")
        photo = question["type"] == "text_photo"

        if photo and not isinstance(image, dict):
            raise PackError(f"{where}: a text_photo question needs an image")
        if not photo and image:
            raise PackError(f'{where}: only a text_photo question may carry an image')
        if not isinstance(image, dict):
            packed.append(question)
            continue

        data = photo_bytes(folder, image, where)
        extension = detect(data)
        if extension is None:
            raise PackError(f"{where}: the photo is not a JPEG, PNG or WebP")
        if len(data) > MAX_PHOTO_BYTES:
            raise PackError(
                f"{where}: the photo is {len(data) / 1024 / 1024:.1f} MB, over the 2 MB limit"
            )

        # Named by its own bytes, like the server names an upload: the same picture
        # used by two questions is stored once and a rebuild changes nothing.
        path = f"media/{hashlib.sha256(data).hexdigest()[:24]}.{extension}"
        photos[path] = data

        # `key` and `url` mean something only on a server, so they never travel.
        kept = {"path": path}
        if isinstance(image.get("alt"), str):
            kept["alt"] = image["alt"]
        packed.append({**question, "image": kept})

    return {**document, "questions": packed}, photos


def write(target: Path, document: dict[str, Any], photos: dict[str, bytes]) -> int:
    """Writes the package and returns its size in bytes."""
    manifest = json.dumps({"quiz": document}, ensure_ascii=False, indent=2, sort_keys=True)
    entries = [("manifest.json", manifest.encode("utf-8"))]
    entries += sorted(photos.items())

    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as package:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=FIXED_TIMESTAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            package.writestr(info, data)

    size = target.stat().st_size
    if size > MAX_PACKAGE_BYTES:
        target.unlink()
        raise PackError(
            f"the package is {size / 1024 / 1024:.1f} MB, over the "
            f"{MAX_PACKAGE_BYTES // 1024 // 1024} MB the server reads — "
            "use fewer or smaller photos"
        )
    return size


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build a .fazoura package from a folder of quiz JSON and photos.",
        epilog="See protocol/QUIZ_FORMAT.md §5.3b for the format.",
    )
    parser.add_argument("folder", type=Path, help="the folder holding the quiz and its photos")
    parser.add_argument(
        "-q", "--quiz", type=Path, help="the quiz document, when the folder holds more than one"
    )
    parser.add_argument(
        "-o", "--out", type=Path, help="where to write (default: <folder>.fazoura beside it)"
    )
    args = parser.parse_args(argv)

    try:
        folder = args.folder
        if not folder.is_dir():
            raise PackError(f"{folder} is not a folder")

        document_path = find_document(folder, args.quiz)
        document, photos = build(folder, document_path)
        target = args.out or folder.resolve().with_suffix(".fazoura")
        size = write(target, document, photos)
    except PackError as error:
        print(f"{parser.prog}: {error}", file=sys.stderr)
        return 1

    print(
        f"{target} · {count(len(document['questions']), 'question')} · "
        f"{count(len(photos), 'photo')} · {size / 1024:.0f} KB"
    )
    return 0


def count(n: int, thing: str) -> str:
    return f"{n} {thing}" if n == 1 else f"{n} {thing}s"


if __name__ == "__main__":
    sys.exit(main())
