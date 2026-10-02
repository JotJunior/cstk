#!/usr/bin/env python3
"""Reuse cstk's tool-call sidecar; this does not measure provider tokens."""

import os
import subprocess
import sys

from pretooluse import RUNTIME, SOURCE


def main():
    env = dict(os.environ)
    env["CLAUDE_PLUGIN_ROOT"] = str(SOURCE / "plugins/cstk")
    try:
        result = subprocess.run(["sh", str(RUNTIME / "hooks/posttooluse-tool-call-tick.sh")],
                                input=sys.stdin.read(), text=True, capture_output=True,
                                env=env, timeout=4)
        if result.returncode:
            print('{"systemMessage":"cstk: tool-call tick failed; verify manual metering"}')
    except (OSError, subprocess.SubprocessError):
        print('{"systemMessage":"cstk: tool-call tick unavailable; verify manual metering"}')


if __name__ == "__main__":
    main()
