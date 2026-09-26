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

OK = re.compile(r'^(\S+)\s+(\d+) of (\d+) tests successful')
NONE = re.compile(r'^(\S+)\s+No tests run\.')
ABORT = re.compile(r'^(\S+)\s+(\d+) tests completed \(aborted\)')


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

    worse = []
    width = max(len(k) for k in base.keys() | patched.keys())
    print(f'{"file":<{width}}  {"base":>14}  {"patched":>14}')
    for k in sorted(base.keys() | patched.keys()):
        b, p = base.get(k), patched.get(k)
        mark = ''
        if b is not None and (p is None or
                              (b[0] != 'aborted' and p[0] == 'aborted') or
                              p[1] < b[1]):
            mark = '  <-- worse'
            worse.append(k)
        elif b is not None and p is not None and p[1] > b[1]:
            mark = '  (better)'
        elif b is not None and b[0] == 'ok' and b[1] < b[2]:
            mark = '  (fails in base too)'
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
