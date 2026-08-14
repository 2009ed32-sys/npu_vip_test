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

Vivado Tcl console에서 저장소 루트를 현재 경로로 설정한 뒤 실행합니다.

```tcl
source tb/run_renewal_vip_maclane_check.tcl
```

또는 PowerShell에서 실행합니다.

```powershell
& "C:\Xilinx\Vivado\2023.1\bin\vivado.bat" `
  -mode batch `
  -source tb/run_renewal_vip_maclane_check.tcl
```

성공하면 TB 자체 검사와 독립 정답 비교 결과가 모두 출력됩니다.

```text
renewal_vip_TB PASSED: 5x5 DATA and 3x3 WEIGHT verified
MACLane comparison PASSED: 81 entries matched
```
