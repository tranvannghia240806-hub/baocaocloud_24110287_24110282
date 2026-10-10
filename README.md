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
| Target Tracking Policy | `ASGAverageCPUUtilization`, target 50% |
| Instance warm-up | 60–120 giây (dự kiến, điều chỉnh theo số liệu đo thực tế) |
| Công cụ tạo tải | `ab` / `hey` / `locust` |

## Quy ước

- **Tag** cho mọi tài nguyên: `Project = HAWeb`, `Owner = <MSSV>`
- **Tên tài nguyên**: tiền tố `HA-Web-`
- **IAM**: dùng `LabRole` / `LabInstanceProfile` do Learner Lab cấp, không tạo IAM user hoặc role
- **Giới hạn Lab**: EC2 loại nano → large, ≤ 9 instance và ≤ 32 vCPU mỗi region, EBS ≤ 100 GB (gp2/gp3)
- **Chi phí**: dừng hoặc xóa tài nguyên (đặc biệt ALB, EC2) sau mỗi buổi làm

## Tiến độ

- [x] **Tuần 1**: tìm hiểu dịch vụ, thiết kế kiến trúc, vẽ sơ đồ, dựng nền tảng (VPC, subnet, IGW, Route Table, Security Group), gắn tag
- [ ] **Tuần 2**: Launch Template, Target Group, ALB, ASG, Target Tracking Policy, warm-up; kiểm thử từng thành phần
- [ ] **Tuần 3**: tích hợp, bảo mật, giám sát CloudWatch, kịch bản tải, IaC (nếu có)
- [ ] **Tuần 4**: kiểm thử tổng thể, tối ưu chi phí, dọn dẹp tài nguyên, báo cáo chi phí, báo cáo phân tích, video demo (≤ 10 phút)

## Cấu trúc repo

```text
ha-web-alb-asg/
├── README.md
├── .gitignore
├── docs/
│   ├── architecture.png        Sơ đồ kiến trúc
│   ├── architecture.mmd        Sơ đồ dạng Mermaid
│   └── bao-cao-tuan-1.docx     Báo cáo tuần 1
├── scripts/                    User data, script tạo tải (từ tuần 2)
└── templates/                  Template CloudFormation (nếu làm IaC)
```

## Sử dụng AI

Nhóm có dùng AI (Claude) để tham khảo, hỗ trợ thiết kế và gỡ lỗi. Mọi tài nguyên đều do nhóm tự triển khai và chạy thật trên AWS Learner Lab.

| Phần công việc | Mức độ hỗ trợ của AI |
| --- | --- |
| [Điền theo thực tế] | [Điền theo thực tế] |