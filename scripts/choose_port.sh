#!/usr/bin/env bash
set -euo pipefail
# Report a free development port. Never rewrite production configuration.
python3 - <<'PY'
import socket
with socket.socket() as listener:
    listener.bind(('127.0.0.1', 0))
    print(listener.getsockname()[1])
PY
