import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest side of a question photo (QUIZ_FORMAT.md §5.6).
const maxPhotoSide = 1280;

/// Prepares a picked photo for storage and upload.
///
/// Downscales to at most [maxSide] px on its longest side and re-encodes as
/// JPEG, which keeps on-device storage and inline room requests small.
///
/// **Metadata is discarded.** A camera photo carries EXIF, which routinely
/// includes GPS coordinates, the device make and model, and a timestamp. A
/// quiz can be published for everyone to see, so that metadata would be
/// published with it — a photo taken at home would tell every player where the
/// author lives. Re-encoding alone does not drop it: the `image` package copies
/// EXIF from the decoded image to the encoded one, so it has to be cleared
/// deliberately.
///
/// Orientation is the one tag that must be *honoured* rather than merely
/// dropped, since phone cameras record a rotation flag instead of rotating the
/// pixels. `decodeImage` already applies it and clears the tag (see
/// `getImageFromJpeg`), so by the time we clear the rest the pixels are
/// upright — `photo_resize_test.dart` pins that behaviour, because it is the
/// package's promise rather than ours.
///
/// Bytes that can't be decoded are returned unchanged; the server validates the
/// real type and structure ([`Fazoura.Uploads.Header`]).
Uint8List preparePhoto(Uint8List bytes, {int maxSide = maxPhotoSide}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    // Some decoders throw on truncated or unknown data instead of returning null.
    decoded = null;
  }
  if (decoded == null) return bytes;

  var image = decoded;
  if (math.max(image.width, image.height) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }

  // Every remaining tag is metadata we have no reason to publish.
  image.exif = img.ExifData();

  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}
