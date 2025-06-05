def rotr(x, n):
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF

def ssig1(x):
    return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10)

print("constant uint SSIG1_LUT[4096] = {")
for i in range(4096):
    val = ssig1(i)
    end = "," if i < 4095 else ""
    if i % 8 == 0:
        print("    ", end="")
    print(f"0x{val:08x}{end}", end=" ")
    if i % 8 == 7:
        print()
print("};")
