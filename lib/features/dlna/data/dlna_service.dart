import 'dart:async';
import 'dart:convert';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import '../domain/dlna_state.dart';
import 'dlna_log.dart';

class DlnaService {
  DlnaService({
    DLNAManager? manager,
    Duration verifyProbeGap = const Duration(milliseconds: 150),
  }) : _manager = manager ?? DLNAManager(),
       _verifyProbeGap = verifyProbeGap;

  final DLNAManager _manager;

  /// 下发 Play/Pause 后回读 TransportState 的探测间隔；测试注入零间隔。
  final Duration _verifyProbeGap;

  /// 每次下发的确认窗口：最多探测次数（6 × 150ms ≈ 0.9s）。
  static const _verifyProbes = 6;

  /// 单次用户点击最多下发次数（1 次 + 2 次补偿，最后一次带 Seek 重锚）。
  static const _transportAttempts = 3;

  DeviceManager? _deviceManager;
  DLNADevice? _activeDevice;

  Timer? _transportTimer;
  bool _hasStartedPlaying = false;
  bool _suppressCompletion = false; // 重新投歌期间抑制完成误判
  int _generation = 0;
  final _pollErrors = <String, String>{};
  String? _lastTransport;
  Duration? _lastPosition; // 最近一次轮询到的播放位置，恢复兜底时用作 Seek 锚点
  bool? _lastPlaying; // 最近一次向 UI 上报的设备真实播放态（去重用）

  final _devicesController = StreamController<List<DlnaDeviceInfo>>.broadcast();
  final _positionController = StreamController<PositionParser>.broadcast();
  final _completionController = StreamController<void>.broadcast();
  final _playingController = StreamController<bool>.broadcast();

  Stream<List<DlnaDeviceInfo>> get devicesStream => _devicesController.stream;
  Stream<PositionParser> get positionStream => _positionController.stream;

  /// 设备端播放完成事件（当前曲在渲染设备上播完时触发）
  Stream<void> get completionStream => _completionController.stream;

  /// 设备**真实**播放态（来自 2s 轮询的 TransportState），仅在变化时发出。
  /// UI 用它纠正乐观翻转：设备丢弃了 Play/Pause 时，图标不会说谎。
  Stream<bool> get playingStream => _playingController.stream;

  DLNADevice? get activeDevice => _activeDevice;

  Future<void> startDiscovery() async {
    dlnaLog('discovery start');
    try {
      _deviceManager = await _manager.start();
    } catch (error, stack) {
      dlnaLog('discovery failed: $error\n$stack');
      rethrow;
    }
    final seen = <String>{};
    _deviceManager!.devices.stream.listen((deviceMap) {
      for (final device in deviceMap.values) {
        if (seen.add(device.info.URLBase)) {
          dlnaLog(
            'discovered name=${device.info.friendlyName} '
            'base=${device.info.URLBase} services=${jsonEncode(device.info.serviceList)}',
          );
        }
      }
      final devices =
          deviceMap.values
              .map(
                (d) => DlnaDeviceInfo(
                  id: d.info.URLBase,
                  name: d.info.friendlyName,
                  location: d.info.URLBase,
                ),
              )
              .toList();
      _devicesController.add(devices);
    });
  }

  void stopDiscovery() {
    dlnaLog('discovery stop');
    _manager.stop();
    _deviceManager = null;
  }

  Future<void> castTo(
    String deviceId,
    String url, {
    String title = '',
    PlayType mime = AudioMime.mp3,
  }) async {
    final generation = ++_generation;
    _pollErrors.clear();
    _lastTransport = null;
    _lastPosition = null;
    final device = _deviceManager?.deviceList[deviceId];
    dlnaLog(
      'cast device=$deviceId title=$title mime=${mime.protocolInfo} url=$url',
    );
    if (device == null) {
      dlnaLog('cast failed: Device not found: $deviceId');
      throw Exception('Device not found: $deviceId');
    }

    _activeDevice = device;
    // 切歌期间设备会短暂进入 STOPPED/TRANSITIONING，抑制完成检测避免误推进
    _suppressCompletion = true;
    _hasStartedPlaying = false;
    try {
      // mime 由调用方按歌曲真实格式决定（视频→VideoMime，音频→对应 AudioMime），
      // 不再硬编码 mp3：写死 mp3 会让 DIDL 永远声明 audio/mp3，非 mp3（flac/wav）或视频投屏可能被渲染器拒绝。
      await _sendWithRetry(
        'SetAVTransportURI',
        device,
        () => _setUrl(device, url, title, mime),
      );
      if (generation != _generation) return;
      await _sendWithRetry('Play', device, () => device.play());
    } finally {
      _suppressCompletion = false;
    }

    if (generation == _generation) _startCompletionMonitor();
  }

  Future<String> _setUrl(
    DLNADevice device,
    String url,
    String title,
    PlayType mime,
  ) {
    // dlna_dart embeds DIDL nodes directly in a string-valued SOAP argument.
    // Strict TV renderers reject that request with UPnP 716. Escape the complete
    // DIDL string once at the SOAP boundary, preserving its own XML entities.
    final xml = XmlText.setPlayURLXml(url, title: title, type: mime);
    const open = '<CurrentURIMetaData>';
    const close = '</CurrentURIMetaData>';
    final start = xml.indexOf(open) + open.length;
    final end = xml.indexOf(close, start);
    final metadata = xml.substring(start, end).trim();
    final body = xml.replaceRange(start, end, htmlEncode(metadata));
    return device.request('SetAVTransportURI', utf8.encode(body));
  }

  /// 设备在切歌/播放结束瞬间会主动关闭连接（HttpException: Connection closed
  /// before full header was received），此处带指数退避重试兜底。
  Future<void> _sendWithRetry(
    String actionName,
    DLNADevice device,
    Future<String> Function() action, {
    int retries = 3,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        dlnaLog(
          '$actionName attempt=${attempt + 1} control=${device.controlURL('AVTransport')}',
        );
        await action();
        dlnaLog('$actionName succeeded');
        return;
      } catch (error, stack) {
        dlnaLog('$actionName failed attempt=${attempt + 1}: $error\n$stack');
        if (attempt >= retries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
  }

  /// 轮询设备 transport 状态，检测当前曲播放完成。
  /// 播放中标记 _hasStartedPlaying，转为 STOPPED/NO_MEDIA 时判定为播完。
  void _startCompletionMonitor() {
    _transportTimer?.cancel();
    _transportTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final device = _activeDevice;
      final generation = _generation;
      if (device == null || _suppressCompletion) return;
      try {
        // dlna_dart 0.1.1 sends an extra MediaDuration argument, which strict
        // renderers reject with 402. GetPositionInfo only accepts InstanceID.
        final xml = await device.request(
          'GetPositionInfo',
          utf8.encode('''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
<s:Body><u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
<InstanceID>0</InstanceID></u:GetPositionInfo></s:Body></s:Envelope>'''),
        );
        if (_activeDevice == device &&
            generation == _generation &&
            !_suppressCompletion &&
            !_positionController.isClosed) {
          final position = PositionParser(xml);
          _lastPosition = Duration(seconds: position.RelTimeInt);
          _positionController.add(position);
          _pollErrors.remove('GetPositionInfo');
        }
      } catch (error) {
        _reportPollError('GetPositionInfo', device, error);
        // Position reporting is optional; transport completion still works.
      }
      try {
        final xml = await device.getTransportInfo();
        if (generation != _generation || _suppressCompletion) return;
        final transport = TransportInfoParser(xml);
        final s = transport.CurrentTransportState.toUpperCase();
        final summary = '$s status=${transport.CurrentTransportStatus}';
        if (_lastTransport != summary) {
          _lastTransport = summary;
          dlnaLog('transport device=${device.info.URLBase} state=$summary');
        }
        _pollErrors.remove('GetTransportInfo');
        // 把设备真实播放态同步给 UI（暂停也算一次真实态变化，不是播完）。
        final playing = playingFromTransport(s);
        if (playing != null) _emitPlaying(playing);
        if (s == 'PLAYING' || s == 'TRANSITIONING') {
          _hasStartedPlaying = true;
        } else if (s == 'STOPPED' || s == 'NO_MEDIA_PRESENT') {
          if (_hasStartedPlaying && !_suppressCompletion) {
            _hasStartedPlaying = false;
            if (!_completionController.isClosed) {
              _completionController.add(null);
            }
          }
        }
      } catch (error) {
        _reportPollError('GetTransportInfo', device, error);
        // 忽略设备切歌/结束瞬间的连接错误，下一轮继续
      }
    });
  }

  /// TransportState → 是否正在播放。过渡态（TRANSITIONING 等）返回 null：
  /// 此刻既不能确认起播也不能确认暂停，交由下一次探测判断。
  static bool? playingFromTransport(String state) {
    switch (state.toUpperCase()) {
      case 'PLAYING':
        return true;
      case 'PAUSED':
      case 'PAUSED_PLAYBACK':
      case 'STOPPED':
      case 'NO_MEDIA_PRESENT':
        return false;
      default:
        return null;
    }
  }

  void _emitPlaying(bool playing) {
    if (_lastPlaying == playing) return;
    _lastPlaying = playing;
    if (!_playingController.isClosed) _playingController.add(playing);
  }

  void _reportPollError(String action, DLNADevice device, Object error) {
    final message = error.toString();
    if (_pollErrors[action] == message) return;
    _pollErrors[action] = message;
    dlnaLog('$action failed device=${device.info.URLBase}: $message');
  }

  Future<void> _control(
    String action,
    Future<String> Function(DLNADevice) send, {
    String detail = '',
  }) async {
    final device = _activeDevice;
    if (device == null) return;
    try {
      final service =
          action == 'SetVolume' ? 'RenderingControl' : 'AVTransport';
      dlnaLog('$action control=${device.controlURL(service)} $detail');
      await send(device);
      dlnaLog('$action succeeded');
    } catch (error, stack) {
      dlnaLog('$action failed: $error\n$stack');
      rethrow;
    }
  }

  void _stopCompletionMonitor() {
    _transportTimer?.cancel();
    _transportTimer = null;
    _hasStartedPlaying = false;
  }

  /// 恢复播放，并**回读 TransportState 确认真的起播**。
  ///
  /// 渲染器（如 LX06 的 DMR）在 pause→play 过渡期会丢弃第一条 Play：SOAP 回 200，
  /// 但设备仍停在 PAUSED_PLAYBACK。旧实现只看 HTTP 成功就乐观翻转 UI，于是第一次
  /// 「开始」表现为无响应（图标已变播放、声音没恢复），用户得再点一次暂停+开始。
  /// 这里把「下发」升级为「下发 + 回读确认 + 补偿重发」，返回是否确认成功。
  Future<bool> play() => _toggleTransport(playing: true);

  /// 暂停，同样以设备 TransportState 确认（PAUSED*/STOPPED 视为生效）。
  Future<bool> pause() => _toggleTransport(playing: false);

  Future<bool> _toggleTransport({required bool playing}) async {
    final device = _activeDevice;
    if (device == null) return false;
    final generation = _generation;
    final action = playing ? 'Play' : 'Pause';
    for (var attempt = 1; attempt <= _transportAttempts; attempt++) {
      // 会话已换代（换设备/断开）就不再补偿，避免把命令发给新设备。
      if (_activeDevice != device || generation != _generation) return false;
      // 最后一次补偿：以最近位置 Seek 重锚后再 Play，兜底「Play 被当空操作」的渲染器。
      final anchor = playing ? _lastPosition : null;
      if (attempt == _transportAttempts &&
          anchor != null &&
          anchor > Duration.zero) {
        final sk = _formatPosition(anchor);
        await _control(
          'Seek',
          (device) => device.seek(sk),
          detail: 'position=$sk',
        );
      }
      try {
        await _control(
          action,
          (device) => playing ? device.play() : device.pause(),
        );
      } catch (error) {
        // 过渡期渲染器会主动断连接，补偿一次比把错误丢给用户更有用。
        dlnaLog('$action failed attempt=$attempt: $error');
        if (attempt == _transportAttempts) rethrow;
        await Future<void>.delayed(_verifyProbeGap);
        continue;
      }
      if (_activeDevice != device || generation != _generation) return false;
      final result = await _waitForTransport(
        device,
        playing: playing,
        generation: generation,
      );
      if (result == true) {
        _emitPlaying(playing);
        return true;
      }
      if (result == null) {
        // 设备不回报 TransportState（少数渲染器）：无从确认，按 HTTP 成功兜底，
        // 不能因为验证不了就把 UI 卡在旧状态上。
        dlnaLog('$action unverified (no transport state)');
        return true;
      }
      dlnaLog('$action not effective attempt=$attempt');
    }
    dlnaLog('$action unconfirmed after $_transportAttempts attempts');
    return false;
  }

  /// 轮询 TransportState 直到与 [playing] 一致。
  /// 返回 true = 已确认，false = 读到相反状态，null = 全程读不到状态。
  Future<bool?> _waitForTransport(
    DLNADevice device, {
    required bool playing,
    required int generation,
  }) async {
    var readable = false;
    for (var probe = 0; probe < _verifyProbes; probe++) {
      await Future<void>.delayed(_verifyProbeGap);
      if (_activeDevice != device || generation != _generation) return false;
      final state = await _readTransportState(device);
      if (state == null) continue;
      readable = true;
      if (playingFromTransport(state) == playing) return true;
    }
    return readable ? false : null;
  }

  Future<String?> _readTransportState(DLNADevice device) async {
    try {
      final xml = await device.getTransportInfo();
      return TransportInfoParser(xml).CurrentTransportState.toUpperCase();
    } catch (error) {
      _reportPollError('GetTransportInfo', device, error);
      return null;
    }
  }

  static String _formatPosition(Duration position) {
    final h = position.inHours.toString().padLeft(2, '0');
    final m = (position.inMinutes % 60).toString().padLeft(2, '0');
    final s = (position.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> stop() async {
    _stopCompletionMonitor();
    _activeDevice?.positionPoller.stop();
    await _control('Stop', (device) => device.stop());
  }

  Future<void> seek(Duration position) async {
    final sk = _formatPosition(position);
    await _control('Seek', (device) => device.seek(sk), detail: 'position=$sk');
  }

  Future<void> setVolume(int volume) => _control(
    'SetVolume',
    (device) => device.volume(volume.clamp(0, 100)),
    detail: 'volume=${volume.clamp(0, 100)}',
  );

  void disconnect() {
    ++_generation;
    _stopCompletionMonitor();
    _activeDevice?.positionPoller.stop();
    dlnaLog('disconnect device=${_activeDevice?.info.URLBase}');
    // The public API is synchronous; consume and record the async Stop failure.
    unawaited(
      _control('Stop', (device) => device.stop()).catchError((Object _) {}),
    );
    _activeDevice = null;
    _lastPosition = null;
    _lastPlaying = null; // 下次投屏重新上报真实态，不吞第一次
  }

  void dispose() {
    _stopCompletionMonitor();
    _activeDevice?.dispose();
    stopDiscovery();
    _devicesController.close();
    _positionController.close();
    _completionController.close();
    _playingController.close();
  }
}
