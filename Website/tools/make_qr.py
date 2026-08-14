#!/usr/bin/env python3
"""Generate a real, scannable QR code as SVG (and PGM for verification).

Pure standard library. Byte mode, error-correction level M, versions 1-10.

Usage:
    python3 make_qr.py "https://speakit.app" ../assets/img/qr.svg
"""

import sys

# --- Galois field GF(256) with primitive polynomial 0x11d -------------------

EXP = [0] * 512
LOG = [0] * 256
_x = 1
for _i in range(255):
    EXP[_i] = _x
    LOG[_x] = _i
    _x <<= 1
    if _x & 0x100:
        _x ^= 0x11D
for _i in range(255, 512):
    EXP[_i] = EXP[_i - 255]


def gf_mul(a, b):
    if a == 0 or b == 0:
        return 0
    return EXP[LOG[a] + LOG[b]]


def rs_generator(degree):
    """Coefficients of the generator polynomial, lowest power first.

    The final element is the leading coefficient and is always 1.
    """
    poly = [1]
    for i in range(degree):
        poly.append(0)
        for j in range(len(poly) - 1, 0, -1):
            poly[j] = poly[j - 1] ^ gf_mul(poly[j], EXP[i])
        poly[0] = gf_mul(poly[0], EXP[i])
    return poly


def rs_encode(data, ec_count):
    # The division below consumes coefficients highest power first with the
    # leading 1 dropped, which is the reverse of how rs_generator returns them.
    coefficients = rs_generator(ec_count)[:-1][::-1]
    result = [0] * ec_count
    for byte in data:
        factor = byte ^ result[0]
        result = result[1:] + [0]
        for i in range(ec_count):
            result[i] ^= gf_mul(coefficients[i], factor)
    return result


# --- Version tables (error-correction level M only) -------------------------
# version: (ec_codewords_per_block, [(block_count, data_codewords_per_block), ...])
EC_LEVEL_M = {
    1: (10, [(1, 16)]),
    2: (16, [(1, 28)]),
    3: (26, [(1, 44)]),
    4: (18, [(2, 32)]),
    5: (24, [(2, 43)]),
    6: (16, [(4, 27)]),
    7: (18, [(4, 31)]),
    8: (22, [(2, 38), (2, 39)]),
    9: (22, [(3, 36), (2, 37)]),
    10: (26, [(4, 43), (1, 44)]),
}

ALIGNMENT_POSITIONS = {
    1: [],
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
    7: [6, 22, 38],
    8: [6, 24, 42],
    9: [6, 26, 46],
    10: [6, 28, 50],
}


def data_capacity(version):
    _, blocks = EC_LEVEL_M[version]
    return sum(count * size for count, size in blocks)


def pick_version(byte_length):
    for version in sorted(EC_LEVEL_M):
        count_bits = 8 if version <= 9 else 16
        needed_bits = 4 + count_bits + byte_length * 8
        if needed_bits <= data_capacity(version) * 8:
            return version
    raise ValueError("payload too long for versions 1-10 at EC level M")


# --- Bit stream -------------------------------------------------------------

class BitBuffer:
    def __init__(self):
        self.bits = []

    def put(self, value, length):
        for i in range(length - 1, -1, -1):
            self.bits.append((value >> i) & 1)

    def __len__(self):
        return len(self.bits)


def build_codewords(payload, version):
    total_data = data_capacity(version)
    buf = BitBuffer()
    buf.put(0b0100, 4)                                  # byte mode
    buf.put(len(payload), 8 if version <= 9 else 16)    # character count
    for byte in payload:
        buf.put(byte, 8)

    # Terminator, then pad to a byte boundary.
    remaining = total_data * 8 - len(buf)
    buf.put(0, min(4, remaining))
    while len(buf) % 8 != 0:
        buf.put(0, 1)

    codewords = []
    for i in range(0, len(buf.bits), 8):
        byte = 0
        for bit in buf.bits[i:i + 8]:
            byte = (byte << 1) | bit
        codewords.append(byte)

    # Pad codewords alternate between 0xEC and 0x11.
    pad = [0xEC, 0x11]
    pad_index = 0
    while len(codewords) < total_data:
        codewords.append(pad[pad_index % 2])
        pad_index += 1
    return codewords


def interleave(codewords, version):
    ec_count, block_spec = EC_LEVEL_M[version]
    data_blocks = []
    offset = 0
    for count, size in block_spec:
        for _ in range(count):
            data_blocks.append(codewords[offset:offset + size])
            offset += size
    ec_blocks = [rs_encode(block, ec_count) for block in data_blocks]

    result = []
    max_data = max(len(block) for block in data_blocks)
    for i in range(max_data):
        for block in data_blocks:
            if i < len(block):
                result.append(block[i])
    for i in range(ec_count):
        for block in ec_blocks:
            result.append(block[i])
    return result


# --- Matrix -----------------------------------------------------------------

class Matrix:
    def __init__(self, version):
        self.version = version
        self.size = version * 4 + 17
        self.modules = [[0] * self.size for _ in range(self.size)]
        self.reserved = [[False] * self.size for _ in range(self.size)]

    def set(self, x, y, value, reserve=True):
        self.modules[y][x] = value
        if reserve:
            self.reserved[y][x] = True

    def place_finder(self, x0, y0):
        for dy in range(-1, 8):
            for dx in range(-1, 8):
                x, y = x0 + dx, y0 + dy
                if not (0 <= x < self.size and 0 <= y < self.size):
                    continue
                inside_ring = (0 <= dx <= 6 and dy in (0, 6)) or (0 <= dy <= 6 and dx in (0, 6))
                inside_core = 2 <= dx <= 4 and 2 <= dy <= 4
                self.set(x, y, 1 if (inside_ring or inside_core) else 0)

    def place_alignment(self, cx, cy):
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                value = 1 if max(abs(dx), abs(dy)) != 1 else 0
                self.set(cx + dx, cy + dy, value)

    def build_function_patterns(self):
        self.place_finder(0, 0)
        self.place_finder(self.size - 7, 0)
        self.place_finder(0, self.size - 7)

        positions = ALIGNMENT_POSITIONS[self.version]
        for cy in positions:
            for cx in positions:
                near_finder = (
                    (cx <= 8 and cy <= 8)
                    or (cx <= 8 and cy >= self.size - 9)
                    or (cx >= self.size - 9 and cy <= 8)
                )
                if not near_finder:
                    self.place_alignment(cx, cy)

        for i in range(8, self.size - 8):
            bit = 1 if i % 2 == 0 else 0
            self.set(i, 6, bit)
            self.set(6, i, bit)

        # Reserve format-information areas.
        for i in range(9):
            if not self.reserved[i][8]:
                self.set(8, i, 0)
            if not self.reserved[8][i]:
                self.set(i, 8, 0)
        for i in range(8):
            self.set(self.size - 1 - i, 8, 0)
            self.set(8, self.size - 1 - i, 0)

        # The dark module is written last: the reservation sweep above passes
        # over its position and would otherwise clear it.
        self.set(8, self.size - 8, 1)

        # Reserve version-information areas.
        if self.version >= 7:
            for i in range(6):
                for j in range(3):
                    self.set(self.size - 11 + j, i, 0)
                    self.set(i, self.size - 11 + j, 0)

    def place_data(self, codewords):
        bits = []
        for byte in codewords:
            for i in range(7, -1, -1):
                bits.append((byte >> i) & 1)

        index = 0
        upward = True
        col = self.size - 1
        while col > 0:
            if col == 6:  # skip the vertical timing column
                col -= 1
            rows = range(self.size - 1, -1, -1) if upward else range(self.size)
            for row in rows:
                for offset in (0, 1):
                    x = col - offset
                    if self.reserved[row][x]:
                        continue
                    bit = bits[index] if index < len(bits) else 0
                    index += 1
                    self.modules[row][x] = bit
            upward = not upward
            col -= 2

    def masked(self, mask):
        rows = []
        for y in range(self.size):
            row = []
            for x in range(self.size):
                value = self.modules[y][x]
                if not self.reserved[y][x] and mask_condition(mask, x, y):
                    value ^= 1
                row.append(value)
            rows.append(row)
        return rows


def mask_condition(mask, x, y):
    if mask == 0:
        return (x + y) % 2 == 0
    if mask == 1:
        return y % 2 == 0
    if mask == 2:
        return x % 3 == 0
    if mask == 3:
        return (x + y) % 3 == 0
    if mask == 4:
        return (y // 2 + x // 3) % 2 == 0
    if mask == 5:
        return (x * y) % 2 + (x * y) % 3 == 0
    if mask == 6:
        return ((x * y) % 2 + (x * y) % 3) % 2 == 0
    return ((x + y) % 2 + (x * y) % 3) % 2 == 0


def format_bits(mask):
    value = (0b00 << 3) | mask          # 00 = error-correction level M
    remainder = value << 10
    while remainder.bit_length() >= 11:
        remainder ^= 0b10100110111 << (remainder.bit_length() - 11)
    return ((value << 10) | remainder) ^ 0b101010000010010


def version_bits(version):
    remainder = version << 12
    while remainder.bit_length() >= 13:
        remainder ^= 0b1111100100101 << (remainder.bit_length() - 13)
    return (version << 12) | remainder


def apply_format_and_version(grid, matrix, mask):
    size = matrix.size
    bits = format_bits(mask)
    for i in range(15):
        bit = (bits >> i) & 1
        if i < 6:
            grid[i][8] = bit
        elif i == 6:
            grid[7][8] = bit
        elif i == 7:
            grid[8][8] = bit
        elif i == 8:
            grid[8][7] = bit
        else:
            grid[8][14 - i] = bit

        if i < 8:
            grid[8][size - 1 - i] = bit
        else:
            grid[size - 15 + i][8] = bit

    if matrix.version >= 7:
        vbits = version_bits(matrix.version)
        for i in range(18):
            bit = (vbits >> i) & 1
            row, col = i // 3, i % 3
            grid[row][size - 11 + col] = bit
            grid[size - 11 + col][row] = bit


def penalty(grid):
    size = len(grid)
    score = 0

    # Rule 1: runs of five or more identical modules.
    for line in list(grid) + [list(col) for col in zip(*grid)]:
        run = 1
        for i in range(1, size):
            if line[i] == line[i - 1]:
                run += 1
            else:
                if run >= 5:
                    score += 3 + (run - 5)
                run = 1
        if run >= 5:
            score += 3 + (run - 5)

    # Rule 2: 2x2 blocks of one color.
    for y in range(size - 1):
        for x in range(size - 1):
            block = grid[y][x] + grid[y][x + 1] + grid[y + 1][x] + grid[y + 1][x + 1]
            if block in (0, 4):
                score += 3

    # Rule 3: finder-like patterns.
    patterns = ([1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0], [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1])
    for line in list(grid) + [list(col) for col in zip(*grid)]:
        for i in range(size - 10):
            window = line[i:i + 11]
            if window in patterns:
                score += 40

    # Rule 4: overall balance of dark modules.
    dark = sum(sum(row) for row in grid)
    ratio = dark * 100 // (size * size)
    score += 10 * min(abs(ratio - 50) // 5, abs(ratio - 50 + 4) // 5)
    return score


def encode(text):
    payload = text.encode("utf-8")
    version = pick_version(len(payload))
    codewords = interleave(build_codewords(payload, version), version)

    matrix = Matrix(version)
    matrix.build_function_patterns()
    matrix.place_data(codewords)

    best_grid, best_score = None, None
    for mask in range(8):
        grid = matrix.masked(mask)
        apply_format_and_version(grid, matrix, mask)
        score = penalty(grid)
        if best_score is None or score < best_score:
            best_grid, best_score = grid, score
    return best_grid


def to_svg(grid, quiet_zone=4):
    size = len(grid)
    total = size + quiet_zone * 2
    paths = []
    for y, row in enumerate(grid):
        x = 0
        while x < size:
            if row[x]:
                run = 1
                while x + run < size and row[x + run]:
                    run += 1
                paths.append(f"M{x + quiet_zone} {y + quiet_zone}h{run}v1h-{run}z")
                x += run
            else:
                x += 1
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {total} {total}" '
        f'shape-rendering="crispEdges" role="img" aria-label="QR code linking to Speak It on the App Store">'
        f'<rect width="{total}" height="{total}" fill="#FFFFFF"/>'
        f'<path fill="#0E0E0E" d="{"".join(paths)}"/></svg>\n'
    )


def to_png(grid, scale=8, quiet_zone=4):
    """Grayscale PNG bytes, used only to verify the code actually decodes."""
    import struct
    import zlib

    size = len(grid)
    total = (size + quiet_zone * 2) * scale
    raw = bytearray()
    for y in range(total):
        gy = y // scale - quiet_zone
        raw.append(0)  # no per-scanline filter
        for x in range(total):
            gx = x // scale - quiet_zone
            dark = 0 <= gx < size and 0 <= gy < size and grid[gy][gx]
            raw.append(0 if dark else 255)

    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", total, total, 8, 0, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    url = sys.argv[1]
    out_svg = sys.argv[2]
    grid = encode(url)

    with open(out_svg, "w") as handle:
        handle.write(to_svg(grid))
    print(f"wrote {out_svg} ({len(grid)}x{len(grid)} modules) for {url}")

    if len(sys.argv) > 3:
        with open(sys.argv[3], "wb") as handle:
            handle.write(to_png(grid))
        print(f"wrote {sys.argv[3]}")
