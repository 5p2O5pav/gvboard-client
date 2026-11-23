import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final values = _arguments(args);
  final input = values['input'];
  final output = values['output'];
  final keyText = values['key'];
  if (input == null || output == null || keyText == null) {
    stderr.writeln(
      '用法：dart run tool/encrypt_oss.dart --input config.json --output config.oss --key <32-byte-base64>',
    );
    exitCode = 2;
    return;
  }
  final key = _decodeKey(keyText);
  final plain = await File(input).readAsBytes();
  final box = await AesGcm.with256bits().encrypt(
    plain,
    secretKey: SecretKey(key),
  );
  final encrypted = box.concatenation();
  await File(output).writeAsString(base64Encode(encrypted));
}

Map<String, String> _arguments(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    final name = args[i];
    if (!name.startsWith('--')) continue;
    result[name.substring(2)] = args[i + 1];
  }
  return result;
}

List<int> _decodeKey(String value) {
  try {
    final decoded = base64.decode(value);
    if (decoded.length == 32) return decoded;
  } on FormatException {
    // Fall through to hexadecimal form.
  }
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
    return [
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ];
  }
  throw const FormatException('密钥必须是 32 字节 Base64 或 64 位十六进制');
}
