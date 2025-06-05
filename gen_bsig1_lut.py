def rotr(x, n):
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF

def bsig1(x):
    return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25)

print("constant uint BSIG1_LUT[4096] = {")
for i in range(4096):
    val = bsig1(i)
    end = "," if i < 4095 else ""
    if i % 8 == 0:
        print("    ", end="")
    print(f"0x{val:08x}{end}", end=" ")
    if i % 8 == 7:
        print()
print("};")
