/// 受管渲染端识别（CCH / LX06）。
///
/// ADR-0001（open-xiaoai）：已托管 renderer 只接受 managed 路径投送，
/// 手机 App 的原生 DLNA 直投不得指向这些端点——否则绕开票据/代次管理，
/// 制造第二控制面并与 bridge 仲裁竞速。
///
/// 判据用 SSDP 发现得到的 `location`（含设备 IP），不靠用户可改的设备名。
/// 名单可配置（预留未来新增受管设备），默认值来自设备事实层：
///   - LX06  10.10.10.20
///   - CCH   10.10.10.25
library;

/// 默认受管设备 IP（事实层已定的固定局域网地址）。
const List<String> defaultManagedDeviceHosts = ['10.10.10.20', '10.10.10.25'];

/// 从 SSDP location 中解析主机名/IP；解析失败返回 null。
String? hostFromLocation(String location) {
  final uri = Uri.tryParse(location);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.host;
}

/// 该设备是否已托管（不得原生 DLNA 直投）。
///
/// 纯函数、无状态、无 IO——便于单测与未来扩展名单来源。
bool isManagedDevice(String location, [List<String>? hosts]) {
  final host = hostFromLocation(location);
  if (host == null) return false;
  final list = hosts ?? defaultManagedDeviceHosts;
  return list.any((h) => h.toLowerCase() == host.toLowerCase());
}

/// 受管设备直投被拒时的用户可见提示。
const String managedDeviceCastBlocked =
    '该音箱已由家庭中枢托管，请通过语音点播（不经手机直投），以避免播放冲突。';
