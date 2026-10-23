"""Runs the BrightScript engine's CLI inside a pseudo-terminal (it only reads keyboard shortcuts from a TTY) and takes screenshots on demand.
Commands arrive on stdin, one per line:  shot <name.png>   |   quit
Usage: python3 tools/pty_driver.py <staging dir>  <output dir>"""
import os, pty, sys, time, select, signal, shutil, threading

stage, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
cli = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "node_modules", ".bin", "brs-cli")
pid, fd = pty.fork()
if pid == 0:
    os.chdir(stage)
    os.execv(cli, ["brs-cli", "-r", ".", "-s", "shot.png", "-e", "source/main.brs"])


logfile = open(os.path.join(outdir, "cli.log"), "ab")
alive = True


def drain():
    # keep the terminal buffer empty at all times, or the engine blocks while drawing its ASCII preview
    while alive:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return
            if not data:
                return
            # keep the log small: only lines that are not screen redraws
            text = data.decode("utf-8", "ignore")
            for ln in text.replace("\r", "").split("\n"):
                if "BRIGHTSCRIPT" in ln or "ERROR" in ln or "WARN" in ln or "Screenshot" in ln or "print" in ln.lower():
                    logfile.write((ln + "\n").encode()); logfile.flush()


threading.Thread(target=drain, daemon=True).start()


def pump(sec):
    time.sleep(sec)


print("ready", flush=True)
for line in sys.stdin:
    parts = line.strip().split(" ", 1)
    if parts[0] == "shot":
        target = os.path.join(stage, "shot.png")
        before = os.path.getmtime(target) if os.path.exists(target) else 0
        saved = False
        for attempt in range(4):
            os.write(fd, b"\x13")
            for _ in range(20):
                pump(0.25)
                if os.path.exists(target) and os.path.getmtime(target) > before:
                    saved = True
                    break
            if saved:
                break
        if saved:
            shutil.copy(target, os.path.join(outdir, parts[1]))
        print("saved" if saved else "FAILED", parts[1], flush=True)
    elif parts[0] == "wait":
        pump(float(parts[1]))
        print("waited", flush=True)
    elif parts[0] == "quit":
        break
try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass
