D=/data/local/tmp/oneplus-toolbox
IMG=$D/init_boot.img
cd $D || exit 1
rm -rf root ksu-out out.img && mkdir root
unzip -o root.apk -d root >/dev/null 2>&1 || { echo "解压 APK 失败"; exit 2; }
cd root || exit 2
cp lib/arm64-v8a/libksud.so ./ksud && chmod 755 ksud || { echo "APK 中没有 ksud"; exit 2; }
mkdir -p $D/ksu-out
./ksud boot-patch -b "$IMG" -o $D/ksu-out
if ! ls $D/ksu-out/*.img >/dev/null 2>&1; then
  case "$(getprop ro.product.first_api_level)" in 32) AV=android12;; 33) AV=android13;; 34) AV=android14;; 35|202404) AV=android15;; 36) AV=android16;; esac
  KV=$(uname -r | cut -d. -f1,2)
  [ -n "$AV" ] && { echo "使用 KMI $AV-$KV 重试"; ./ksud boot-patch -b "$IMG" -o $D/ksu-out --kmi "$AV-$KV"; }
fi
P=$(ls $D/ksu-out/*.img 2>/dev/null | head -n 1)
[ -n "$P" ] || { echo "修补失败：设备可能不是 GKI 2.0，或 KMI 不受支持"; exit 3; }
mv "$P" $D/out.img || exit 4
[ -s $D/out.img ] || exit 5
echo PATCH_OK
