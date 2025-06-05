def rotr(x, n):
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF

def bsig0(x):
    return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22)

print("constant uint BSIG0_LUT[4096] = {")
for i in range(4096):
    val = bsig0(i)
    end = "," if i < 4095 else ""
    if i % 8 == 0:
        print("    ", end="")
    print(f"0x{val:08x}{end}", end=" ")
    if i % 8 == 7:
        print()
print("};")
