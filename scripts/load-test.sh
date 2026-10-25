#!/bin/bash
# load-test.sh - Tao tai that len ALB va ghi lai thoi gian scale-out / scale-in.
# Chay trong AWS CloudShell (us-east-1).
# Cach dung: ./load-test.sh <ALB-DNS> [thoi_gian_tai_giay=600] [so_luong_worker=20] [theo_doi_them_giay=1200]
#
# - Moi worker goi lap lai http://<ALB-DNS>/cgi-bin/load.sh (moi request ~1 giay CPU).
# - Song song, cu 15 giay ghi 1 dong vao file CSV: gio, desired, in-service, healthy, CPU trung binh.
# - Sau khi dung tai van theo doi them de thay scale-in.
# Gio ghi theo mui gio +07:00 de khop Activity history tren console.

ALB="$1"
DUR="${2:-600}"
WORKERS="${3:-20}"
EXTRA="${4:-1200}"
ASG="HA-Web-ASG"
TG_NAME="HA-Web-TG"
INTERVAL=15
export TZ="Asia/Ho_Chi_Minh"

if [ -z "$ALB" ]; then
  echo "Dung: $0 <ALB-DNS> [thoi_gian_tai=600] [worker=20] [theo_doi_them=1200]"
  exit 1
fi

TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
STAMP=$(date +%Y%m%d_%H%M%S)
CSV="scaling_log_${STAMP}.csv"
REQ="requests_${STAMP}.log"
echo "time,desired,inservice,healthy_targets,avg_cpu" > "$CSV"
: > "$REQ"

T_START=$(date +%s)
T_LOAD_END=$((T_START + DUR))
T_MON_END=$((T_LOAD_END + EXTRA))
echo "T0 (bat dau tai): $(date +%T)  | worker=$WORKERS | tai=${DUR}s | theo doi them=${EXTRA}s"
echo "File log: $CSV, $REQ"

worker() {
  while [ "$(date +%s)" -lt "$T_LOAD_END" ]; do
    curl -s -o /dev/null --max-time 60 -w "%{http_code} %{time_total}\n" \
      "http://${ALB}/cgi-bin/load.sh" >> "$REQ"
  done
}

for i in $(seq 1 "$WORKERS"); do worker & done

sample() {
  local D N H CPU
  read -r D N < <(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG" \
    --query 'AutoScalingGroups[0].[DesiredCapacity, length(Instances[?LifecycleState==`InService`])]' \
    --output text)
  H=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)
  CPU=$(aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization \
    --dimensions Name=AutoScalingGroupName,Value="$ASG" \
    --start-time "$(date -u -d '-4 minutes' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 60 --statistics Average \
    --query 'sort_by(Datapoints,&Timestamp)[-1].Average' --output text)
  echo "$(date +%T),${D},${N},${H},${CPU}" | tee -a "$CSV"
}

while [ "$(date +%s)" -lt "$T_MON_END" ]; do
  sample
  sleep "$INTERVAL"
done
wait

echo
echo "===== TOM TAT ====="
echo "T0 (bat dau tai)            : $(date -d @"$T_START" +%T)"
echo "Ket thuc tai                : $(date -d @"$T_LOAD_END" +%T)"
awk -F, 'NR>1 {
  if (h0 == "") h0 = $4;
  if (!t1 && $5+0 > 50) t1 = $1;
  if (!t3 && $2+0 > d0 && d0 != "") t3 = $1;
  if (d0 == "") d0 = $2;
  if (!t4 && h0 != "" && $4+0 > h0+0) t4 = $1;
  if ($3+0 > mx) { mx = $3+0; tmx = $1 }
  if (t4 && !t8 && $3+0 < mx) t8 = $1;
} END {
  print "Lan dau CPU > 50%            : " (t1 ? t1 : "khong thay");
  print "Lan dau desired tang         : " (t3 ? t3 : "khong thay");
  print "Lan dau healthy tang (ready) : " (t4 ? t4 : "khong thay");
  print "So instance in-service lon nhat: " mx " (luc " tmx ")";
  print "Lan dau in-service giam      : " (t8 ? t8 : "khong thay");
}' "$CSV"
awk '{ n++; if ($1 != 200) e++; s += $2; if ($2 > m) m = $2 }
  END { printf "Tong request: %d | khac 200: %d | thoi gian TB: %.2fs | lon nhat: %.2fs\n", n, e, (n ? s/n : 0), m }' "$REQ"
echo "Doi chieu gio chinh xac voi ASG -> Activity va CloudWatch -> Alarms."
