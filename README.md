![Sơ đồ Kiến trúc mạng](./diagram.svg)
![Ảnh thực tế](./anhthucte.jpg)

## Danh sách code
- san.sh: code khởi tạo SAN server
- esxi.sh: code khởi tạo ESXi server
- monitor.sh: code khởi tạo Monitor server
- router.rsc: code cấu hình Router
- switch.rsc: code cấu hình Switch
- iser_monitor.py: code Python agent lấy log từ SAN server
- patch/: các patch vá khi cài đặt chương trình

## Danh sách thiết bị
- SAN server
  + CPU: Dual Intel 8171M 56 nhân, 108 luồng
  + RAM: 4 thanh 64 GB DDR4
  + SSD: 512 GB
  + Mainboard: Huananzhi X11
  + GPU: Dual RTX 3090 (để nghiên cứu AI, trước mắt nghiên cứu RoCEv2 để giao tiếp GPU-GPU cross PC)
  + PSU: Nguồn 2 nguồn 1000 W
  + NIC: Mellanox ConnectX4-Lx, **hỗ trợ đầy đủ iSER**, tối đa 25 GbE
  + Module quang: Hadar 10G, do Switch chỉ hỗ trợ tối đa 10 GbE
- ESXi server:
  + CPU: Dual Intel 8171M 56 nhân, 108 luồng
  + RAM: 4 thanh 64 GB DDR4
  + SSD: 512 GB
  + Mainboard: Huananzhi X11. **ESXi 8 không hỗ trợ mainboard này**
  + NIC: Mellanox ConnectX4-Lx, **hỗ trợ đầy đủ iSER**
  + Module quang: Hadar 10G, do Switch chỉ hỗ trợ tối đa 10 GbE
- Switch Mikrotik CRS309-1G-8S+IN, **hỗ trợ đầy đủ iSER**, tối đa 10 GbE, nhưng để tăng độ khó bài lab, giả sử rằng nó không hỗ trợ iSER
- Router Mikrotik heyS: thiết bị mặc định của nhà mạng FPT
- Switch cáp đồng 24 port no name

Hệ thống có hiệu năng/giá thành rất cao
- Dual Intel 8171M có đến 56 nhân, 108 luồng, chỉ đắt ở mainboard, CPU + Mainboard chỉ khoảng 20 triệu
- Dual RTX 3090 với NVLink tổng 48 GB VRAM chỉ 38 triệu, tổng số nhân CUDA bằng RTX 5090. Nhưng RTX 5090 giá 110 triệu và chỉ 32 GB VRAM
- Mikrotik CRS309, Mellanox ConnectX4-Lx là nhưng thiết bị giá rẻ nhất mà có tính năng iSER

