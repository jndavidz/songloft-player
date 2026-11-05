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

  /// 模拟 LX06：普通 Play 一律被丢弃，只有 SetAVTransportURI 重投后才接受 Play。
  bool playIgnoredUntilReload = false;
  bool _reloaded = false;

  /// 模拟「HTTP 200 + SOAP Fault 正文」的假成功（701/710/714 这类真实拒绝码）。
  bool faultOnPlay = false;
  bool faultOnSeek = false;

  static const _faultBody =
      '<s:Envelope><s:Body><s:Fault><faultcode>s:Client</faultcode>'
      '<detail><UPnPError><errorCode>701</errorCode>'
      '<errorDescription>Transition not available</errorDescription>'
      '</UPnPError></detail></s:Fault></s:Body></s:Envelope>';

  /// GetPositionInfo 回报的播放位置 / 曲目时长（秒），用于模拟「播完」与「暂停」。
  int positionSeconds = 12;
  int durationSeconds = 180;

  static String _fmt(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// 投屏自身也会发一次 Play，测试关心的是之后的用户点击，故单独计数。
  void resetPlayCount() => _plays = 0;

  @override
  Future<String> request(String action, List<int> body) async {
    commands.add(action);
    switch (action) {
      case 'Play':
        _plays++;
        if (faultOnPlay) return _faultBody;
        if (playIgnoredUntilReload && !_reloaded) return ''; // 丢弃，状态不变
        if (_plays >= playUntilConfirmed) state = 'PLAYING';
        return '';
      case 'Seek':
        if (faultOnSeek) return _faultBody;
        return '';
      case 'SetAVTransportURI':
        _reloaded = true;
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
        return '<root><TrackDuration>${_fmt(durationSeconds)}</TrackDuration>'
            '<RelTime>${_fmt(positionSeconds)}</RelTime>'
            '<AbsTime>${_fmt(positionSeconds)}</AbsTime>'
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
    device.playIgnoredUntilReload = false;
    device._reloaded = false;
    device.faultOnPlay = false;
    device.faultOnSeek = false;
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
    // 3 次常规下发 + 1 次 recast 重投（重投仍失败时如实返回 false，不谎报成功）；
    // 位置未知时不发 Seek（避免把歌重头放）
    expect(device.commands.where((c) => c == 'Play'), hasLength(4));
    expect(
      device.commands.where((c) => c == 'SetAVTransportURI'),
      hasLength(1),
      reason: '常规 Play 全部无效后必须尝试 recast，即使最终仍失败',
    );
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
    // 先读设备态（PLAYING）再下发 Pause，再回读确认（PAUSED）。
    expect(device.commands, ['GetTransportInfo', 'Pause', 'GetTransportInfo']);
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

  // 轮询用真实 Timer（2s），pause 的补偿探测也走真实延时；
  // 故用 test + 真实等待，而不是 testWidgets（假时钟会让 Future.delayed 卡死）。
  Future<void> waitPollTicks() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  test('暂停后渲染器上报 STOPPED 不判定播完（不推进下一首）', () async {
    await service.startDiscovery();
    device.state = 'PLAYING';
    await service.castTo(device.info.URLBase, 'http://server/song.mp3');
    final completions = <void>[];
    final sub = service.completionStream.listen(completions.add);
    addTearDown(sub.cancel);

    await waitPollTicks();
    expect(device.state, 'PLAYING');

    device.state = 'PAUSED_PLAYBACK';
    expect(await service.pause(), isTrue);

    // 部分渲染器（LX06 DMR）暂停后把 transport 掉到 STOPPED，位置仍停在曲中。
    device.state = 'STOPPED';
    device.positionSeconds = 12;
    await waitPollTicks();

    expect(completions, isEmpty, reason: '暂停导致的 STOPPED 不是曲末，不能推进队列');
    service.disconnect();
  });

  test('暂停后首按播放：Play 被设备丢弃时自动重投恢复（不必再点第二次）', () async {
    await service.startDiscovery();
    await castOnce();
    expect(await service.pause(), isTrue);
    // 模拟 LX06：暂停后 transport 掉到 STOPPED，此后普通 Play 一律被丢弃，
    // 只有 SetAVTransportURI 重投当前曲才重新接受 Play。
    device.state = 'STOPPED';
    device.playIgnoredUntilReload = true;
    final reported = <bool>[];
    final sub = service.playingStream.listen(reported.add);
    addTearDown(sub.cancel);

    expect(await service.play(), isTrue);
    await pumpEventQueue();
    expect(
      device.commands.where((c) => c == 'SetAVTransportURI'),
      isNotEmpty,
      reason: '普通 Play 无效时必须走 recast 重投，而不是把失败丢给用户',
    );
    expect(device.state, 'PLAYING');
    expect(reported, [true]);
    service.disconnect();
  });

  test('位置接近曲尾时 STOPPED 仍按播完处理', () async {
    await service.startDiscovery();
    device.state = 'PLAYING';
    device.positionSeconds = 170;
    await service.castTo(device.info.URLBase, 'http://server/song.mp3');
    final completions = <void>[];
    final sub = service.completionStream.listen(completions.add);
    addTearDown(sub.cancel);

    await waitPollTicks();

    device.state = 'STOPPED';
    device.positionSeconds = 180; // 与 TrackDuration 相同，即自然播完
    await waitPollTicks();

    expect(completions, hasLength(1));
    service.disconnect();
  });

  test('toggle 以设备回读态定方向：PAUSED 发 Play，PLAYING 发 Pause', () async {
    await service.startDiscovery();
    await castOnce();

    // 本地 UI 认为「在播」，设备实际 PAUSED：必须发 Play 而不是 Pause。
    device.state = 'PAUSED_PLAYBACK';
    expect(await service.togglePlayback(), isTrue);
    expect(device.commands.where((c) => c == 'Play'), isNotEmpty);
    expect(device.commands.where((c) => c == 'Pause'), isEmpty);
    expect(device.state, 'PLAYING');

    // 反向：设备实际在播（本地可能滞后）→ 发 Pause。
    device.commands.clear();
    expect(await service.togglePlayback(), isFalse);
    expect(device.commands.where((c) => c == 'Pause'), isNotEmpty);
    expect(device.state, 'PAUSED_PLAYBACK');
    service.disconnect();
  });

  test('HTTP 200 但正文是 SOAP Fault 时如实判失败，不谎报起播', () async {
    await service.startDiscovery();
    await castOnce();
    device.faultOnPlay = true;
    expect(await service.play(), isFalse);
    expect(device.state, 'PAUSED_PLAYBACK');
    service.disconnect();
  });

  test('STOPPED 态点播放直接重投，不先发必然失败的 Play', () async {
    await service.startDiscovery();
    await castOnce();
    device.state = 'STOPPED';
    device.commands.clear();
    device.playUntilConfirmed = 1;
    device.playIgnoredUntilReload = true; // 只有重投后才接受 Play

    expect(await service.togglePlayback(), isTrue);
    final firstTransportPlay = device.commands.indexOf('Play');
    final reload = device.commands.indexOf('SetAVTransportURI');
    expect(reload, isNonNegative);
    expect(firstTransportPlay, greaterThan(reload), reason: '重投必须先于 Play');
    expect(device.state, 'PLAYING');
    service.disconnect();
  });
}
