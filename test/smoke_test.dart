import 'package:flutter_test/flutter_test.dart';
import 'package:syncthing_flutter/syncthing/models.dart';

void main() {
  test('FolderConfig 容错解析与无损写回', () {
    final f = FolderConfig({
      'id': 'abcd-1234',
      'label': '照片',
      'type': 'sendonly',
      'devices': [
        {'deviceID': 'DEV1', 'introducedBy': ''}
      ],
      'unknownFutureField': {'x': 1},
    });
    expect(f.id, 'abcd-1234');
    expect(f.type, 'sendonly');
    expect(f.devices.length, 1);
    expect(f.rescanIntervalS, 3600); // 缺省
    f.label = '新名字';
    expect(f.toJson()['unknownFutureField'], isNotNull); // 未知字段保留
    expect(f.toJson()['label'], '新名字');
  });

  test('VersioningConfig params 是活引用（编辑直接落 raw）', () {
    final f = FolderConfig({
      'id': 'x',
      'versioning': {
        'type': 'simple',
        'params': {'keep': 5},
      },
    });
    f.versioning.params['keep'] = '9';
    expect(f.toJson()['versioning']['params']['keep'], '9');
  });

  test('FolderStatus completion 计算', () {
    final s = FolderStatus.fromJson({'globalBytes': 1000, 'needBytes': 250});
    expect(s.completion, 75.0);
  });
}
