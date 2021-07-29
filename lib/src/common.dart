import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

class ZipEntry {
  final String name;
  final bool isDir;
  final int size;
  final int crc32;

  ZipEntry(this.name, this.isDir, this.size, this.crc32);
}

class ZipException implements Exception {
  final String message;

  ZipException(this.message);

  @override
  String toString() {
    return 'ZipException($message)';
  }
}

typedef IsolateWorker = void Function(SendPort sendPort);

class IsolateManager<T> {
  final _receivePort = ReceivePort();
  final _sendPort = new Completer<SendPort>();
  final _requests = <int, Completer>{};
  var _requestId = 0;

  IsolateManager(IsolateWorker worker) {
    _listenForWorkerMessages();
    Isolate.spawn(worker, _receivePort.sendPort);
  }

  Future<P> sendRequest<P>(T type, [dynamic param]) async {
    final sendPort = await _sendPort.future;
    final request = IsolateRequest(++_requestId, type, param);
    final completer = Completer<P>();
    _requests[request.id] = completer;
    sendPort.send(request);
    return completer.future;
  }

  void _listenForWorkerMessages() async {
    await for (final message in _receivePort) {
      if (message is SendPort) {
        _sendPort.complete(message);
      } else if (message is IsolateQuitMessage) {
        break;
      } else if (message is IsolateResponse) {
        final completer = _requests[message.id];
        if (completer != null) {
          _requests.remove(message.id);
          if (message.error != null) {
            debugPrint('Response for ${message.id} with error=${message.error}');
            completer.completeError(ZipException(message.error!));
          } else {
            completer.complete(message.param);
          }
        }
      }
    }
    debugPrint('Stopped listening for messages');
  }
}

class IsolateRequest<T, P> {
  final int id;
  final T type;
  final P? param;

  IsolateRequest(this.id, this.type, [this.param]);
}

class IsolateResponse<P> {
  final int id;
  final P? param;
  final String? error;

  IsolateResponse(this.id, [this.param, this.error]);
}

class IsolateQuitMessage {}
