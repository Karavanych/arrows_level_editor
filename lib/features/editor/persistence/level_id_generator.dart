import 'dart:math';

class EditorLevelIdGenerator {
  EditorLevelIdGenerator({Random? random})
    : _random = random ?? Random.secure();

  static const String _suffixAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  final Random _random;

  String generate({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final datePart =
        '${timestamp.year.toString().padLeft(4, '0')}'
        '${timestamp.month.toString().padLeft(2, '0')}'
        '${timestamp.day.toString().padLeft(2, '0')}';
    final timePart =
        '${timestamp.hour.toString().padLeft(2, '0')}'
        '${timestamp.minute.toString().padLeft(2, '0')}'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final millisPart = timestamp.millisecond.toString().padLeft(3, '0');
    final suffix = _randomSuffix(length: 4);
    return '${datePart}_${timePart}_${millisPart}_$suffix';
  }

  String _randomSuffix({required int length}) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i += 1) {
      final index = _random.nextInt(_suffixAlphabet.length);
      buffer.write(_suffixAlphabet[index]);
    }
    return buffer.toString();
  }
}
