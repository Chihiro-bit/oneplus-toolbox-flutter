A=/data/local/tmp/oneplus-toolbox/aapt2
chmod 755 $A
i=0
for e in $(pm list packages -3 -f | sed "s/^package://"); do
  p=${e##*=}; path=${e%=*}
  (
    b=$($A d badging "$path" 2>/dev/null | grep -E "^application-(label(-zh-CN)?|icon-(160|240|320|480)):")
    l=$(echo "$b" | grep "^application-label-zh-CN:" | head -n 1 | sed "s/^[^:]*:'\(.*\)'$/\1/")
    [ -z "$l" ] && l=$(echo "$b" | grep "^application-label:" | head -n 1 | sed "s/^[^:]*:'\(.*\)'$/\1/")
    ic=""
    for d in 240 320 160 480; do
      c=$(echo "$b" | grep "^application-icon-$d:" | head -n 1 | sed "s/^[^:]*:'\(.*\)'$/\1/")
      case "$c" in *.png|*.webp|*.jpg) ic=$c; break;; esac
    done
    echo "APP|$p|$path|$ic|$l"
  ) &
  i=$((i + 1)); [ $((i % 8)) -eq 0 ] && wait
done
wait
for p in $(pm list packages -3 -d --user 0 | sed "s/package://"); do echo "DISABLED|$p"; done