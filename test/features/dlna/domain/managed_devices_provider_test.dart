// 投屏入口守卫的纯逻辑测试：受管设备在 castToDevice 入口被拒。
//
// 说明：provider 依赖 flutter_riverpod/audio_service，本仓现有测试用
// 子类化 provider + 打桩（见 device_sheet_test.dart 的 _Dlna）。这里只测
// 守卫所依赖的纯函数与文案，确保「识别 → 拒绝文案」契约不回归。
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/dlna/domain/managed_devices.dart';

void main() {
  test('受管设备命中且给出明确拒绝文案', () {
    final device = 'http://10.10.10.20:25826/desc.xml';
    expect(isManagedDevice(device), true);
    expect(managedDeviceCastBlocked.contains('中枢托管'), true);
    expect(managedDeviceCastBlocked.contains('语音点播'), true);
  });

  test('普通设备不被误挡', () {
    expect(isManagedDevice('http://192.168.2.111:25826/desc.xml'), false);
  });
}
