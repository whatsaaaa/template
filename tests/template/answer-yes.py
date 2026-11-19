"""Runs a command in a terminal, as a person would, and answers yes to every yes/no question it asks.

Copier refuses an answer given with --data that its validator rejects, but not a yes typed in at a
yes/no prompt, which it does not validate: what Copier asks is what a person can answer.
Usage: python3 tests/template/answer-yes.py <command>...
"""

import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(sys.stdout.fileno(), termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    os.environ["TERM"] = "xterm-256color"
    os.execvp(sys.argv[1], sys.argv[1:])

deadline = time.monotonic() + 120
seen = b""
answered = False  # waiting for the yes to show before looking for the next question
while True:
    if time.monotonic() > deadline:
        os.kill(pid, signal.SIGKILL)
        sys.exit(f"{sys.argv[1]} is still running after 120 seconds, waiting for an answer")
    if not select.select([fd], [], [], 1)[0]:
        continue
    try:
        chunk = os.read(fd, 4096)
    except OSError:  # EIO once the command has exited and closed the terminal
        break
    if not chunk:
        break
    sys.stdout.buffer.write(chunk)
    sys.stdout.flush()
    if b"\x1b[6n" in chunk:  # the prompt asks where the cursor is
        os.write(fd, b"\x1b[1;1R")
    seen += chunk
    while True:
        if answered and b"Yes" in seen:
            seen, answered = seen.split(b"Yes", 1)[1], False
        elif not answered and (prompt := next((p for p in (b"(y/N)", b"(Y/n)") if p in seen), None)):
            os.write(fd, b"y")
            seen, answered = seen.split(prompt, 1)[1], True
        else:
            break

sys.exit(os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]))
