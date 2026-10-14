import 'package:toolbox_core/toolbox_core.dart';

/// 手机上本工具专用的临时目录
const remoteDir = '/data/local/tmp/oneplus-toolbox';

/// 单引号转义，用于拼接手机端 shell 脚本
String shq(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// 修补脚本成功时输出的标记
const patchOkMarker = 'PATCH_OK';

/// 生成在手机上执行的修补脚本。三种方式都只使用 APK 自带的官方工具：
/// - magisk：解出 lib*.so 改名后运行 Magisk 的 boot_patch.sh（兼容 26.x 与 30.x 的库布局）
/// - apatch：运行 APatch 的 boot_patch.sh <superkey> <boot>
/// - ksu：运行 ksud boot-patch，失败后按 first_api_level + 内核版本推出 KMI 重试
///
/// 约定：`$D/root.apk` 和 `$D/<img>` 已推送到位。成功时把结果放到 `$D/out.img` 并输出 [patchOkMarker]。
String patchScript(RootFamily family, String img, {String? superkey}) {
  final head = [
    'D=$remoteDir',
    'IMG=\$D/$img',
    r'cd $D || exit 1',
    'rm -rf root ksu-out out.img && mkdir root',
    'unzip -o root.apk -d root >/dev/null 2>&1 || { echo "解压 APK 失败"; exit 2; }',
  ];
  const unpackLibs = [
    r'for f in ../lib/arm64-v8a/lib*.so; do n=${f##*/lib}; cp "$f" "./${n%.so}"; done',
    'chmod 755 *',
  ];
  final body = switch (family) {
    RootFamily.magisk => [
        'cd root/assets || exit 2',
        ...unpackLibs,
        '[ -f ../lib/armeabi-v7a/libmagisk32.so ] && cp ../lib/armeabi-v7a/libmagisk32.so ./magisk32 && chmod 755 magisk32',
        // 与 Magisk App 的判断一致：system-as-root 时保留 verity，数据加密时保留强制加密
        'SAR=false; grep -q " /system_root " /proc/mounts && SAR=true; grep " / " /proc/mounts | grep -qv rootfs && SAR=true',
        r'ENC=false; [ "$(getprop ro.crypto.state)" = "encrypted" ] && ENC=true',
        'VB=false; ls /dev/block/by-name/vbmeta* >/dev/null 2>&1 || VB=true',
        r'export KEEPVERITY=$SAR KEEPFORCEENCRYPT=$ENC PATCHVBMETAFLAG=$VB RECOVERYMODE=false',
        r'echo "KEEPVERITY=$SAR KEEPFORCEENCRYPT=$ENC PATCHVBMETAFLAG=$VB"',
        r'sh ./boot_patch.sh "$IMG" || exit 3',
        r'mv new-boot.img $D/out.img || exit 4',
      ],
    RootFamily.apatch => [
        'cd root/assets || exit 2',
        ...unpackLibs,
        'sh ./boot_patch.sh ${shq(superkey ?? '')} "\$IMG" || exit 3',
        // boot_patch.sh 在镜像无效或内核未开启 CONFIG_KALLSYMS 时也会以 0 退出，所以要看有没有产物
        '[ -s new-boot.img ] || { echo "APatch 未生成修补后的镜像，原因见上方输出"; exit 4; }',
        r'mv new-boot.img $D/out.img || exit 4',
      ],
    RootFamily.ksu => [
        'cd root || exit 2',
        'cp lib/arm64-v8a/libksud.so ./ksud && chmod 755 ksud || { echo "APK 中没有 ksud"; exit 2; }',
        r'mkdir -p $D/ksu-out',
        r'./ksud boot-patch -b "$IMG" -o $D/ksu-out',
        r'if ! ls $D/ksu-out/*.img >/dev/null 2>&1; then',
        r'  case "$(getprop ro.product.first_api_level)" in 32) AV=android12;; 33) AV=android13;; 34) AV=android14;; 35|202404) AV=android15;; 36) AV=android16;; esac',
        r'  KV=$(uname -r | cut -d. -f1,2)',
        r'  [ -n "$AV" ] && { echo "使用 KMI $AV-$KV 重试"; ./ksud boot-patch -b "$IMG" -o $D/ksu-out --kmi "$AV-$KV"; }',
        'fi',
        r'P=$(ls $D/ksu-out/*.img 2>/dev/null | head -n 1)',
        r'[ -n "$P" ] || { echo "修补失败：设备可能不是 GKI 2.0，或 KMI 不受支持"; exit 3; }',
        r'mv "$P" $D/out.img || exit 4',
      ],
  };
  return '${[...head, ...body, r'[ -s $D/out.img ] || exit 5', 'echo $patchOkMarker'].join('\n')}\n';
}
