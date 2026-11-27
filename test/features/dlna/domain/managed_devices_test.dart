import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/dlna/domain/managed_devices.dart';

void main() {
  group('isManagedDevice', () {
    test('LX06 受管', () {
      expect(isManagedDevice('http://10.10.10.20:25826/upnp/desc.xml'), true);
    });
    test('CCH 受管', () {
      expect(isManagedDevice('http://10.10.10.25:25826/upnp/desc.xml'), true);
    });
    test('普通电视不受管', () {
      expect(isManagedDevice('http://192.168.2.111:25826/upnp/desc.xml'), false);
    });
    test('非法 location 不误判', () {
      expect(isManagedDevice('not-a-url'), false);
    });
    test('可覆盖名单', () {
      expect(isManagedDevice('http://10.10.10.99:80/', ['10.10.10.99']), true);
      expect(isManagedDevice('http://10.10.10.20:80/', ['10.10.10.99']), false);
    });
    test('大小写不敏感主机名', () {
      expect(isManagedDevice('http://10.10.10.20:80/'.toUpperCase()), true);
    });
  });
  group('hostFromLocation', () {
    test('解析 host', () {
      expect(hostFromLocation('http://10.10.10.25:25826/x'), '10.10.10.25');
    });
    test('无 host 返回 null', () {
      expect(hostFromLocation(''), null);
      expect(hostFromLocation('not-a-url'), null);
    });
  });
}
