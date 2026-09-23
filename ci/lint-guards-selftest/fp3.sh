#!/bin/sh
ssh h "Q='$Q' sh -s" <<'GUEST'
[ -n "$Q" ] || { echo no; exit 1; }
GUEST
