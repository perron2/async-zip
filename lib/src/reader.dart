import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'common.dart';
import 'zip.dart';

class ZipFileReader {
  ZipHandle? _handle;

  void open(File file) {
    if (_handle != null) {
      throw ZipException('ZipFileReader already opened; call close() first');
    }
    _handle = _open(file);
  }

  void close() {
    if (_handle != null) {
      _close(_handle!);
    }
    _handle = null;
  }

  Iterable<ZipEntry> entries() => _entries(_checkOpened(_handle));

  void readToFile(String name, File file) => _readToFile(_checkOpened(_handle), name, file);

  Uint8List read(String name) => _read(_checkOpened(_handle), name);
}

class ZipFileReaderAsync {
  final _receivePort = ReceivePort();
  final _sendPort = new Completer<SendPort>();
  final _requests = <int, Completer>{};
  var _requestId = 0;

  ZipFileReaderAsync() {
    _listenForWorkerMessages();
    Isolate.spawn(_zipWorker, _receivePort.sendPort);
  }

  Future<void> open(File file) => _sendRequest<void>(_RequestType.open, file);

  Future<void> close() => _sendRequest<void>(_RequestType.close);

  Future<List<ZipEntry>> entries() => _sendRequest<List<ZipEntry>>(_RequestType.entries);

  Future<void> readToFile(String name, File file) =>
      _sendRequest<void>(_RequestType.readToFile, [name, file]);

  Future<Uint8List> read(String name) => _sendRequest<Uint8List>(_RequestType.read, name);

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
      } else if (message is _Quit) {
        break;
      } else if (message is _Response) {
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
    print('Stopped listening for messages');
  }

  static void _zipWorker(SendPort sendPort) async {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    ZipHandle? handle;
    await for (final message in receivePort) {
      if (message is _Request) {
        print('Request received: ${message.id} of type ${message.type}');
        try {
          if (message.type == _RequestType.open) {
            if (handle != null) {
              throw ZipException('ZipFileReader already opened; call close() first');
            }
            final file = message.param as File;
            handle = _open(file);
            sendPort.send(_Response(message.id));
          } else if (message.type == _RequestType.close) {
            if (handle != null) {
              _close(handle);
            }
            sendPort.send(_Response(message.id));
            sendPort.send(_Quit());
            print('Isolate stopped');
            return;
          } else if (message.type == _RequestType.entries) {
            final entries = _entries(_checkOpened(handle));
            sendPort.send(_Response(message.id, entries));
          } else if (message.type == _RequestType.readToFile) {
            final args = message.param as List<dynamic>;
            final name = args[0] as String;
            final file = args[1] as File;
            _readToFile(_checkOpened(handle), name, file);
            sendPort.send(_Response(message.id));
          } else if (message.type == _RequestType.read) {
            final name = message.param as String;
            final data = _read(_checkOpened(handle), name);
            sendPort.send(_Response(message.id, data));
          }
        } on ZipException catch (ex) {
          sendPort.send(_Response(message.id, null, ex.message));
        }
      }
    }
  }
}

ZipHandle _open(File file) {
  final nativeFilePath = file.path.toNativeUtf8();
  final handle = zipOpen(nativeFilePath, 0, ModeRead);
  malloc.free(nativeFilePath);
  if (handle.address == 0) {
    throw ZipException('Cannot open Zip file at "${file.path}"');
  }
  return handle;
}

void _close(ZipHandle handle) {
  zipClose(handle);
}

Iterable<ZipEntry> _entries(ZipHandle handle) {
  final numEntries = zipEntriesTotal(handle);
  if (numEntries < 0) {
    throw ZipException('Cannot determine number of Zip entries');
  }

  final entries = <ZipEntry>[];
  for (int i = 0; i < numEntries; i++) {
    int success = zipEntryOpenByIndex(handle, i);
    if (success == 0) {
      final name = zipEntryName(handle).toDartString();
      final size = zipEntrySize(handle);
      final isDir = zipEntryIsDir(handle) == 1;
      final crc32 = zipEntryCrc32(handle);
      entries.add(ZipEntry(name, isDir, size, crc32));
      zipEntryClose(handle);
    }
  }

  return entries;
}

void _readToFile(ZipHandle handle, String name, File file) {
  final nativeName = name.toNativeUtf8();
  final openResult = zipEntryOpen(handle, nativeName);
  malloc.free(nativeName);

  if (openResult != 0) {
    throw ZipException('Entry "$name" not found');
  }

  final nativePath = file.path.toNativeUtf8();
  final freadResult = zipEntryFRead(handle, nativePath);
  malloc.free(nativePath);
  zipEntryClose(handle);

  if (freadResult != 0) {
    throw ZipException('Cannot write "$name" to file "${file.path}');
  }
}

Uint8List _read(ZipHandle handle, String name) {
  final nativeName = name.toNativeUtf8();
  final openResult = zipEntryOpen(handle, nativeName);
  malloc.free(nativeName);

  if (openResult != 0) {
    throw ZipException('Entry "$name" not found');
  }

  final dataPointer = malloc<DataPointer>();
  final sizePointer = malloc<Int32>();

  final bytesRead = zipEntryRead(handle, dataPointer, sizePointer);
  final realDataAddress = dataPointer.value.address;
  malloc.free(dataPointer);
  malloc.free(sizePointer);

  if (bytesRead >= 0 && realDataAddress != 0) {
    final realDataPointer = Pointer<Uint8>.fromAddress(dataPointer.value.address);
    final data = realDataPointer.asTypedList(sizePointer.value);
    malloc.free(realDataPointer);
    return data;
  }

  throw ZipException('Cannot read data from "$name"');
}

ZipHandle _checkOpened(ZipHandle? handle) {
  if (handle == null) {
    throw ZipException('Zip file is not opened');
  }
  return handle;
}

class _Quit {}

enum _RequestType {
  open,
  close,
  entries,
  readToFile,
  read,
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
