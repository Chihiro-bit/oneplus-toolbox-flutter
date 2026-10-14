D=/data/local/tmp/oneplus-toolbox
IMG=$D/boot.img
cd $D || exit 1
rm -rf root ksu-out out.img && mkdir root
unzip -o root.apk -d root >/dev/null 2>&1 || { echo "解压 APK 失败"; exit 2; }
cd root/assets || exit 2
for f in ../lib/arm64-v8a/lib*.so; do n=${f##*/lib}; cp "$f" "./${n%.so}"; done
chmod 755 *
sh ./boot_patch.sh 'abc123XY' "$IMG" || exit 3
[ -s new-boot.img ] || { echo "APatch 未生成修补后的镜像，原因见上方输出"; exit 4; }
mv new-boot.img $D/out.img || exit 4
[ -s $D/out.img ] || exit 5
echo PATCH_OK
