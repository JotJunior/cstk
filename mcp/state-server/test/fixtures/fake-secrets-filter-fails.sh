#!/bin/sh
# Fake secrets-filter.sh that always fails (exit != 0), for exercising the
# fail-closed placeholder path of audit/log.ts::scrubText.
exit 7
