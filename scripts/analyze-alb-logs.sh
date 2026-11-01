#!/bin/bash
# analyze-alb-logs.sh - Phan tich ALB access log (.log.gz) da dong bo tu S3 ve CloudShell.
#
# Cach dung:
#   ./analyze-alb-logs.sh [thu_muc_log] [tu_UTC] [den_UTC]
# Vi du:
#   mkdir -p ~/alblogs && aws s3 sync s3://ha-web-alb-logs-902534396906/alb/ ~/alblogs/ --quiet
#   ./analyze-alb-logs.sh ~/alblogs                                   # toan bo log
#   ./analyze-alb-logs.sh ~/alblogs 2026-10-24T03:15:38 2026-10-24T03:30:40   # chi cua so tai lan 2
#
# Luu y: gio trong log la UTC (gio Viet Nam = UTC + 7). Tu_UTC / den_UTC theo dang YYYY-MM-DDTHH:MM:SS.
# Cac truong dung (theo dinh dang log ALB): $2 thoi gian, $5 target:port, $7 target_processing_time,
# $9 elb_status_code, $10 target_status_code; trong dau nhay kep: request va user_agent.

DIR="${1:-$HOME/alblogs}"
FROM="${2:-}"
TO="${3:-}"
TMP=$(mktemp /tmp/alb_all.XXXXXX)
trap 'rm -f "$TMP" "$TMP".*' EXIT

if ! find "$DIR" -name '*.log.gz' | grep -q .; then
  echo "Khong tim thay file .log.gz trong $DIR"; exit 1
fi

find "$DIR" -name '*.log.gz' -exec zcat {} + \
  | awk -v f="$FROM" -v t="$TO" '(f=="" || $2>=f) && (t=="" || $2<t)' > "$TMP"

N=$(wc -l < "$TMP")
echo "=============================================="
echo " PHAN TICH ALB ACCESS LOG"
echo " Thu muc : $DIR"
echo " Cua so  : ${FROM:-(dau)} -> ${TO:-(cuoi)} (UTC)"
echo "=============================================="
echo
echo "1) TONG QUAN"
echo "  So dong log      : $N"
if [ "$N" -eq 0 ]; then echo "  Khong co du lieu trong cua so."; exit 0; fi
echo "  Dong dau (UTC)   : $(awk '{print $2}' "$TMP" | sort | head -1)"
echo "  Dong cuoi (UTC)  : $(awk '{print $2}' "$TMP" | sort | tail -1)"

echo
echo "2) MA TRANG THAI DO ALB TRA VE (elb_status_code)"
awk '{c[$9]++} END{for(k in c) printf "  %s : %d\n", k, c[k]}' "$TMP" | sort

echo
echo "3) MA TRANG THAI CUA TARGET (target_status_code, '-' = khong ghi nhan ma tu target)"
awk '{c[$10]++} END{for(k in c) printf "  %s : %d\n", k, c[k]}' "$TMP" | sort

echo
echo "4) SO REQUEST THEO PHUT (UTC) - chi in khi co chi dinh cua so thoi gian"
if [ -n "$FROM" ] && [ -n "$TO" ]; then
  awk '{c[substr($2,1,16)]++} END{for(k in c) printf "  %s : %d\n", k, c[k]}' "$TMP" | sort
else
  echo "  (bo qua: khong co cua so; so request theo gio ben duoi)"
  awk '{c[substr($2,1,13)]++} END{for(k in c) printf "  %sh : %d\n", k, c[k]}' "$TMP" | sort
fi

echo
echo "5) PHAN BO THEO TARGET (can bang tai; '-' = khong co target)"
awk '{split($5,a,":"); c[a[1]]++} END{for(k in c) printf "  %s : %d\n", k, c[k]}' "$TMP" | sort -t: -k2 -nr

echo
echo "6) USER-AGENT (top 10)"
awk -F'"' '{ua=$4; if (length(ua)>45) ua=substr(ua,1,45); c[ua]++} END{for(k in c) printf "%d\t%s\n", c[k], k}' "$TMP" \
  | sort -nr | head -10 | awk -F'\t' '{printf "  %s : %s\n", $2, $1}'

echo
echo "7) REQUEST KHONG PHAI 2xx (toi da 40 dong)"
echo "   gio(UTC) | elb | target_status | target:port | danh_sach_target | danh_sach_ma_target | user-agent"
awk -F'"' '{split($1,p," "); if (p[9] !~ /^2/) printf "  %s | %s | %s | %s | %s | %s | %s\n", p[2], p[9], p[10], p[5], $18, $20, substr($4,1,30)}' "$TMP" | sort | head -40

pct() {
  sort -n | awk '{a[NR]=$1; s+=$1}
    function idx(p,  i){ i=int(NR*p); if (i<NR*p) i++; if (i<1) i=1; return i }
    END{ if (NR==0) { print "  khong co du lieu"; exit }
      printf "  so luong: %d | trung binh: %.3fs | p50: %.3fs | p95: %.3fs | lon nhat: %.3fs\n", NR, s/NR, a[idx(0.5)], a[idx(0.95)], a[NR] }'
}

echo
echo "8) THOI GIAN XU LY CUA TARGET (target_processing_time)"
echo " - Request toi /cgi-bin/load.sh:"
grep '/cgi-bin/load.sh' "$TMP" | awk '$7>=0{print $7}' | pct
echo " - Request toi trang chu (/):"
grep -v '/cgi-bin/load.sh' "$TMP" | awk -F'"' '{split($1,p," "); if (p[7]>=0 && $2 ~ /GET http:\/\/[^\/]+\/ /) print p[7]}' | pct
echo
echo "Ghi chu: target_processing_time tinh den luc ALB nhan byte dau tien cua phan hoi,"
echo "so voi thoi gian tong do ab/curl do duoc cho /cgi-bin/load.sh."
