# Website có tính sẵn sàng cao với ALB và EC2 Auto Scaling

Đồ án cuối kỳ môn **Điện toán đám mây** (HCMUTE) · GVHD: TS. Huỳnh Xuân Phụng · Nền tảng: AWS Learner Lab

## Nhóm thực hiện

| MSSV | Họ và tên | Vai trò |
| --- | --- | --- |
| 24110287 | Trần Văn Nghĩa | Nhóm trưởng |
| 24110282 | Kiên Nguyễn Xuân Lưu | Thành viên |

## Mục tiêu

Triển khai website chạy trên nhiều EC2 phía sau Application Load Balancer, được quản lý bởi Auto Scaling Group để tự động co giãn theo tải CPU, sau đó đo đạc hành vi **scale-out** và **scale-in**.

Sản phẩm dự kiến:

- Launch Template, Auto Scaling Group (min 1 – max 4, `t3.micro`), ALB có health check
- Kịch bản tải bằng `ab` / `hey` / `locust`
- Biểu đồ CloudWatch minh họa scale-out và scale-in
- Báo cáo phân tích, cấu hình Target Tracking Policy và thời gian warm-up

## Kiến trúc

![Sơ đồ kiến trúc](docs/architecture.png)

## Dịch vụ AWS sử dụng

| Dịch vụ | Vai trò |
| --- | --- |
| Amazon VPC / Subnet / Internet Gateway | Mạng, 2 public subnet ở 2 AZ |
| Security Group | Kiểm soát lưu lượng vào ALB và EC2 |
| Amazon EC2 + Launch Template | Máy chủ web, template mô tả AMI, loại instance, user data |
| Elastic Load Balancing (ALB) | Phân phối lưu lượng, kiểm tra health check |
| EC2 Auto Scaling | Tự động tăng/giảm số instance, thay thế instance lỗi |
| Amazon CloudWatch | Metric CPU, biểu đồ, dữ liệu cho scaling |

## Thông số thiết kế

| Hạng mục | Giá trị |
| --- | --- |
| Region | `us-east-1` |
| VPC | `HA-Web-vpc` – `10.0.0.0/16` |
| Public subnet 1 | `HA-Web-subnet-public1-us-east-1a` – `10.0.0.0/20` |
| Public subnet 2 | `HA-Web-subnet-public2-us-east-1b` – `10.0.16.0/20` |
| Security Group | `HA-Web-ALB-SG` (HTTP 80 từ `0.0.0.0/0`), `HA-Web-EC2-SG` (HTTP 80 chỉ từ `HA-Web-ALB-SG`) |
| AMI / loại instance | Amazon Linux 2023 / `t3.micro` |
| Auto Scaling Group | min 1 / desired 1 / max 4 (không vượt 4 để giữ giới hạn 9 EC2 mỗi region) |
| Target Tracking Policy | `HA-Web-CPU-50`: `ASGAverageCPUUtilization`, target 50% |
| Instance warm-up | 120 giây (giữ nguyên; đo ở tuần 3: instance mới Healthy sau khoảng 1 phút đến 1 phút 10 giây kể từ lúc ASG tăng desired) |
| Công cụ tạo tải | `scripts/load-test.sh` (tuần 3, lần 1) và `ab` (tuần 3, lần 2) |

## Quy ước

- **Tag** cho mọi tài nguyên: `Project = HAWeb`, `Owner = <MSSV>`
- **Tên tài nguyên**: tiền tố `HA-Web-`
- **IAM**: dùng `LabRole` / `LabInstanceProfile` do Learner Lab cấp, không tạo IAM user hoặc role
- **Giới hạn Lab**: EC2 loại nano → large, ≤ 9 instance và ≤ 32 vCPU mỗi region, EBS ≤ 100 GB (gp2/gp3)
- **Chi phí**: dừng hoặc xóa tài nguyên (đặc biệt ALB, EC2) sau mỗi buổi làm

## Tiến độ

- [x] **Tuần 1**: tìm hiểu dịch vụ, thiết kế kiến trúc, vẽ sơ đồ, dựng nền tảng (VPC, subnet, IGW, Route Table, Security Group), gắn tag
- [x] **Tuần 2**: Launch Template, Target Group, ALB, ASG, Target Tracking Policy, warm-up; kiểm thử từng thành phần
- [x] **Tuần 3**: tích hợp, bảo mật, giám sát CloudWatch, kịch bản tải thật, ALB access log ra S3, IaC (CloudFormation)
- [ ] **Tuần 4**: kiểm thử tổng thể, tối ưu chi phí, dọn dẹp tài nguyên, báo cáo chi phí, báo cáo phân tích, video demo (≤ 10 phút)

## Cấu trúc repo

```text
.
├── README.md
├── .gitignore
├── docs/
│   ├── architecture.png                           Sơ đồ kiến trúc
│   ├── Bao_cao_tuan_1.docx                        Báo cáo tuần 1
│   ├── Bao_cao_tuan_2.docx                        Báo cáo tuần 2
│   ├── Bang_phan_cong_va_worklog_tuan_2.docx      Worklog tuần 2
│   ├── Bao_cao_tuan_3.docx                        Báo cáo tuần 3
│   ├── data/tuan3/                                Số liệu đo tuần 3 (CSV scaling, kết quả ab, log lỗi 502)
│   └── images/                                    Ảnh minh chứng (tuan2/, tuan3/)
├── scripts/
│   ├── user-data.sh                               User data của Launch Template HA-Web-LT
│   └── load-test.sh                               Script tạo tải và ghi mốc scale-out/scale-in (tuần 3)
├── infra/
│   └── ha-web-cfn.yaml                            Template CloudFormation: ALB, Target Group, ASG, Target Tracking (tuần 3)
└── templates/                                     Thư mục dự phòng
```

## Kết quả tuần 2

- Launch Template `HA-Web-LT`, Target Group `HA-Web-TG`, Application Load Balancer `HA-Web-ALB`, Auto Scaling Group `HA-Web-ASG` (min 1 – max 4) và Target Tracking Policy `HA-Web-CPU-50` (CPU 50%, warm-up 120 giây) đã triển khai và kiểm thử trên AWS Learner Lab.
- Đã kiểm thử: cân bằng tải qua 2 AZ, Security Group chặn truy cập trực tiếp vào EC2, ASG tự thay thế instance bị terminate, policy tự scale-in qua alarm `AlarmLow`.
- Cuối buổi đã dọn dẹp: ASG min = 0, desired = 0 và xóa ALB để tiết kiệm ngân sách Lab.
- Chi tiết và ảnh minh chứng: xem `docs/Bao_cao_tuan_2.docx`.

## Kết quả tuần 3

- **Tải thật có đo thời gian**: chạy hai lần (script `load-test.sh` với 20 worker, và `ab -c 20` trong 900 giây). Cả hai lần AlarmHigh kích hoạt, ASG tăng 1 → 2 rồi 2 → 4 và đủ 4 instance Healthy. Từ lúc ASG tăng desired đến lúc instance mới Healthy: khoảng 1 phút (lần 1) và 1 phút 10 giây (lần 2), ngắn hơn warm-up 120 giây đã cấu hình.
- **Scale-in (lần 1)**: AlarmLow kích hoạt 17 phút 23 giây sau khi dừng tải, ASG giảm 4 → 3 → 2 → 1 trong khoảng 2 phút 33 giây. Lần 2 không đo scale-in.
- **Giám sát**: dashboard `HA-Web-Dashboard` (CPU, số instance, RequestCount, healthy host, độ trễ) và 3 alarm bổ sung (`HA-Web-ASG-AtMax`, `HA-Web-UnhealthyHosts`, `HA-Web-HighLatency`). Số liệu CPU của ASG chỉ có điểm mỗi 5 phút nên mốc CPU vượt 50% ở lần 2 chỉ xác định trong khung 5 phút.
- **ALB access log**: bật ghi ra S3 bucket `ha-web-alb-logs-902534396906` (prefix `alb`), dùng để phân tích ở tuần 4.
- **Bảo mật**: `HA-Web-EC2-SG` chỉ nhận HTTP 80 từ `HA-Web-ALB-SG`, không mở cổng 22; IMDSv2 bắt buộc (không token trả 401, có token trả 200); truy cập trực tiếp public IP bị timeout; `git grep` tìm khóa truy cập không có kết quả.
- **CloudFormation**: stack `HA-Web-CFN-Stack` tạo trong 2 phút 30 giây, website chạy qua DNS ở Outputs, đã xóa stack sau khi kiểm tra.
- **Hạn chế đã ghi nhận**: 5 request mã 502 ở lần tải 2 (chưa xác định nguyên nhân), thời gian phản hồi do `ab` đo (khoảng 1000 ms) lệch với `TargetResponseTime` trên dashboard (khoảng 85 ms) chưa kiểm chứng, mô phỏng sự cố 1 AZ chuyển sang tuần 4.
- Chi tiết, số liệu và ảnh minh chứng: xem `docs/Bao_cao_tuan_3.docx`.

## Sử dụng AI

Nhóm có dùng AI (Claude) để tham khảo, hỗ trợ thiết kế và gỡ lỗi. Mọi tài nguyên đều do nhóm tự triển khai và chạy thật trên AWS Learner Lab.

| Phần công việc | Mức độ hỗ trợ của AI |
| --- | --- |
| Script `load-test.sh` và template CloudFormation | Dùng Claude soạn; nhóm đã đọc, chỉnh sửa, tự chạy thử trên Learner Lab |
| Dashboard, alarm, access log, rà soát bảo mật | AI gợi ý các bước; nhóm tự thực hiện trên AWS và chụp minh chứng |
| Đối chiếu và phân tích số liệu (CSV, log ALB, ảnh console) | AI hỗ trợ tính khoảng thời gian và gợi ý lệnh kiểm tra; nhóm tự chạy lệnh và đối chiếu với console |
| Khung báo cáo tuần 3 | AI soạn khung; nhóm điền số liệu đo thật và nhận xét |
