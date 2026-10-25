/// 显示格式化工具（流量、字节、时间等）。
library;

String formatBytes(num? bytes, {int digits = 1}) {
  if (bytes == null || bytes < 0) return '—';
  if (bytes < 1024) return '$bytes B';
  const units = ['KiB', 'MiB', 'GiB', 'TiB'];
  var v = bytes / 1024.0;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : digits)} ${units[i]}';
}

String formatRate(num? bytesPerSec) =>
    bytesPerSec == null || bytesPerSec <= 0 ? '—' : '${formatBytes(bytesPerSec)}/s';

String formatDurationSec(int? sec) {
  if (sec == null || sec < 0) return '—';
  if (sec == 0) return '0 秒';
  final d = Duration(seconds: sec);
  final parts = <String>[];
  if (d.inDays > 0) parts.add('${d.inDays} 天');
  if (d.inHours % 24 > 0) parts.add('${d.inHours % 24} 小时');
  if (d.inMinutes % 60 > 0) parts.add('${d.inMinutes % 60} 分');
  if (d.inSeconds % 60 > 0 && d.inDays == 0) parts.add('${d.inSeconds % 60} 秒');
  return parts.take(2).join();
}

String formatTime(DateTime? t) {
  if (t == null) return '—';
  final now = DateTime.now();
  final local = t.toLocal();
  final d = now.difference(local);
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(local.hour)}:${two(local.minute)}';
  if (d.inDays == 0 && local.day == now.day) return hm;
  if (d.inDays < 7) return '$hm (${d.inDays} 天前)';
  return '${local.year}-${two(local.month)}-${two(local.day)} $hm';
}

String formatPercent(double? v) =>
    v == null ? '—' : (v >= 99.95 ? '100%' : '${v.toStringAsFixed(1)}%');

/// Syncthing 设备 ID 按 7 字符一组展示。
/// v2 API 返回的 ID 已含分组横线（如 ABCDEFG-XXXXXXX-...），此时原样返回。
String formatDeviceId(String id) {
  if (id.contains('-')) return id;
  final buf = StringBuffer();
  for (var i = 0; i < id.length; i += 7) {
    if (i > 0) buf.write('-');
    buf.write(id.substring(i, i + 7 > id.length ? id.length : i + 7));
  }
  return buf.toString();
}
