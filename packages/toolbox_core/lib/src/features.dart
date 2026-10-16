/// 功能开关。
///
/// 9008 救砖：新系统上免授权 EDL 已被熔断，而散包、编程器一旦用错就会写坏分区，
/// 风险远大于收益，先整体关闭（隐藏入口，业务层也拒绝执行）。代码保留，之后评估再决定是否恢复。
///
/// 对应 TS 版的 `FEATURES`（src/shared/features.ts）。
abstract final class Features {
  static const edl = false;
}
