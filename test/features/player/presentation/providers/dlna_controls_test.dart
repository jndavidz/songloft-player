import 'dart:async';

import 'package:dlna_dart/xmlParser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/core/audio/audio_service.dart';
import 'package:songloft_flutter/features/dlna/data/dlna_service.dart';
import 'package:songloft_flutter/features/dlna/domain/dlna_state.dart';
import 'package:songloft_flutter/features/dlna/presentation/providers/dlna_provider.dart';
import 'package:songloft_flutter/features/player/domain/player_state.dart';
import 'package:songloft_flutter/features/player/presentation/providers/player_provider.dart';
import 'package:songloft_flutter/main.dart';
import 'package:songloft_flutter/shared/models/song.dart';

class _Player extends PlayerNotifier {
  @override
  PlayerState build() => PlayerState(
    currentSong: Song.fromJson({
      'id': 1,
      'title': '歌曲',
      'url': '/songs/1/play',
    }),
    isPlaying: false,
    duration: const Duration(minutes: 3),
  );
}

class _Casting extends DlnaNotifier {
  @override
  DlnaState build() => const DlnaState(
    isCasting: true,
    isPlaying: true,
    position: Duration(seconds: 12),
    duration: Duration(minutes: 4),
  );

  void endSession() => state = const DlnaState();
}

class _Audio implements SongloftAudioHandler {
  @override
  Future<void> pause() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Service extends DlnaService {
  final commands = <String>[];
  final _playing = StreamController<bool>.broadcast();
  bool confirm = true;

  @override
  Stream<bool> get playingStream => _playing.stream;

  void deviceReported(bool playing) => _playing.add(playing);

  @override
  Future<void> castTo(
    String deviceId,
    String url, {
    String title = '',
    PlayType mime = AudioMime.mp3,
  }) async => commands.add('cast:${title.isEmpty ? url : title}');

  @override
  Future<bool> pause() async {
    commands.add('pause');
    return confirm;
  }

  @override
  Future<bool> play() async {
    commands.add('play');
    return confirm;
  }

  @override
  Future<void> seek(Duration position) async =>
      commands.add('seek:${position.inSeconds}');
  @override
  Future<void> setVolume(int volume) async => commands.add('volume:$volume');
}

void main() {
  late ProviderContainer container;
  late _Service service;
  setUp(() {
    service = _Service();
    container = ProviderContainer(
      overrides: [
        playerStateProvider.overrideWith(_Player.new),
        dlnaStateProvider.overrideWith(_Casting.new),
        dlnaServiceProvider.overrideWithValue(service),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    service.dispose();
  });

  test('主播放器暂停和继续发给投屏设备，图标读取远端状态', () async {
    final player = container.read(playerStateProvider.notifier);
    expect(container.read(playerStateProvider).isPlaying, isFalse);
    expect(container.read(activePlaybackStateProvider).isPlaying, isTrue);
    await player.togglePlay();
    expect(service.commands, ['pause']);
    expect(container.read(activePlaybackStateProvider).isPlaying, isFalse);
    await player.togglePlay();
    expect(service.commands, ['pause', 'play']);
    expect(container.read(activePlaybackStateProvider).isPlaying, isTrue);
  });

  test('投屏时进度、快进和音量使用远端控制', () async {
    final player = container.read(playerStateProvider.notifier);
    expect(
      container.read(activePlaybackStateProvider).currentTime,
      const Duration(seconds: 12),
    );
    expect(
      container.read(activePlaybackStateProvider).duration,
      const Duration(minutes: 4),
    );
    await player.seekBy(const Duration(seconds: 10));
    await player.setVolume(35);
    expect(service.commands, ['seek:22', 'volume:35']);
  });

  test('断开后界面恢复本地播放状态', () {
    final local = container.read(playerStateProvider);
    container.read(dlnaStateProvider);
    (container.read(dlnaStateProvider.notifier) as _Casting).endSession();
    expect(container.read(activePlaybackStateProvider), same(local));
  });

  test('快速连点按顺序暂停再恢复远端', () async {
    final player = container.read(playerStateProvider.notifier);
    await Future.wait([player.togglePlay(), player.togglePlay()]);
    expect(service.commands, ['pause', 'play']);
    expect(container.read(activePlaybackStateProvider).isPlaying, isTrue);
  });

  test('恢复未被设备确认时不翻转图标，下一次点击仍下发恢复', () async {
    final player = container.read(playerStateProvider.notifier);
    await player.togglePlay(); // 暂停成功
    expect(container.read(activePlaybackStateProvider).isPlaying, isFalse);

    service.confirm = false; // 设备丢弃第一条 Play（过渡期）
    await player.togglePlay();
    expect(service.commands, ['pause', 'play']);
    // 图标仍显示「播放」，再点一次继续下发 play，而不是翻转成 pause
    expect(container.read(activePlaybackStateProvider).isPlaying, isFalse);
    await player.togglePlay();
    expect(service.commands, ['pause', 'play', 'play']);
  });

  test('投屏时设备回推的真实播放态纠正 UI', () async {
    final castingContainer = ProviderContainer(
      overrides: [
        playerStateProvider.overrideWith(_Player.new),
        dlnaStateProvider.overrideWith(_Casting.new),
        dlnaServiceProvider.overrideWithValue(service),
        audioHandlerProvider.overrideWithValue(_Audio()),
      ],
    );
    addTearDown(castingContainer.dispose);
    final notifier =
        castingContainer.read(dlnaStateProvider.notifier) as _Casting;

    await notifier.castToDevice(
      const DlnaDeviceInfo(
        id: 'renderer',
        name: '音箱',
        location: 'http://192.168.2.111:9999',
      ),
    );
    expect(notifier.state.isPlaying, isTrue);

    // 设备其实没在播（例如丢弃了 Play）：轮询把它纠正回来
    service.deviceReported(false);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.isPlaying, isFalse);
  });
}
