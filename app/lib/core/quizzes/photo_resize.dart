import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest side of a question photo (QUIZ_FORMAT.md §5.7).
///
/// A phone shows a question photo at most about 1080 px across, and every
/// player in the room downloads it the moment the question starts, so pixels
/// beyond this are paid for by everyone and seen by nobody.
const maxPhotoSide = 1280;

/// Prepares a photo for a quiz: the app's editor runs it on every photo picked,
/// and `fazoura quiz pack` on every photo it packs, so a quiz is the same size
/// however it was made.
///
/// Downscales to at most [maxSide] px on its longest side and re-encodes it:
/// as PNG when it has transparent pixels — a logo on a clear background, which
/// JPEG would paint black — and otherwise as whichever of JPEG and, for a
/// picture that came as a PNG, PNG is smaller. A PNG already small enough
/// keeps its own pixels with only its metadata taken out, when that is smaller
/// than encoding it again: logos usually come out of a better PNG optimiser
/// than this one.
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

  // A palette image is expanded first, so resizing blends colours rather than
  // palette indices.
  final fits = math.max(decoded.width, decoded.height) <= maxSide;
  var image = decoded.hasPalette ? decoded.convert(numChannels: 4) : decoded;
  if (!fits) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxSide,
            interpolation: img.Interpolation.average,
          );
  }

  // Every remaining tag is metadata we have no reason to publish.
  image.exif = img.ExifData();
  image.textData = null;

  // Whichever is smallest of what may be sent: a clear pixel rules JPEG out,
  // and a picture that came as a PNG — a logo, a diagram, flat colour — is
  // often smaller as one.
  final sourcePng = stripPngMetadata(bytes) != null;
  final transparent = _transparent(image);
  final candidates = [
    if (!transparent) Uint8List.fromList(img.encodeJpg(image, quality: 80)),
    if (transparent || sourcePng)
      Uint8List.fromList(img.encodePng(image, level: 9)),
    if (fits && sourcePng) stripPngMetadata(bytes)!,
  ];
  return candidates.reduce((a, b) => b.length < a.length ? b : a);
}

/// Chunks that say something about the picture's author or history rather
/// than its pixels: text (`tEXt`, `zTXt`, `iTXt` — often a software name, a
/// comment, an author), `eXIf` (camera EXIF, GPS included) and `tIME`.
const _metadataChunks = {'tEXt', 'zTXt', 'iTXt', 'eXIf', 'tIME'};

/// [bytes] with every metadata chunk removed, or null if they are not a
/// well-formed PNG. Everything that affects how it is drawn — transparency,
/// colour profile, gamma, animation — is kept, byte for byte.
Uint8List? stripPngMetadata(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 8) return null;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != signature[i]) return null;
  }

  final out = BytesBuilder(copy: false)..add(bytes.sublist(0, 8));
  final view = ByteData.sublistView(bytes);
  var at = 8;
  while (at + 12 <= bytes.length) {
    final length = view.getUint32(at);
    final end = at + 12 + length;
    if (end > bytes.length) return null;
    final type = String.fromCharCodes(bytes.sublist(at + 4, at + 8));
    if (!_metadataChunks.contains(type)) out.add(bytes.sublist(at, end));
    at = end;
    if (type == 'IEND') return out.takeBytes();
  }
  return null;
}

/// Whether any pixel is less than fully opaque. An alpha channel alone is not
/// enough: plenty of photos carry one that is opaque everywhere, and those are
/// far smaller as JPEG.
bool _transparent(img.Image image) {
  if (!image.hasAlpha) return false;
  final opaque = image.maxChannelValue;
  for (final pixel in image) {
    if (pixel.a < opaque) return true;
  }
  return false;
}
