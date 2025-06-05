# gen_ssig0_lut.py
def rotr(x, n):
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF

def ssig0(x):
    return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)

print("constant uint SSIG0_LUT[4096] = {")
for i in range(4096):
    val = ssig0(i)
    end = "," if i < 4095 else ""
    if i % 8 == 0:
        print("    ", end="")
    print(f"0x{val:08x}{end}", end=" ")
    if i % 8 == 7:
        print()
print("};")

