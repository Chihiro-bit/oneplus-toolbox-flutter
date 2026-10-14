D=/data/local/tmp/oneplus-toolbox
IMG=$D/init_boot.img
cd $D || exit 1
rm -rf root ksu-out out.img && mkdir root
unzip -o root.apk -d root >/dev/null 2>&1 || { echo "解压 APK 失败"; exit 2; }
cd root/assets || exit 2
for f in ../lib/arm64-v8a/lib*.so; do n=${f##*/lib}; cp "$f" "./${n%.so}"; done
chmod 755 *
[ -f ../lib/armeabi-v7a/libmagisk32.so ] && cp ../lib/armeabi-v7a/libmagisk32.so ./magisk32 && chmod 755 magisk32
SAR=false; grep -q " /system_root " /proc/mounts && SAR=true; grep " / " /proc/mounts | grep -qv rootfs && SAR=true
ENC=false; [ "$(getprop ro.crypto.state)" = "encrypted" ] && ENC=true
VB=false; ls /dev/block/by-name/vbmeta* >/dev/null 2>&1 || VB=true
export KEEPVERITY=$SAR KEEPFORCEENCRYPT=$ENC PATCHVBMETAFLAG=$VB RECOVERYMODE=false
echo "KEEPVERITY=$SAR KEEPFORCEENCRYPT=$ENC PATCHVBMETAFLAG=$VB"
sh ./boot_patch.sh "$IMG" || exit 3
mv new-boot.img $D/out.img || exit 4
[ -s $D/out.img ] || exit 5
echo PATCH_OK
