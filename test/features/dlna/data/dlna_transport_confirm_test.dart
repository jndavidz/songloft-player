import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/dlna/data/dlna_service.dart';

/// 可编程渲染器：用 [state] 表态，用 [playUntilConfirmed] 模拟
/// 「第一次 Play 被设备丢弃、第二次才真正起播」的过渡期行为。
class _Device extends DLNADevice {
  _Device()
    : super(
        DeviceInfo('http://192.168.2.111:9999', 'MediaRenderer', '音箱', [
          {
            'serviceId': 'urn:upnp-org:serviceId:AVTransport',
            'controlURL': '/upnp/control/AVTransport',
          },
        ]),
      );

  final commands = <String>[];
  String state = 'PAUSED_PLAYBACK';

  /// 少数渲染器不实现 GetTransportInfo：回空正文让解析失败。
  bool supportsTransportInfo = true;

  /// 收到第 N 次 Play 才真正进入 PLAYING（N=1 表示首次即生效）。
  int playUntilConfirmed = 1;
  int _plays = 0;

  /// 投屏自身也会发一次 Play，测试关心的是之后的用户点击，故单独计数。
  void resetPlayCount() => _plays = 0;

  @override
  Future<String> request(String action, List<int> body) async {
    commands.add(action);
    switch (action) {
      case 'Play':
        _plays++;
        if (_plays >= playUntilConfirmed) state = 'PLAYING';
        return '';
      case 'Pause':
        state = 'PAUSED_PLAYBACK';
        return '';
      case 'GetTransportInfo':
        if (!supportsTransportInfo) return '';
        return '<root><CurrentTransportState>$state</CurrentTransportState>'
            '<CurrentTransportStatus>OK</CurrentTransportStatus></root>';
      case 'GetPositionInfo':
        // PositionParser 要求四个时间/URI 字段都在，否则 first 会抛 No element。
        return '<root><TrackDuration>00:03:00</TrackDuration>'
            '<RelTime>00:00:12</RelTime>'
            '<AbsTime>00:00:12</AbsTime>'
            '<TrackURI>http://server/song.mp3</TrackURI></root>';
      default:
        return '';
    }
  }
}

class _Manager extends DLNAManager {
  final deviceManager = DeviceManager();

  @override
  Future<DeviceManager> start({reusePort = false}) async => deviceManager;

  @override
  void stop() {}
}

void main() {
  late DlnaService service;
  late _Device device;

  Future<void> castOnce() async {
    device.playUntilConfirmed = 1;
    await service.castTo(device.info.URLBase, 'http://server/song.mp3');
    device.commands.clear();
    device.playUntilConfirmed = 1;
    device.resetPlayCount();
    device.state = 'PAUSED_PLAYBACK';
  }

  setUp(() {
    device = _Device();
    final manager = _Manager();
    manager.deviceManager.deviceList[device.info.URLBase] = device;
    // 探测间隔归零：纯逻辑验证，不引入真实等待。
    service = DlnaService(manager: manager, verifyProbeGap: Duration.zero);
    addTearDown(service.dispose);
  });

  test('第一次 Play 被设备丢弃时补发，并在确认后返回成功', () async {
    await service.startDiscovery();
    await castOnce();
    device.playUntilConfirmed = 2; // 第一发 Play 无效
    final reported = <bool>[];
    final sub = service.playingStream.listen(reported.add);
    addTearDown(sub.cancel);

    expect(await service.play(), isTrue);
    await pumpEventQueue(); // 广播流投递是微任务，不是同步
    expect(device.commands.where((c) => c == 'Play'), hasLength(2));
    expect(reported, [true]);
  });

  test('设备始终不恢复时返回 false，不谎报成功', () async {
    await service.startDiscovery();
    await castOnce();
    device.playUntilConfirmed = 99;
    final reported = <bool>[];
    final sub = service.playingStream.listen(reported.add);
    addTearDown(sub.cancel);

    expect(await service.play(), isFalse);
    // 1 次下发 + 2 次补偿；位置未知时不发 Seek（避免把歌重头放）
    expect(device.commands.where((c) => c == 'Play'), hasLength(3));
    expect(device.commands.where((c) => c == 'Seek'), isEmpty);
    expect(reported, isEmpty);
  });

  test('设备不回报 TransportState 时按 HTTP 成功兜底，不反复重发', () async {
    await service.startDiscovery();
    device.supportsTransportInfo = false;
    await service.castTo(device.info.URLBase, 'http://server/song.mp3');
    device.commands.clear();

    expect(await service.play(), isTrue);
    expect(device.commands.where((c) => c == 'Play'), hasLength(1));
  });

  test('暂停以设备 PAUSED 状态确认', () async {
    await service.startDiscovery();
    device.playUntilConfirmed = 1;
    await service.castTo(device.info.URLBase, 'http://server/song.mp3');
    device.commands.clear();
    final reported = <bool>[];
    final sub = service.playingStream.listen(reported.add);
    addTearDown(sub.cancel);

    expect(await service.pause(), isTrue);
    await pumpEventQueue();
    expect(device.commands, ['Pause', 'GetTransportInfo']);
    expect(reported, [false]);
  });

  testWidgets('轮询把设备真实播放态推给 UI（投屏进度也来自同一轮询）', (tester) async {
    await service.startDiscovery();
    await castOnce();
    final reported = <bool>[];
    final sub = service.playingStream.listen(reported.add);
    addTearDown(sub.cancel);
    final positions = <Duration>[];
    final positionSub = service.positionStream.listen(
      (p) => positions.add(Duration(seconds: p.RelTimeInt)),
    );
    addTearDown(positionSub.cancel);

    device.state = 'PAUSED_PLAYBACK';
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(reported, [false]);
    device.state = 'PLAYING';
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(reported, [false, true]);
    expect(positions, isNotEmpty);
    expect(positions.last, const Duration(seconds: 12));
    service.disconnect(); // 停掉 2s 轮询，避免测试结束时仍有 pending timer
  });
}
