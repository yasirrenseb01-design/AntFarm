"""List (or check for) Thai text in string literals of the game's scripts - comments are skipped (a line at a time:
a string running over two lines is missed; tests/lang_test.gd, in tools/check.ps1, catches those too).
Usage: python tools/dev/thai_strings.py [--check] [files...]
  (no files: every scripts/**/*.gd)   --check: exit 1 if any is found (PART EA-R R1)
"""
import glob
import re
import sys

THAI = re.compile('[฀-๿]')


def literals(line):
    """(col, text) of each string literal on one line of GDScript, comments left out."""
    out = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == '#':
            break
        if c in '"\'':
            q = c
            j = i + 1
            buf = []
            while j < n and line[j] != q:
                if line[j] == '\\' and j + 1 < n:
                    buf.append(line[j:j + 2])
                    j += 2
                    continue
                buf.append(line[j])
                j += 1
            out.append((i, ''.join(buf)))
            i = j + 1
            continue
        i += 1
    return out


def scan(files):
    found = []
    for f in files:
        with open(f, encoding='utf-8') as fh:
            for ln, line in enumerate(fh, 1):
                for col, s in literals(line):
                    if THAI.search(s):
                        found.append((f, ln, s))
    return found


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    files = args or sorted(glob.glob('scripts/**/*.gd', recursive=True))
    found = scan(files)
    for f, ln, s in found:
        print('%s:%d: %s' % (f, ln, s))
    if '--check' in sys.argv:
        print('THAI IN CODE: %d' % len(found) if found else 'NO THAI IN CODE')
        sys.exit(1 if found else 0)


if __name__ == '__main__':
    main()
