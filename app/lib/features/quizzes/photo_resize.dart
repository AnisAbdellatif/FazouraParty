import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest side of a question photo (QUIZ_FORMAT.md §5.6).
const maxPhotoSide = 1280;

/// Downscales a picked photo to at most [maxSide] px on its longest side and
/// re-encodes it as JPEG, which keeps on-device storage and inline room
/// requests small. Bytes that can't be decoded are returned unchanged (the
/// server checks the real type).
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
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}
