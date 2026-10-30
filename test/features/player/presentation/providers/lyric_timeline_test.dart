import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/core/audio/audio_service.dart';
import 'package:songloft_flutter/core/storage/lyric_cache_service.dart';
import 'package:songloft_flutter/features/dlna/domain/dlna_state.dart';
import 'package:songloft_flutter/features/dlna/presentation/providers/dlna_provider.dart';
import 'package:songloft_flutter/features/player/domain/player_state.dart';
import 'package:songloft_flutter/features/player/presentation/providers/lyric_provider.dart';
import 'package:songloft_flutter/features/player/presentation/providers/player_provider.dart';
import 'package:songloft_flutter/features/settings/presentation/providers/settings_provider.dart';
import 'package:songloft_flutter/main.dart';
import 'package:songloft_flutter/shared/models/song.dart';

const _lyricUrl = '/api/v1/songs/1/lyric';

class _Audio implements SongloftAudioHandler {
  @override
  void updateNowPlayingLyric(String lyricLine, {bool inTitle = true}) {}
  @override
  void restoreNowPlaying() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Player extends PlayerNotifier {
  @override
  PlayerState build() => PlayerState(
    currentSong: Song.fromJson({
      'id': 1,
      'title': '歌曲',
      'url': '/songs/1/play',
      'lyric_url': _lyricUrl,
      'updated_at': '2026-01-01T00:00:00.000Z',
    }),
    isPlaying: false,
    duration: const Duration(minutes: 3),
  );
}

class _Casting extends DlnaNotifier {
  @override
  DlnaState build() => const DlnaState(isCasting: true, isPlaying: true);

  void moveTo(Duration position) =>
      state = state.copyWith(position: position, isPlaying: true);
}

/// 通知栏歌词开关只做本地偏好读取，测试里固定为默认值以免依赖 SharedPreferences。
class _LyricInTitle extends NotificationLyricInTitleNotifier {
  @override
  bool build() => true;
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition not met in time');
}

void main() {
  // LyricCacheService 会尝试用 path_provider 定位缓存目录；无插件时内部已兜底到内存缓存，
  // 但需要先初始化 binding 才不至于抛未初始化异常。
  TestWidgetsFlutterBinding.ensureInitialized();

  test('投屏时歌词时间轴跟随远端进度，而不是冻结的本机进度', () async {
    final song = Song.fromJson({
      'id': 1,
      'title': '歌曲',
      'url': '/songs/1/play',
      'lyric_url': _lyricUrl,
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    // 预置歌词缓存，避免歌词 provider 走网络。
    await LyricCacheService().put(
      _lyricUrl,
      jsonEncode({'lyric': '[00:00.000]第一行\n[00:05.000]第二行\n[00:10.000]第三行'}),
      songUpdatedAt: song.updatedAt.toIso8601String(),
    );

    final container = ProviderContainer(
      overrides: [
        playerStateProvider.overrideWith(_Player.new),
        dlnaStateProvider.overrideWith(_Casting.new),
        audioHandlerProvider.overrideWithValue(_Audio()),
        notificationLyricInTitleProvider.overrideWith(_LyricInTitle.new),
      ],
    );
    addTearDown(container.dispose);

    await _waitFor(() => container.read(lyricStateProvider).hasLyrics);
    expect(container.read(lyricStateProvider).currentIndex, 0);

    // 投屏开始：本机播放器被 pauseLocal 冻结在 0，远端已经播到 6s。
    final casting = container.read(dlnaStateProvider.notifier) as _Casting;
    casting.moveTo(const Duration(seconds: 6));
    await pumpEventQueue();

    expect(container.read(playerStateProvider).currentTime, Duration.zero);
    expect(container.read(lyricStateProvider).currentIndex, 1);

    casting.moveTo(const Duration(seconds: 11));
    await pumpEventQueue();
    expect(container.read(lyricStateProvider).currentIndex, 2);
  });
}
