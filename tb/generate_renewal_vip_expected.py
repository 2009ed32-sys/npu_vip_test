#!/usr/bin/env python3

from pathlib import Path


INPUT_WIDTH = 5
INPUT_HEIGHT = 5
KERNEL_WIDTH = 3
KERNEL_HEIGHT = 3
OUTPUT_WIDTH = INPUT_WIDTH - KERNEL_WIDTH + 1
OUTPUT_HEIGHT = INPUT_HEIGHT - KERNEL_HEIGHT + 1
BURST_LEN = 8
WORD_WIDTH = 32
MACLANE_WIDTH = 512
DATA_PATTERN = 0xD000_0000
WEIGHT_PATTERN = 0xA000_0000


def pack_burst(words: list[int]) -> int:
    packed = 0
    for beat, word in enumerate(words):
        packed |= (word & 0xFFFF_FFFF) << (beat * WORD_WIDTH)
    return packed


def data_words(position: int) -> list[int]:
    return [
        DATA_PATTERN + position * BURST_LEN + beat
        for beat in range(BURST_LEN)
    ]

def weight_words(kernel_position: int) -> list[int]:
    return [
        WEIGHT_PATTERN + kernel_position * BURST_LEN + beat
        for beat in range(BURST_LEN)
    ]


def generate_expected_lines() -> list[str]:
    lines = []
    tag = 0
    hex_digits = MACLANE_WIDTH // 4

    for output_y in range(OUTPUT_HEIGHT):
        for output_x in range(OUTPUT_WIDTH):
            for kernel_y in range(KERNEL_HEIGHT):
                for kernel_x in range(KERNEL_WIDTH):
                    data_x = output_x + kernel_x
                    data_y = output_y + kernel_y
                    data_position = data_y * INPUT_WIDTH + data_x
                    kernel_position = kernel_y * KERNEL_WIDTH + kernel_x

                    data = pack_burst(data_words(data_position))
                    weight = pack_burst(weight_words(kernel_position))
                    lines.append(
                        f"{tag:08x} {data:0{hex_digits}x} "
                        f"{weight:0{hex_digits}x}"
                    )
                    tag += 1

    return lines


def main() -> int:
    output_path = Path(__file__).resolve().parent / "renewal_maclane_expected.txt"
    lines = generate_expected_lines()
    output_path.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"Wrote {len(lines)} expected MACLane entries: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
