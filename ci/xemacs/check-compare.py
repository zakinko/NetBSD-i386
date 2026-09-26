#!/usr/bin/env python3
"""Compare two `make check' logs from XEmacs's test-harness.

    check-compare.py BASE.log PATCHED.log

test-harness ends with one line per test file:

    buffer-tests.el     123 of 125 tests successful ( 98%).
    foo-tests.el             No tests run.
    bar-tests.el         40 tests completed (aborted).

The patch passes when, for every file the base tree ran, the patched
tree ran it too and succeeded on at least as many tests, and no file
that completed in the base tree aborted in the patched one.  Failures
the base tree already had are shown but are not the patch's.
"""
import re
import sys

# test-harness pads the counts to a column ("18 of    18"), so every gap
# is \s+.  A first version wrote single spaces and matched only the lines
# whose counts filled the column, 7 files of 39.
OK = re.compile(r'^(\S+?):?\s+(\d+)\s+of\s+(\d+)\s+tests successful')
NONE = re.compile(r'^(\S+?):?\s+No tests run\.')
ABORT = re.compile(r'^(\S+?):?\s+(\d+)\s+tests completed \(aborted\)')


def summary(path):
    res = {}
    with open(path, encoding='utf-8', errors='replace') as f:
        for raw in f:
            line = raw.replace('\r', '').strip()
            m = OK.match(line)
            if m:
                res[m[1]] = ('ok', int(m[2]), int(m[3]))
                continue
            m = NONE.match(line)
            if m:
                res[m[1]] = ('none', 0, 0)
                continue
            m = ABORT.match(line)
            if m:
                res[m[1]] = ('aborted', int(m[2]), None)
    return res


def fails(r):
    if r is None or r[0] != 'ok':
        return None
    return r[2] - r[1]


def show(r):
    if r is None:
        return 'missing'
    kind, n, m = r
    return {'ok': f'{n}/{m}', 'none': 'no tests', 'aborted': f'{n} (aborted)'}[kind]


def main():
    base, patched = summary(sys.argv[1]), summary(sys.argv[2])
    if not base:
        sys.exit('no test-harness summary in the base log: nothing measured')
    if not patched:
        sys.exit('no test-harness summary in the patched log: nothing measured')
    # Count the files named on anything that looks like a summary line
    # against the files parsed, so a parser that misses a format cannot
    # report a partial comparison as a whole one.  Names, not lines: each
    # summary appears twice in the log, once as the file finishes and once
    # in the table at the end.
    for path, got in ((sys.argv[1], base), (sys.argv[2], patched)):
        with open(path, encoding='utf-8', errors='replace') as f:
            seen = {l.split()[0].rstrip(':') for l in f
                    if re.search(r'tests successful|No tests run|\(aborted\)', l)
                    and l.split()}
        if seen != set(got):
            sys.exit(f'{path}: summary lines name {len(seen)} files, parsed '
                     f'{len(got)}; not parsed: {sorted(seen - set(got))}')

    worse = []
    width = max(len(k) for k in base.keys() | patched.keys())
    print(f'{"file":<{width}}  {"base":>14}  {"patched":>14}')
    for k in sorted(base.keys() | patched.keys()):
        b, p = base.get(k), patched.get(k)
        mark = ''
        # Worse means more failures, not fewer successes: some files
        # (query-coding-tests.el) generate a different number of tests
        # from run to run, with no failure at all on either side.
        fb = fails(b)
        fp = fails(p)
        if b is not None and (p is None or
                              (b[0] != 'aborted' and p[0] == 'aborted') or
                              (fb is not None and fp is not None and fp > fb)):
            mark = f'  <-- worse ({fb} -> {fp} failed)' if fp is not None else '  <-- worse'
            worse.append(k)
        elif fb is not None and fp is not None and fp < fb:
            mark = f'  (better: {fb} -> {fp} failed)'
        elif fb:
            mark = f'  (fails in base too: {fb})'
        print(f'{k:<{width}}  {show(b):>14}  {show(p):>14}{mark}')

    tb = sum(r[1] for r in base.values())
    tp = sum(r[1] for r in patched.values())
    print(f'\n{len(base)} files in base, {len(patched)} in patched; '
          f'successful tests {tb} -> {tp}')
    if worse:
        sys.exit('worse with the patch: ' + ' '.join(worse))
    print('no file is worse with the patch')


if __name__ == '__main__':
    main()
