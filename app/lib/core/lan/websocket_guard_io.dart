/// The LAN host's WebSocket upgrade, done here rather than by
/// `WebSocketTransformer.upgrade` so the bytes can be watched as they arrive.
///
/// `dart:io` hands a WebSocket message over only once the whole of it has been
/// received, has no size limit to set, and negotiates deflate by default. So
/// anybody on the Wi-Fi, without a room code, could send one frame that
/// inflated — or simply was — gigabytes, and the phone hosting the party ran
/// out of memory before any check in the host could see it. Here the frame
/// headers are read off the raw socket as they come: a frame or message that
/// declares more than the limit closes the connection before its payload is
/// buffered, and no compression is offered, so what arrives is what was sent.
///
/// `dart:io` only; imported by `lan_host_io.dart` alone.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 6455 §1.3.
const _acceptGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// Answers [request]'s upgrade and returns the socket, or null having refused
/// it. Frames or messages that declare more than [maxMessageBytes] end the
/// connection as their header arrives.
///
/// Requests carrying an `Origin` are refused: every client of a LAN host is the
/// app or the CLI, and neither sends one, while a browser always does — so this
/// is what keeps a web page a guest happens to open from reaching the phone.
Future<WebSocket?> upgradeGuarded(
  HttpRequest request, {
  required int maxMessageBytes,
}) async {
  final headers = request.headers;
  final key = headers.value('sec-websocket-key');
  final upgrade = headers.value(HttpHeaders.upgradeHeader)?.toLowerCase();
  final connection = headers[HttpHeaders.connectionHeader] ?? const [];

  final valid =
      request.method == 'GET' &&
      key != null &&
      key.isNotEmpty &&
      upgrade == 'websocket' &&
      connection.any((value) => value.toLowerCase().contains('upgrade')) &&
      headers.value('sec-websocket-version') == '13';

  if (!valid || headers.value('origin') != null) {
    request.response.statusCode = valid
        ? HttpStatus.forbidden
        : HttpStatus.badRequest;
    try {
      await request.response.close();
    } on Object {
      // Gone already; nothing to answer.
    }
    return null;
  }

  final accept = base64.encode(
    sha1.convert(utf8.encode('$key$_acceptGuid')).bytes,
  );
  final response = request.response
    ..statusCode = HttpStatus.switchingProtocols
    ..contentLength = 0;
  response.headers
    ..set(HttpHeaders.connectionHeader, 'Upgrade')
    ..set(HttpHeaders.upgradeHeader, 'websocket')
    ..set('sec-websocket-accept', accept);

  final socket = await response.detachSocket();
  return WebSocket.fromUpgradedSocket(
    GuardedSocket(socket, maxMessageBytes: maxMessageBytes),
    serverSide: true,
  );
}

/// [socket] with its incoming bytes read as WebSocket frames on the way past.
///
/// Nothing is changed: every byte is forwarded as it came. The only thing it
/// does is stop — destroying the socket — the moment a frame header announces
/// a frame, or a fragmented message, bigger than [maxMessageBytes].
class GuardedSocket extends StreamView<Uint8List> implements Socket {
  factory GuardedSocket(Socket socket, {required int maxMessageBytes}) {
    final guard = _FrameGuard(maxMessageBytes);
    final incoming = socket.transform(
      StreamTransformer<Uint8List, Uint8List>.fromHandlers(
        handleData: (chunk, sink) {
          if (guard.accepts(chunk)) {
            sink.add(chunk);
          } else {
            // Destroying ends both directions, and the stream with them.
            socket.destroy();
            sink.close();
          }
        },
      ),
    );
    return GuardedSocket._(socket, incoming);
  }

  GuardedSocket._(this._socket, Stream<Uint8List> incoming) : super(incoming);

  final Socket _socket;

  // --- Socket, forwarded ---------------------------------------------------

  @override
  InternetAddress get address => _socket.address;
  @override
  int get port => _socket.port;
  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
  @override
  int get remotePort => _socket.remotePort;
  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);
  @override
  void destroy() => _socket.destroy();

  // --- IOSink, forwarded ---------------------------------------------------

  @override
  Encoding get encoding => _socket.encoding;
  @override
  set encoding(Encoding value) => _socket.encoding = value;
  @override
  void add(List<int> data) => _socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);
  @override
  Future<void> close() => _socket.close();
  @override
  Future<void> get done => _socket.done;
  @override
  Future<void> flush() => _socket.flush();
  @override
  void write(Object? object) => _socket.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _socket.writeln(object);
}

/// Reads RFC 6455 frame headers out of a byte stream, chunk by chunk, and
/// says whether what has been announced so far is within the limit.
class _FrameGuard {
  _FrameGuard(this.maxMessageBytes);

  final int maxMessageBytes;

  /// Header bytes of the frame being read, until it is complete.
  final List<int> _header = [];

  /// Payload bytes of the current frame still to pass by.
  int _remaining = 0;

  /// Bytes of the data message being assembled across its fragments.
  int _message = 0;

  bool _refused = false;

  bool accepts(Uint8List chunk) {
    if (_refused) return false;
    var i = 0;
    while (i < chunk.length) {
      if (_remaining > 0) {
        final take = _remaining < chunk.length - i
            ? _remaining
            : chunk.length - i;
        _remaining -= take;
        i += take;
        continue;
      }
      _header.add(chunk[i]);
      i += 1;
      final length = _frameLength();
      if (length == null) continue; // header not complete yet
      _header.clear();
      if (length < 0 || !_admit(length)) {
        _refused = true;
        return false;
      }
      _remaining = length;
    }
    return true;
  }

  int _opcode = 0;

  /// The payload length once [_header] holds a whole header, null before
  /// then, and -1 for a length no frame from a client could honestly have.
  int? _frameLength() {
    if (_header.length < 2) return null;
    _opcode = _header[0] & 0x0F;
    final masked = (_header[1] & 0x80) != 0;
    final short = _header[1] & 0x7F;
    final extended = switch (short) {
      126 => 2,
      127 => 8,
      _ => 0,
    };
    final size = 2 + extended + (masked ? 4 : 0);
    if (_header.length < size) return null;

    if (extended == 0) return short;
    var length = 0;
    for (var b = 2; b < 2 + extended; b++) {
      // Anything past 2^53 is a lie a Dart int would not even hold.
      if (length > 0x1FFFFFFFFFFF) return -1;
      length = (length << 8) | _header[b];
    }
    return length;
  }

  /// Control frames are small by rule; data frames count towards their
  /// message, which a new text or binary frame starts afresh.
  bool _admit(int length) {
    if (_opcode >= 0x8) return length <= 125;
    if (_opcode != 0x0) _message = 0;
    _message += length;
    return length <= maxMessageBytes && _message <= maxMessageBytes;
  }
}
