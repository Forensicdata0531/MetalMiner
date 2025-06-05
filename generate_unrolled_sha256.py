# generate_unrolled_sha256.py

def bsig0(var): return f"(rotr({var}, 2) ^ rotr({var}, 13) ^ rotr({var}, 22))"
def bsig1(var): return f"(rotr({var}, 6) ^ rotr({var}, 11) ^ rotr({var}, 25))"
def ch(e, f, g): return f"(({e} & {f}) ^ ((~{e}) & {g}))"
def maj(a, b, c): return f"(({a} & {b}) ^ ({a} & {c}) ^ ({b} & {c}))"

def round_code(round_num):
    k = f"K[{round_num}]"
    w = f"w[{round_num}]"
    S1 = bsig1("e")
    ch_expr = ch("e", "f", "g")
    temp1 = f"(h + {S1} + {ch_expr} + {k} + {w})"
    S0 = bsig0("a")
    maj_expr = maj("a", "b", "c")
    temp2 = f"({S0} + {maj_expr})"

    return f"""\
    // Round {round_num}
    {{
        uint T1 = {temp1};
        uint T2 = {temp2};
        h = g;
        g = f;
        f = e;
        e = d + T1;
        d = c;
        c = b;
        b = a;
        a = T1 + T2;
    }}"""

print("// === BEGIN UNROLLED SHA-256 ROUNDS ===")
for i in range(64):
    print(round_code(i))
print("// === END UNROLLED SHA-256 ROUNDS ===")
