"""Decode every tc('...','...') call in the obfuscated script.

The tc function takes (encrypted, key) Lua strings and returns the result
of XOR-ing each byte of `encrypted` against the corresponding byte of
`key` (cycling key per position): out[i] = encrypted[i] XOR key[(i-1) mod len(key) + 1]
"""

import re
import sys

SOURCE_PATH = sys.argv[1] if len(sys.argv) > 1 else 'mtc4-cheat-obf.lua'

with open(SOURCE_PATH, 'r', encoding='utf-8', errors='replace') as f:
    src = f.read()


def lua_lit_to_bytes(s):
    """Parse a Lua single-quoted string literal body (between the quotes)
    and return the raw byte values."""
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\':
            i += 1
            if i >= len(s):
                break
            c2 = s[i]
            if c2.isdigit():
                j = i
                while j < len(s) and s[j].isdigit() and (j - i) < 3:
                    j += 1
                out.append(int(s[i:j]) & 0xFF)
                i = j
                continue
            specials = {'a': 7, 'b': 8, 'f': 12, 'n': 10, 'r': 13, 't': 9,
                        'v': 11, '\\': 92, "'": 39, '"': 34, '0': 0}
            out.append(specials.get(c2, ord(c2)))
            i += 1
        else:
            out.append(ord(c) & 0xFF)
            i += 1
    return out


def tc_decode(encrypted, key):
    eb = lua_lit_to_bytes(encrypted)
    kb = lua_lit_to_bytes(key)
    if not kb:
        return ''
    return ''.join(chr(eb[i] ^ kb[i % len(kb)]) for i in range(len(eb)))


# Find every tc('A','B') in the source. Lua single-quote strings let any
# char in including double-quote; escaped quotes use \' . We scan manually.

def find_tc_calls(text):
    calls = []
    i = 0
    n = len(text)
    while i < n - 3:
        if text[i:i + 3] == 'tc(' and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] == '_')):
            # find first arg
            j = i + 3
            while j < n and text[j] in ' \t':
                j += 1
            if j >= n or text[j] != "'":
                i += 1
                continue
            a_start = j + 1
            a_end = a_start
            while a_end < n:
                if text[a_end] == '\\':
                    a_end += 2
                    continue
                if text[a_end] == "'":
                    break
                a_end += 1
            arg1 = text[a_start:a_end]
            # skip comma
            j = a_end + 1
            while j < n and text[j] in ' \t,':
                j += 1
            if j >= n or text[j] != "'":
                i += 1
                continue
            b_start = j + 1
            b_end = b_start
            while b_end < n:
                if text[b_end] == '\\':
                    b_end += 2
                    continue
                if text[b_end] == "'":
                    break
                b_end += 1
            arg2 = text[b_start:b_end]
            j = b_end + 1
            while j < n and text[j] in ' \t':
                j += 1
            if j < n and text[j] == ')':
                calls.append((i, j + 1, arg1, arg2))
                i = j + 1
                continue
        i += 1
    return calls


calls = find_tc_calls(src)

# Decode and emit
seen = {}
print(f"=== {len(calls)} tc() calls found ===\n")
for span_a, span_b, a, b in calls:
    try:
        plain = tc_decode(a, b)
    except Exception as e:
        plain = f"<decode error: {e}>"
    key = (a, b)
    if key not in seen:
        seen[key] = plain
        # show printable
        safe = ''.join(c if 32 <= ord(c) < 127 else f'\\x{ord(c):02x}' for c in plain)
        print(f"{safe}")
print(f"\n=== {len(seen)} unique strings ===")
