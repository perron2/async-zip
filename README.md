# Asynchronous Zip library

![Pub Version](https://img.shields.io/pub/v/async_zip)

This package allows reading and writing Zip archives asynchronously and with
low memory consumption.

There is already a [standard archive library](https://pub.dev/packages/archive)
for Dart. But the standard library has two major issues:
- It cannot be used asynchronously
- It reads Zip files completely to memory and unpacks them from there. This is an
  issue when reading large Zip files on low or medium range devices.

## Reading Zip files

Zip files can be read synchronously and asynchronously. Synchronous reading
might be faster in some situations. Choose whatever you need.

### Reading data synchronously

```dart
try {
  final reader = ZipFileReader('path-to-archive.zip');
  
  // Get all Zip entries
  final entries = reader.entries();
  for (final entry in entries) {
    print('${entry.name} ${entry.size}');
  }

  // Read a specific file
  reader.readFile('specific-image.jpg', File('/somewhere/on/disk/image.jpg'));

  // Read specific data as Uint8List
  final data = reader.readFile('README.md');

} on ZipException catch (ex) {
  print('Could not read Zip file: ${$ex.message}');
}
```

### Reading data asynchronously

```dart
try {
  final reader = ZipFileReaderAsync('path-to-archive.zip');
  
  // Get all Zip entries
  final entries = await reader.entries();
  for (final entry in entries) {
    print('${entry.name} ${entry.size}');
  }

  // Read a specific file
  await reader.readFile('specific-image.jpg', File('/somewhere/on/disk/image.jpg'));

  // Read specific data as Uint8List
  final data = await reader.readFile('README.md');

} on ZipException catch (ex) {
  print('Could not read Zip file: ${$ex.message}');
}
```
