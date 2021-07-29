import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'common.dart';
import 'zip.dart';

const kDefaultCompressionLevel = 6;

class ZipFileWriter {
  final File file;
  final ZipHandle _handle;

  ZipFileWriter(this.file, {int compressionLevel = kDefaultCompressionLevel})
      : _handle = _open(file, compressionLevel);

  void writeFile(String name, File file, {bool compress = true}) =>
      _writeFile(_handle, name, file, compress);

  void writeData(String name, Uint8List data, {bool compress = true}) =>
      _writeData(_handle, name, data, compress);

  void close() => _close(_handle);
}

class ZipFileWriterAsync {
  final File file;
  final _receivePort = ReceivePort();
  final _sendPort = new Completer<SendPort>();
  final _requests = <int, Completer>{};
  var _requestId = 0;

  ZipFileWriterAsync(this.file, {int compressionLevel = kDefaultCompressionLevel}) {
    _listenForWorkerMessages();
    final params = _ZipWorkerParams(
      file: file,
      compressionLevel: compressionLevel,
      sendPort: _receivePort.sendPort,
    );
    Isolate.spawn(_zipWorker, params);
  }

  Future<void> close() => _sendRequest<void>(_RequestType.close);

  Future<void> writeFile(String name, File file, {bool compress = true}) =>
      _sendRequest<void>(_RequestType.writeFile, [name, file, compress]);

  Future<void> writeData(String name, Uint8List data, {bool compress = true}) =>
      _sendRequest<void>(_RequestType.writeData, [name, data, compress]);

  Future<T> _sendRequest<T>(_RequestType type, [dynamic param]) async {
    final sendPort = await _sendPort.future;
    final request = _Request(++_requestId, type, param);
    final completer = Completer<T>();
    _requests[request.id] = completer;
    sendPort.send(request);
    return completer.future;
  }

  void _listenForWorkerMessages() async {
    await for (final message in _receivePort) {
      if (message is SendPort) {
        _sendPort.complete(message);
      } else if (message is _Exception) {
        throw ZipException(message.message);
      } else if (message is _Quit) {
        break;
      } else if (message is _Response) {
        if (message.error != null) {
          throw ZipException(message.error!);
        } else {
          final completer = _requests[message.id];
          if (completer != null) {
            _requests.remove(message.id);
            if (message.error != null) {
              print('Response for ${message.id} with error=${message.error}');
              completer.completeError(ZipException(message.error!));
            } else {
              completer.complete(message.param);
            }
          }
        }
      }
    }
    print('Stopped listening for messages');
  }

  static void _zipWorker(_ZipWorkerParams params) async {
    final receivePort = ReceivePort();
    params.sendPort.send(receivePort.sendPort);

    final ZipHandle handle;
    try {
      handle = _open(params.file, params.compressionLevel);
    } on ZipException catch (ex) {
      params.sendPort.send(_Exception(ex.message));
      params.sendPort.send(_Quit());
      return;
    }

    await for (final message in receivePort) {
      if (message is _Request) {
        try {
          if (message.type == _RequestType.close) {
            _close(handle);
            params.sendPort.send(_Response(message.id));
            params.sendPort.send(_Quit());
            print('Isolate stopped');
            return;
          } else if (message.type == _RequestType.writeFile) {
            final args = message.param as List<dynamic>;
            final name = args[0] as String;
            final file = args[1] as File;
            final compress = args[2] as bool;
            _writeFile(handle, name, file, compress);
            params.sendPort.send(_Response(message.id));
          } else if (message.type == _RequestType.writeData) {
            final args = message.param as List<dynamic>;
            final name = args[0] as String;
            final data = args[1] as Uint8List;
            final compress = args[2] as bool;
            _writeData(handle, name, data, compress);
            params.sendPort.send(_Response(message.id));
          }
        } on ZipException catch (ex) {
          params.sendPort.send(_Response(message.id, null, ex.message));
        }
      }
    }
  }
}

ZipHandle _open(File file, int compressionLevel) {
  final nativeFilePath = file.path.toNativeUtf8();
  final handle = zipOpen(nativeFilePath, compressionLevel, ModeWrite);
  malloc.free(nativeFilePath);
  if (handle.address == 0) {
    throw ZipException('Cannot create Zip file at "${file.path}"');
  }
  return handle;
}

void _writeFile(ZipHandle handle, String name, File file, bool compress) {
  var level = 0;
  if (!compress) {
    level = zipSetLevel(handle, 0);
  }

  try {
    final nativeName = name.toNativeUtf8();
    final openResult = zipEntryOpen(handle, nativeName);
    malloc.free(nativeName);

    if (openResult != 0) {
      throw ZipException('Cannot create entry "$name"');
    }

    final nativePath = file.path.toNativeUtf8();
    final writeResult = zipEntryFWrite(handle, nativePath);
    malloc.free(nativePath);

    if (writeResult != 0) {
      throw ZipException('Cannot write file "$file" to entry "$name"');
    }

    zipEntryClose(handle);
  } finally {
    if (!compress) {
      zipSetLevel(handle, level);
    }
  }
}

void _writeData(ZipHandle handle, String name, Uint8List data, bool compress) {
  var level = 0;
  if (!compress) {
    level = zipSetLevel(handle, 0);
  }

  try {
    final nativeName = name.toNativeUtf8();
    final openResult = zipEntryOpen(handle, nativeName);
    malloc.free(nativeName);

    if (openResult != 0) {
      throw ZipException('Cannot create entry "$name"');
    }

    final bufferPointer = malloc<Uint8>(data.length);
    final buffer = bufferPointer.asTypedList(data.length);
    buffer.setAll(0, data);

    final writeResult = zipEntryWrite(handle, bufferPointer, data.length);
    malloc.free(bufferPointer);

    if (writeResult != 0) {
      throw ZipException('Cannot write file ${data.length} bytes of data to entry "$name"');
    }

    zipEntryClose(handle);
  } finally {
    if (!compress) {
      zipSetLevel(handle, level);
    }
  }
}

void _close(ZipHandle handle) {
  zipClose(handle);
}

class _ZipWorkerParams {
  final File file;
  final int compressionLevel;
  final SendPort sendPort;

  _ZipWorkerParams({
    required this.file,
    required this.compressionLevel,
    required this.sendPort,
  });
}

class _Exception {
  final String message;

  _Exception(this.message);
}

class _Quit {}

enum _RequestType {
  close,
  writeFile,
  writeData,
}

class _Request<T> {
  final int id;
  final _RequestType type;
  final T? param;

  _Request(this.id, this.type, [this.param]);
}

class _Response<T> {
  final int id;
  final T? param;
  final String? error;

  _Response(this.id, [this.param, this.error]);
}
