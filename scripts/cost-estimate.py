#!/usr/bin/env python3
"""cost-estimate.py - Uoc tinh chi phi EC2 / ALB / S3 cua de tai (chay duoc trong CloudShell hoac may ca nhan).

Cach dung:
  1) Lay lich su hoat dong cua ASG:
       aws autoscaling describe-scaling-activities --auto-scaling-group-name HA-Web-ASG \
           --max-items 500 > activities.json
  2) Sua phan "CAU HINH" ben duoi cho dung thuc te (cac khoang chay ALB, instance ngoai ASG, don gia).
  3) Chay:
       python3 cost-estimate.py activities.json [--tu 2026-10-19]

Ket qua la UOC TINH tu cac moc thoi gian da ghi; so lieu that nam o trang Learner Lab ("Used $x of $50").
Don gia chi la gia tham khao (us-east-1), can doi chieu lai tren trang gia AWS truoc khi nop.
"""
import argparse
import json
import math
import re
import sys
from datetime import datetime, timedelta, timezone

VN = timezone(timedelta(hours=7))

# ----------------------------- CAU HINH -----------------------------
PRICES = {
    "alb_hour": 0.0225,         # ALB, USD / gio (moi gio le tinh tron 1 gio)
    "lcu_hour": 0.008,          # USD / LCU-gio (mac dinh bo qua vi luu luong nho, xem LCU_PER_HOUR)
    "ipv4_hour": 0.005,         # USD / gio cho moi dia chi public IPv4
    "ec2_hour": 0.0104,         # t3.micro Linux, USD / gio (gia niem yet luc ra mat T3, can doi chieu)
    "ebs_gb_month": 0.08,       # gp3, USD / GB-thang (can doi chieu)
    "s3_gb_month": 0.023,       # S3 Standard, USD / GB-thang (can doi chieu)
}
LCU_PER_HOUR = 0.0            # dat > 0 neu muon tinh LCU (vi du 1.0 trong luc co tai)
ALB_IPV4_PER_ALB = 2          # ALB 2 AZ giu 2 dia chi IPv4 (gia dinh)
EC2_IPV4_PER_INSTANCE = 1     # instance o public subnet co 1 public IPv4
EBS_GB_PER_INSTANCE = 8       # o dia goc cua AMI Amazon Linux 2023 (gia dinh 8 GB)
S3_GB_STORED = 0.001          # dung luong log tren S3 (GB); xem: aws s3 ls --summarize --recursive

# Cac khoang thoi gian ALB chay (gio Viet Nam, dang "YYYY-MM-DD HH:MM"). Dat None neu chua biet.
ALB_INTERVALS = [
    ("ALB tuan 3 (qua dem 23-24/10)", "2026-10-23 22:37", "2026-10-24 10:56"),
    ("ALB toi 24/10 (ngay 4 tuan 3)", None, "2026-10-24 20:22"),          # SUA: gio tao ALB
    ("ALB do CloudFormation tao (24/10)", "2026-10-24 20:59", "2026-10-24 21:08"),
    ("ALB tuan 4 - ngay 1 (29/10)", None, "2026-10-29 19:58"),             # SUA: gio tao ALB (lay tu CloudTrail)
    # ("ALB tuan 4 - ngay 4 (quay video)", "2026-11-01 hh:mm", "2026-11-01 hh:mm"),   # THEM cac buoi sau
]

# Instance khong nam trong ASG HA-Web-ASG (vi du instance cua stack CloudFormation da bi xoa cung ASG).
EXTRA_INSTANCES = [
    ("i-0469467cb05ac9f26 (stack CFN)", "2026-10-24 21:01", "2026-10-24 21:08"),
]
# --------------------------------------------------------------------


def parse_aws_time(s):
    s = s.strip().replace("Z", "+00:00")
    m = re.match(r"^(.*?T\d\d:\d\d:\d\d)(\.\d+)?(\+\d\d:\d\d)?$", s)
    if not m:
        raise ValueError("khong doc duoc thoi gian: " + s)
    base, frac, tz = m.group(1), m.group(2) or "", m.group(3) or "+00:00"
    frac = (frac + "000000")[:7] if frac else ""
    return datetime.fromisoformat(base + frac + tz)


def parse_vn(s):
    return datetime.strptime(s, "%Y-%m-%d %H:%M").replace(tzinfo=VN)


def instance_lifetimes(activities, since):
    launch, kill = {}, {}
    for a in activities:
        desc = a.get("Description", "")
        m = re.search(r"(i-[0-9a-f]+)", desc)
        if not m:
            continue
        iid = m.group(1)
        t = parse_aws_time(a["StartTime"])
        if desc.startswith("Launching"):
            launch[iid] = t
        elif desc.startswith("Terminating"):
            kill[iid] = t
    rows = []
    now = datetime.now(timezone.utc)
    for iid, t0 in launch.items():
        if since and t0 < since:
            continue
        t1 = kill.get(iid)
        still = t1 is None
        t1 = t1 or now
        rows.append((iid, t0, t1, still))
    return sorted(rows, key=lambda r: r[1])


def fmt(t):
    return t.astimezone(VN).strftime("%d/%m %H:%M")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("activities", help="file JSON tu aws autoscaling describe-scaling-activities")
    ap.add_argument("--tu", default="2026-10-19", help="chi tinh instance khoi tao tu ngay nay (gio VN, YYYY-MM-DD)")
    ap.add_argument("--ebs", action="store_true", help="tinh them phi EBS")
    args = ap.parse_args()

    since = datetime.strptime(args.tu, "%Y-%m-%d").replace(tzinfo=VN)
    data = json.load(open(args.activities))
    acts = data.get("Activities", data if isinstance(data, list) else [])
    rows = instance_lifetimes(acts, since)

    print("=" * 66)
    print(" UOC TINH CHI PHI (USD) - tu %s" % args.tu)
    print("=" * 66)

    # ---- EC2 ----
    print("\n1) EC2 t3.micro (tinh theo giay, lam tron khi in)")
    ec2_hours = 0.0
    for iid, t0, t1, still in rows:
        h = (t1 - t0).total_seconds() / 3600
        ec2_hours += h
        print("  %-22s %s -> %s  %6.2f gio%s" % (iid, fmt(t0), fmt(t1), h, "  (CHUA terminate: tinh den bay gio)" if still else ""))
    for name, a, b in EXTRA_INSTANCES:
        if parse_vn(b) <= since:      # chi tinh instance ket thuc sau ngay --tu
            continue
        h = (parse_vn(b) - parse_vn(a)).total_seconds() / 3600
        ec2_hours += h
        print("  %-22s %s -> %s  %6.2f gio  (them tay)" % (name[:22], a[5:], b[5:], h))
    ec2 = ec2_hours * PRICES["ec2_hour"]
    ipv4_ec2 = ec2_hours * EC2_IPV4_PER_INSTANCE * PRICES["ipv4_hour"]
    ebs = ec2_hours * EBS_GB_PER_INSTANCE * PRICES["ebs_gb_month"] / 730 if args.ebs else 0.0
    print("  Tong: %.2f instance-gio -> EC2 %.4f | public IPv4 %.4f%s" % (
        ec2_hours, ec2, ipv4_ec2, " | EBS %.4f" % ebs if args.ebs else ""))

    # ---- ALB ----
    print("\n2) ALB (moi gio le tinh tron 1 gio)")
    alb_hours_billed, unknown = 0, 0
    for name, a, b in ALB_INTERVALS:
        if b and parse_vn(b) <= since:    # chi tinh ALB xoa sau ngay --tu
            continue
        if not a or not b:
            print("  %-34s CHUA DU MOC THOI GIAN -> bo qua (sua ALB_INTERVALS)" % name)
            unknown += 1
            continue
        h = (parse_vn(b) - parse_vn(a)).total_seconds() / 3600
        billed = math.ceil(h)
        alb_hours_billed += billed
        print("  %-34s %s -> %s  %6.2f gio thuc te, tinh %d gio" % (name, a[5:], b[5:], h, billed))
    alb = alb_hours_billed * (PRICES["alb_hour"] + LCU_PER_HOUR * PRICES["lcu_hour"])
    ipv4_alb = alb_hours_billed * ALB_IPV4_PER_ALB * PRICES["ipv4_hour"]
    print("  Tong: %d gio ALB -> ALB %.4f | public IPv4 cua ALB %.4f" % (alb_hours_billed, alb, ipv4_alb))

    # ---- S3 ----
    s3 = S3_GB_STORED * PRICES["s3_gb_month"]
    print("\n3) S3: %.3f GB luu tru -> %.4f USD/thang (rat nho)" % (S3_GB_STORED, s3))

    total = ec2 + ipv4_ec2 + ebs + alb + ipv4_alb + s3
    print("\n" + "-" * 66)
    print(" TONG UOC TINH: %.4f USD" % total)
    print("-" * 66)
    if unknown:
        print(" Luu y: %d khoang ALB chua co du moc -> tong chua day du." % unknown)
    print(" So lieu that: trang Learner Lab ('Used $x of $50'), chup truoc va sau tung buoi.")
    print(" Khong tinh: LCU (neu LCU_PER_HOUR = 0), CloudWatch, truyen du lieu, phi tin dung CPU vuot muc.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
