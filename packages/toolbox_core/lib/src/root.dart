/// [DeviceInfo.root] / [BootState.root] 表示已经拿到 Root
/// （「未 Root」「未检测到（装有 … App）」都不算）。
///
/// 对应 TS 版的 src/shared/root.ts。
bool isRooted(String? root) => root != null && root.isNotEmpty && root != '未 Root' && !root.startsWith('未检测到');
