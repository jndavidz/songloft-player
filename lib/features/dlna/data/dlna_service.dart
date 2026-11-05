import 'dart:async';
import 'dart:convert';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import '../domain/dlna_state.dart';
import 'dlna_log.dart';

/// UPnP SOAP 错误：不少 DMR（含 LX06）即使拒绝动作也回 HTTP 200 + Fault 正文，
/// dlna_dart 只看 HTTP 码就会把「假成功」当成功，必须由业务层解析正文判失败。
class DlnaSoapFault implements Exception {
  DlnaSoapFault(this.action, this.code, this.body);

  final String action;
  final int? code;
  final String body;

  @override
  String toString() =>
      '$action SOAP fault code=${code ?? '?'} body=${soapSnippet(body)}';
}

/// SOAP 正文单行摘要（供 dlna_log 取证：用户回传日志即可看到设备真实拒绝码）。
String soapSnippet(String body, {int max = 220}) {
  final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}

/// 从 SOAP 正文提取 UPnP errorCode（`<s:Fault>` / `errorCode` 同时兼容）。
int? _soapErrorCode(String body) => int.tryParse(
  RegExp(r'<[^>]*errorCode>\s*(-?\d+)').firstMatch(body)?.group(1) ?? '',
);

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

  /// Play 的确认窗口要更宽：LX06 这类 DMR 从暂停/停机恢复到 PLAYING 常需 1s+，
  /// 用暂停的 0.9s 窗口会把「已经在恢复」误判成「Play 没生效」，进而多按一次。
  static const _playVerifyProbes = 10;

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
  String? _lastTransportState; // 最近一次读到的 TransportState（大写）
  Duration? _lastPosition; // 最近一次轮询到的播放位置，恢复兜底时用作 Seek 锚点
  Duration? _lastDuration; // 最近一次轮询到的曲目时长，用于区分「播完」与「暂停后转 STOPPED」
  bool? _lastPlaying; // 最近一次向 UI 上报的设备真实播放态（去重用）

  /// 用户主动暂停后置位，起播/投歌时清除。
  /// 部分渲染器（含 LX06 DMR）暂停会上报 STOPPED，若不区分就会被完成检测误判成
  /// 「当前曲播完」从而推进到下一首——这正是「暂停后再点播放变成下一首」的来源。
  bool _pausedByUser = false;

  /// 最近一次投送的曲目信息，起播失败且设备停在 STOPPED 时用于原地重投续播。
  String? _currentUrl;
  String? _currentTitle;
  PlayType? _currentMime;

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
    String? fallbackUrl,
  }) async {
    final generation = ++_generation;
    _pollErrors.clear();
    _lastTransport = null;
    _lastTransportState = null;
    _lastPosition = null;
    _lastDuration = null;
    _pausedByUser = false;
    _currentUrl = url;
    _currentTitle = title;
    _currentMime = mime;
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
      try {
        await _sendWithRetry(
          'SetAVTransportURI',
          device,
          () => _setUrl(device, url, title, mime),
        );
      } on Object catch (error) {
        // 只认 MP3 的渲染器（songloft-plugin-miot 虚拟接收器）用 714 拒绝 FLAC/WAV。
        // 这是语义拒绝不是网络抖动：改用调用方给的「服务端转码 MP3」URL 重投一次，
        // 并把 _currentUrl/_currentMime 换成实际生效的版本，暂停后 recast 才不会又撞 714。
        if (fallbackUrl == null || !_formatRejected(error)) rethrow;
        dlnaLog('cast format rejected ($error) -> retry fallback=$fallbackUrl');
        await _sendWithRetry(
          'SetAVTransportURI',
          device,
          () => _setUrl(device, fallbackUrl, title, AudioMime.mp3),
        );
        _currentUrl = fallbackUrl;
        _currentMime = AudioMime.mp3;
      }
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
        final response = await action();
        // 语义拒绝（Fault）重试没有意义，直接交给调用方按真实失败处理。
        _assertNoSoapFault(actionName, response);
        if (response.isNotEmpty) {
          dlnaLog('[soap] $actionName resp=${soapSnippet(response, max: 120)}');
        }
        dlnaLog('$actionName succeeded');
        return;
      } on DlnaSoapFault catch (error) {
        dlnaLog('$actionName rejected: $error');
        rethrow;
      } catch (error, stack) {
        dlnaLog('$actionName failed attempt=${attempt + 1}: $error\n$stack');
        // 714 = MIME/格式被渲染器拒绝：语义拒绝，重试只会把同一个错刷 4 次。
        if (_formatRejected(error)) rethrow;
        if (attempt >= retries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
  }

  /// 渲染器是否以「格式不支持」拒绝（UPnP 714 / 正文 Only MP3）。
  /// dlna_dart 对非 200 会把响应正文带进异常文案，因此可直接从 error 里取 errorCode。
  static bool _formatRejected(Object error) {
    final text = error.toString();
    final code = RegExp(r'<[^>]*errorCode>\s*(\d+)').firstMatch(text)?.group(1);
    return code == '714' || text.contains('Only MP3');
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
          final duration = Duration(seconds: position.TrackDurationInt);
          if (duration > Duration.zero) _lastDuration = duration;
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
        _lastTransportState = s;
        final summary = '$s status=${transport.CurrentTransportStatus}';
        if (_lastTransport != summary) {
          _lastTransport = summary;
          dlnaLog('transport device=${device.info.URLBase} state=$summary');
        }
        _pollErrors.remove('GetTransportInfo');
        // 把设备真实播放态同步给 UI（暂停也算一次真实态变化，不是播完）。
        final playing = playingFromTransport(s);
        if (playing != null) _emitPlaying(playing);
        // 设备自报在播（含 recast/重投后恢复）即清掉「用户暂停」标记，保持状态一致。
        if (playing == true) _pausedByUser = false;
        if (s == 'PLAYING' || s == 'TRANSITIONING') {
          _hasStartedPlaying = true;
        } else if (s == 'STOPPED' || s == 'NO_MEDIA_PRESENT') {
          if (_hasStartedPlaying && !_suppressCompletion) {
            _hasStartedPlaying = false;
            if (_looksLikeTrackEnd() && !_completionController.isClosed) {
              _completionController.add(null);
            } else {
              // 用户暂停导致渲染器上报 STOPPED：只同步为暂停态，不推进队列。
              dlnaLog('stop-after-pause ignored (no completion)');
            }
          }
        }
      } catch (error) {
        _reportPollError('GetTransportInfo', device, error);
        // 忽略设备切歌/结束瞬间的连接错误，下一轮继续
      }
    });
  }

  /// STOPPED / NO_MEDIA 是否真的是「当前曲播完」，而非用户暂停引起的设备停机。
  ///
  /// 用户暂停期间设备上报的停机一律不算播完（即便暂停点恰好在曲尾 5 秒内）：
  /// 暂停是显式用户意图，绝不能触发推进队列——这是「暂停后再点播放变下一首」的根因。
  /// 其余情况已知时长时以播放位置是否贴近曲尾为准（允许 2s 轮询间隔的滞后）；
  /// 时长未知（少数渲染器不回报 TrackDuration）时按播完处理。
  bool _looksLikeTrackEnd() {
    if (_pausedByUser) return false;
    final position = _lastPosition;
    final duration = _lastDuration;
    if (position != null && duration != null && duration > Duration.zero) {
      return duration - position <= const Duration(seconds: 5);
    }
    return true;
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
      final response = await send(device);
      _assertNoSoapFault(action, response);
      if (response.isNotEmpty) {
        dlnaLog('[soap] $action resp=${soapSnippet(response, max: 120)}');
      }
      dlnaLog('$action succeeded');
    } catch (error, stack) {
      dlnaLog('$action failed: $error\n$stack');
      rethrow;
    }
  }

  /// HTTP 200 + Fault 正文也判失败（大量 DMR 用这种「假成功」）；
  /// 701/710/714 等 UPnP 错误码原样带进日志，便于按机型复现。
  void _assertNoSoapFault(String action, String body) {
    if (body.isEmpty) return;
    final hasFault =
        RegExp(r'<[^>]*Fault', caseSensitive: false).hasMatch(body) ||
        _soapErrorCode(body) != null;
    if (!hasFault) return;
    throw DlnaSoapFault(action, _soapErrorCode(body), body);
  }

  void _stopCompletionMonitor() {
    _transportTimer?.cancel();
    _transportTimer = null;
    _hasStartedPlaying = false;
    _pausedByUser = false;
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

  /// 按**设备回读态**决定本次是暂停还是恢复，而不是用本地 isPlaying。
  ///
  /// 本地播放态来自 2s 轮询与投屏确认，两个来源都可能滞后/分叉；一旦本地误判为
  /// 「在播」，用户点「播放」实际下发的是 Pause——LX06 上就表现为「点播放没反应，
  /// 再点一次暂停反而继续」。这里先读设备态再定方向，返回确认后的播放态；
  /// null = 会话失效或动作未确认（UI 保持原状，下次点击重试同一意图）。
  Future<bool?> togglePlayback() async {
    final device = _activeDevice;
    if (device == null) return null;
    final state = await _readTransportState(device);
    if (_activeDevice != device) return null;
    final devicePlaying = state == null ? null : playingFromTransport(state);
    final target = !(devicePlaying ?? _lastPlaying ?? true);
    dlnaLog(
      '[toggle] device-driven target=$target deviceState=${state ?? '-'}',
    );
    if (!await _toggleTransport(playing: target)) return null;
    return target;
  }

  Future<bool> _toggleTransport({required bool playing}) async {
    final device = _activeDevice;
    if (device == null) return false;
    final generation = _generation;
    final action = playing ? 'Play' : 'Pause';
    // 一键排查日志：点击意图 + 本地态 + 设备最近上报态/位置（用户回传日志即可定位）。
    dlnaLog(
      '[toggle] intent action=$action localPlaying=$playing '
      'deviceState=${_lastTransportState ?? '-'} '
      'position=${_lastPosition ?? '-'} duration=${_lastDuration ?? '-'} '
      'pausedByUser=$_pausedByUser',
    );
    // 下发前必读设备真实态：已是目标态就不重复发（暂停态再发 Pause 会被部分
    // 渲染器当成「恢复」，正是「第二次点击才继续」的来源）。
    final readState = await _readTransportState(device);
    if (_activeDevice != device || generation != _generation) return false;
    dlnaLog('[toggle] pre-read state=${readState ?? '-'}');
    if (readState != null && playingFromTransport(readState) == playing) {
      dlnaLog('[toggle] already target state (skip $action)');
      _applyTarget(playing);
      return true;
    }
    // 用户重点怀疑 ①：本机型从 STOPPED/NO_MEDIA 接受不了普通 Play，只有重投才起得来。
    // 直接走 recast，省掉 3 次必然失败的 Play（回 200 但状态不变）。
    if (playing && readState != null && _stoppedState(readState)) {
      dlnaLog('[toggle] stopped state -> recast directly');
      final resumed = await _resumeByRecast(device, generation);
      return resumed ?? false;
    }
    for (var attempt = 1; attempt <= _transportAttempts; attempt++) {
      // 会话已换代（换设备/断开）就不再补偿，避免把命令发给新设备。
      if (_activeDevice != device || generation != _generation) return false;
      // 最后一次补偿：以最近位置 Seek 重锚后再 Play，兜底「Play 被当空操作」的渲染器。
      final anchor = playing ? _lastPosition : null;
      if (attempt == _transportAttempts &&
          anchor != null &&
          anchor > Duration.zero) {
        final sk = _formatPosition(anchor);
        try {
          await _control(
            'Seek',
            (device) => device.seek(sk),
            detail: 'position=$sk',
          );
        } catch (error) {
          // Seek 被拒（停机态渲染器常返回 701/710）不能中断 Play 补偿链，
          // 否则 recast 兜底永远没机会执行，表现为「点播放没反应」。
          dlnaLog('[toggle] seek anchor failed (continue play): $error');
        }
      }
      try {
        await _control(
          action,
          (device) => playing ? device.play() : device.pause(),
        );
      } catch (error) {
        // 过渡期渲染器会主动断连接，SOAP Fault 也在此；语义失败不抛给 UI，
        // 记日志后走 recast 兜底并如实返回 false（「假成功」绝不能当成功）。
        dlnaLog('$action failed attempt=$attempt: $error');
        if (attempt == _transportAttempts) {
          dlnaLog('$action exhausted after $_transportAttempts attempts');
          break;
        }
        await Future<void>.delayed(_verifyProbeGap);
        continue;
      }
      if (_activeDevice != device || generation != _generation) return false;
      final result = await _waitForTransport(
        device,
        playing: playing,
        generation: generation,
        probes: playing ? _playVerifyProbes : null,
      );
      if (result == true) {
        dlnaLog('[toggle] confirmed action=$action attempt=$attempt');
        _applyTarget(playing);
        return true;
      }
      if (result == null) {
        // 设备不回报 TransportState（少数渲染器）：无从确认，按 HTTP 成功兜底，
        // 不能因为验证不了就把 UI 卡在旧状态上。
        dlnaLog('$action unverified (no transport state)');
        _applyTarget(playing);
        return true;
      }
      dlnaLog(
        '[toggle] not effective action=$action attempt=$attempt '
        'deviceState=${_lastTransportState ?? '-'}',
      );
    }
    dlnaLog('$action unconfirmed after $_transportAttempts attempts');
    // 暂停让设备停机（STOPPED）后，普通 Play 可能回不来：原地重投当前曲再续播，
    // 既不跳到下一首，也不至于点了播放毫无反应。
    if (playing) {
      final resumed = await _resumeByRecast(device, generation);
      if (resumed != null) return resumed;
    }
    return false;
  }

  static bool _stoppedState(String state) =>
      state == 'STOPPED' || state == 'NO_MEDIA_PRESENT';

  void _applyTarget(bool playing) {
    _pausedByUser = !playing;
    _emitPlaying(playing);
  }

  /// 普通 Play 未被确认时，重投最近一次投送的曲目并 Seek 回原位置。
  ///
  /// 不限定设备停在哪一态：LX06 暂停后可能是 STOPPED，也可能停在 PAUSED_PLAYBACK
  /// 且丢弃第一条 Play。只要回读不是 PLAYING，重投同一 URL 都是安全幂等的；
  /// 回读已是 PLAYING 则直接按成功处理（避免把已在恢复的设备再重投一次）。
  Future<bool?> _resumeByRecast(DLNADevice device, int generation) async {
    final url = _currentUrl;
    if (url == null) return null;
    if (_activeDevice != device || generation != _generation) return null;
    final state = _lastTransportState;
    if (state == 'PLAYING') {
      dlnaLog('[toggle] recast skipped: device already PLAYING');
      _applyTarget(true);
      _hasStartedPlaying = true;
      return true;
    }
    final anchor = _lastPosition;
    try {
      dlnaLog('[toggle] recast start state=${state ?? '-'} anchor=$anchor');
      await _sendWithRetry(
        'SetAVTransportURI',
        device,
        () => _setUrl(
          device,
          url,
          _currentTitle ?? '',
          _currentMime ?? AudioMime.mp3,
        ),
      );
      await _control('Play', (device) => device.play(), detail: 'recast');
    } catch (error) {
      dlnaLog('[toggle] recast failed: $error');
      return false;
    }
    if (_activeDevice != device || generation != _generation) return false;
    final confirmed = await _waitForTransport(
      device,
      playing: true,
      generation: generation,
      probes: _playVerifyProbes,
    );
    if (confirmed == false) {
      dlnaLog(
        '[toggle] recast unconfirmed state=${_lastTransportState ?? '-'}',
      );
      return false;
    }
    // 用户重点怀疑 ②：重投后 Seek 可能被渲染器忽略（回了 200 但位置没动）。
    // 必须回读 GetPositionInfo 验证；偏差过大再补一次 Seek 并如实记录。
    if (anchor != null && anchor > Duration.zero) {
      await _seekAfterRecast(device, generation, anchor);
    }
    _applyTarget(true);
    _hasStartedPlaying = true;
    dlnaLog(
      '[toggle] recast confirmed state=${_lastTransportState ?? '-'} '
      'position=${_lastPosition ?? '-'}',
    );
    return true;
  }

  /// recast 后把播放位置拉回 [anchor]，并以 GetPositionInfo 回读验证。
  Future<void> _seekAfterRecast(
    DLNADevice device,
    int generation,
    Duration anchor,
  ) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      final target = _formatPosition(anchor);
      try {
        await _control(
          'Seek',
          (device) => device.seek(target),
          detail: 'resume position=$target attempt=$attempt',
        );
      } catch (error) {
        dlnaLog('[toggle] recast seek rejected attempt=$attempt: $error');
        return;
      }
      await Future<void>.delayed(_verifyProbeGap);
      if (_activeDevice != device || generation != _generation) return;
      final actual = await _readPositionOnce(device);
      if (actual == null) {
        dlnaLog('[toggle] recast seek unverified (no position)');
        return;
      }
      final drift = (actual - anchor).abs();
      dlnaLog(
        '[toggle] recast seek target=$target actual=${_formatPosition(actual)} '
        'drift=${drift.inSeconds}s',
      );
      // 12s 内位置本就自然前进，只有明显落后（>3s）才视为 Seek 被忽略并补发。
      if (actual + const Duration(seconds: 3) >= anchor) return;
    }
    dlnaLog('[toggle] recast seek ignored by renderer (kept playing from 0)');
  }

  /// 严格渲染器不接受 dlna_dart 的 GetPositionInfo（多送 MediaDuration → 402），
  /// 这里复用轮询同款最小 SOAP 请求，只回读当前位置。
  Future<Duration?> _readPositionOnce(DLNADevice device) async {
    try {
      final xml = await device.request(
        'GetPositionInfo',
        utf8.encode('''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
<s:Body><u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
<InstanceID>0</InstanceID></u:GetPositionInfo></s:Body></s:Envelope>'''),
      );
      final position = PositionParser(xml);
      final value = Duration(seconds: position.RelTimeInt);
      _lastPosition = value;
      return value;
    } catch (error) {
      dlnaLog('[toggle] GetPositionInfo failed: $error');
      return null;
    }
  }

  /// 轮询 TransportState 直到与 [playing] 一致。
  /// 返回 true = 已确认，false = 读到相反状态，null = 全程读不到状态。
  Future<bool?> _waitForTransport(
    DLNADevice device, {
    required bool playing,
    required int generation,
    int? probes,
  }) async {
    var readable = false;
    final count = probes ?? _verifyProbes;
    for (var probe = 0; probe < count; probe++) {
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
      final state =
          TransportInfoParser(xml).CurrentTransportState.toUpperCase();
      // 校验回读也必须刷新缓存：recast 兜底依赖 [_lastTransportState]，若只靠
      // 2s 轮询更新，暂停后立刻点「播放」时会读到过期的 PLAYING 而跳过兜底，
      // 表现为第一次点播放毫无反应、再点一次才恢复。
      _lastTransportState = state;
      return state;
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
    _lastDuration = null;
    _lastTransportState = null;
    _pausedByUser = false;
    _currentUrl = null;
    _currentTitle = null;
    _currentMime = null;
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
