import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Zeigt ein lokal gewähltes Foto an (image_picker). Im Browser ist der Pfad
/// eine blob:-URL, in den Apps ein Dateipfad.
Image pickedImage(String path, {double? width, double? height, BoxFit? fit}) {
  if (kIsWeb) {
    return Image.network(path, width: width, height: height, fit: fit);
  }
  return Image.file(File(path), width: width, height: height, fit: fit);
}
