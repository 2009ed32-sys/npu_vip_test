# NPU VIP Test

Vivado AXI VIP를 사용해 `renewal` convolution front-end의 제어 및 memory read 경로를 검증하는 프로젝트입니다.

## Verification Scope

현재 시나리오는 다음 조건을 사용합니다.

- Input: 5x5, 32 channels
- Kernel: 3x3, 32 channels
- Stride: 1x1
- Output positions: 3x3
- AXI read: 32-bit beat, 8-beat INCR burst
- MACLane packets: 3x3 output positions x 3x3 kernel positions = 81

검증 항목은 다음과 같습니다.

- AXI4-Lite Master VIP를 통한 CSB register programming
- AXI-to-APB bridge를 통한 APB control access
- AXI Slave Memory VIP에 data/weight pattern preload
- Data 25회 및 weight 9회의 DDR burst 주소 순서
- `ARLEN=7`, `ARSIZE=4-byte`, `ARBURST=INCR`
- MACLane의 tag, data, weight packet 순서
- `maclane_ready=0`에서 payload가 유지되는 backpressure
- Python 독립 정답 81개와 RTL 출력의 Tcl 비교

현재 범위에는 MAC 연산, CACC 누산, SDP writeback, padding, multi-chunk refill 및 AXI error injection이 포함되지 않습니다.

## Repository Layout

```text
rtl/        renewal RTL sources
tb/         VIP wrapper, testbench, Python reference, Tcl runner
vivado/ip/  AXI VIP, AXI-to-APB bridge, AXI interconnect XCI files
```

## Requirements

- Vivado 2023.1
- XSim
- Python 3
- Target part: `xc7z020clg400-1`

Vivado IP output products와 simulation 결과는 저장소에 포함하지 않습니다. Tcl 실행 시 `.vivado/` 아래에 다시 생성됩니다.

## Run

64x64 data refill 시나리오는 Vivado Tcl console에서 저장소 루트를 현재 경로로 설정한 뒤 실행합니다.

```tcl
source tb/run_renewal_vip_refill_64x64_check.tcl
```

또는 PowerShell에서 실행합니다.

```powershell
& "C:\Xilinx\Vivado\2023.1\bin\vivado.bat" `
  -mode batch `
  -source tb/run_renewal_vip_refill_64x64_check.tcl
```

성공하면 TB 자체 검사와 독립 정답 비교 결과가 모두 출력됩니다.

```text
renewal_vip_refill_64x64_TB PASSED: 64x64 DATA, 32x32 WEIGHT, stride 32, and four CBUF chunks verified
MACLane refill64 comparison PASSED: 4096/4096 entries matched
```

기존 5x5 data와 3x3 weight 시나리오는 그대로 유지되며 다음 명령으로 실행할 수 있습니다.

```tcl
source tb/run_renewal_vip_maclane_check.tcl
```

## Simulation Result

Vivado 2023.1 XSim에서 64x64 input data를 네 개의 CBUF chunk로 나누어 읽고, 필요한 chunk를 다시 요청하는 refill 시나리오를 검증했습니다.

| 검증 항목 | 결과 |
|---|---:|
| CSB AXI4-Lite read/write response | PASS (`OKAY`) |
| Data chunk 순서 | PASS (`0,1,0,1,2,3,2,3`) |
| Data AXI read burst | PASS (8192 bursts) |
| Weight AXI read burst | PASS (1024 bursts) |
| AXI burst 속성 | PASS (`ARLEN=7`, `ARSIZE=4-byte`, `INCR`) |
| MACLane backpressure payload 유지 | PASS |
| MACLane tag/data/weight 자체 검사 | PASS (4096 packets) |
| Python 독립 정답과 RTL 출력 비교 | PASS (4096/4096 matched) |

검증 조건과 packet 수는 다음과 같습니다.

```text
input             = 64 x 64 x 32
kernel            = 32 x 32 x 32, one kernel
stride            = 32 x 32
output positions  = 2 x 2
MACLane packets   = 2 x 2 x 32 x 32 = 4096
CBUF chunk size   = 1024 input positions
```

각 chunk의 첫 DDR 주소는 `0x01000000`, `0x01008000`, `0x01010000`, `0x01018000`으로 확인됐습니다. 마지막 실행은 simulation time `3998990 ns`에 정상 종료됐습니다.

```text
[MACLANE PASS] packet=4095 tag=4095 out=(1,1) kernel=(31,31) data_position=4095
renewal_vip_refill_64x64_TB PASSED: 64x64 DATA, 32x32 WEIGHT, stride 32, and four CBUF chunks verified
Executing Axi4 End Of Simulation checks
MACLane refill64 comparison PASSED: 4096/4096 entries matched
```

이 테스트는 네 chunk의 forward/backward refill과 MACLane 배치를 빠르게 확인하기 위해 stride 32를 사용한 directed test입니다. Stride 1의 전체 33x33 output convolution 검증은 포함하지 않습니다.
