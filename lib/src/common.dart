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