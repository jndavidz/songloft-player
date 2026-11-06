import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

/// 播放页歌词字号档位（唱盘下两行 + 独立歌词页共用）。
///
/// 纯本地偏好：不参与服务器偏好同步；默认 [PlayerLyricFontSize.medium]，
/// 即唱盘下 17、独立歌词页当前行 20（比旧版 15/18 各调大一档）。
enum PlayerLyricFontSize { small, medium, large }

extension PlayerLyricFontSizeX on PlayerLyricFontSize {
  /// 唱盘下两行歌词字号。
  double get compactSize {
    switch (this) {
      case PlayerLyricFontSize.small:
        return 15;
      case PlayerLyricFontSize.medium:
        return 17;
      case PlayerLyricFontSize.large:
        return 20;
    }
  }

  /// 独立歌词页当前行字号。
  double get fullCurrentSize {
    switch (this) {
      case PlayerLyricFontSize.small:
        return 18;
      case PlayerLyricFontSize.medium:
        return 20;
      case PlayerLyricFontSize.large:
        return 23;
    }
  }

  /// 独立歌词页非当前行字号。
  double get fullOtherSize {
    switch (this) {
      case PlayerLyricFontSize.small:
        return 15;
      case PlayerLyricFontSize.medium:
        return 17;
      case PlayerLyricFontSize.large:
        return 20;
    }
  }

  String get storageValue {
    switch (this) {
      case PlayerLyricFontSize.small:
        return 'small';
      case PlayerLyricFontSize.medium:
        return 'medium';
      case PlayerLyricFontSize.large:
        return 'large';
    }
  }

  static PlayerLyricFontSize fromStorageValue(String value) {
    switch (value) {
      case 'small':
        return PlayerLyricFontSize.small;
      case 'large':
        return PlayerLyricFontSize.large;
      case 'medium':
      default:
        return PlayerLyricFontSize.medium;
    }
  }
}

class PlayerLyricFontSizeNotifier extends Notifier<PlayerLyricFontSize> {
  @override
  PlayerLyricFontSize build() {
    _load();
    return PlayerLyricFontSize.medium;
  }

  Future<void> _load() async {
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      state = PlayerLyricFontSizeX.fromStorageValue(
        prefs.getPlayerLyricFontSize(),
      );
    } catch (_) {
      state = PlayerLyricFontSize.medium;
    }
  }

  Future<void> setFontSize(PlayerLyricFontSize value) async {
    state = value;
    try {
      final prefs = await ref.read(appPreferencesProvider.future);
      await prefs.setPlayerLyricFontSize(value.storageValue);
    } catch (_) {}
  }
}

final playerLyricFontSizeProvider =
    NotifierProvider<PlayerLyricFontSizeNotifier, PlayerLyricFontSize>(
      PlayerLyricFontSizeNotifier.new,
    );
