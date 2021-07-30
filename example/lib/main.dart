import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:async_zip/async_zip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Asynchronous Zip example'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                child: Text('Create Zip file'),
                onPressed: () => _createZipFile(),
              ),
              ElevatedButton(
                child: Text('Read Zip file'),
                onPressed: () => _readZipFile(),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Take note of logging output in the console'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _readZipFile() async {
    // Save bundled asset Zip file to temporary directory in order to read
    // it from there. This is just for illustration purposes.
    final tempDir = Directory.systemTemp;
    final archiveData = await rootBundle.load('assets/archive.zip');
    final archiveFile = File(path.join(tempDir.path, 'archive.zip'));
    await archiveFile.writeAsBytes(archiveData.buffer.asUint8List());

    // Read the Zip file synchronously
    final reader = ZipFileReader();
    print('Reading synchronously from Zip file ${archiveFile.path}');
    try {
      reader.open(archiveFile);

      for (final entry in reader.entries()) {
        print('${entry.name} ${entry.size} ${entry.isDir ? 'DIR' : 'FILE'}');
      }

      final imageFile = File(path.join(tempDir.path, 'image.jpg'));
      reader.readToFile('butterfly.jpg', imageFile);

      final jsonData = reader.read('data/person.json');
      print(utf8.decode(jsonData));
    } on ZipException catch (ex) {
      print('An error ocurred while reading from the Zip file: ${ex.message}');
    } finally {
      reader.close();
    }

    // Read the Zip file asynchronously
    final asyncReader = ZipFileReaderAsync();
    print('Reading asynchronously from Zip file ${archiveFile.path}');
    try {
      await asyncReader.open(archiveFile);

      for (final entry in await asyncReader.entries()) {
        print('${entry.name} ${entry.size} ${entry.isDir ? 'DIR' : 'FILE'}');
      }

      final imageFile = File(path.join(tempDir.path, 'image.jpg'));
      await asyncReader.readToFile('butterfly.jpg', imageFile);

      final jsonData = await asyncReader.read('data/person.json');
      print(utf8.decode(jsonData));
    } on ZipException catch (ex) {
      print('An error ocurred while reading from the Zip file: ${ex.message}');
    } finally {
      await asyncReader.close();
    }
  }

  void _createZipFile() async {
    // Save bundled files to temporary directory in order to write
    // them to the Zip file. This is just for illustration purposes.
    final tempDir = Directory.systemTemp;
    final archiveFile = File(path.join(tempDir.path, 'create-archive-sync.zip'));
    final butterflyData = await rootBundle.load('assets/butterfly.jpg');
    final butterflyFile = File(path.join(tempDir.path, 'image.jpg'));
    await butterflyFile.writeAsBytes(butterflyData.buffer.asUint8List());
    final jsonData = await rootBundle.load('assets/person.json');
    final jsonFile = File(path.join(tempDir.path, 'person.json'));
    await jsonFile.writeAsBytes(jsonData.buffer.asUint8List());

    // Create the Zip file synchronously
    final writer = ZipFileWriter();
    try {
      writer.create(archiveFile);
      writer.writeFile('butterfly.jpg', butterflyFile);
      writer.writeFile('data/person.json', jsonFile);

      final textData = await rootBundle.loadString('assets/fox.txt');
      writer.writeData('fox.txt', Uint8List.fromList(utf8.encode(textData)));
    } on ZipException catch (ex) {
      print('An error ocurred while creating the Zip file: ${ex.message}');
    } finally {
      writer.close();
    }

    final archiveSize = archiveFile.lengthSync();
    print('Created Zip file at ${archiveFile.path} with a size of $archiveSize bytes');

    // Create the Zip file asynchronously
    final asyncArchiveFile = File(path.join(tempDir.path, 'create-archive-async.zip'));
    final asyncWriter = ZipFileWriterAsync();
    try {
      await asyncWriter.create(asyncArchiveFile);
      await asyncWriter.writeFile('butterfly.jpg', butterflyFile);
      await asyncWriter.writeFile('data/person.json', jsonFile);

      final textData = await rootBundle.loadString('assets/fox.txt');
      await asyncWriter.writeData('fox.txt', Uint8List.fromList(utf8.encode(textData)));
    } on ZipException catch (ex) {
      print('An error ocurred while creating the Zip file: ${ex.message}');
    } finally {
      await asyncWriter.close();
    }

    final asyncArchiveSize = asyncArchiveFile.lengthSync();
    print('Created Zip file at ${asyncArchiveFile.path} with a size of $asyncArchiveSize bytes');
  }
}
