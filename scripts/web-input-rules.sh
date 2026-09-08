#!/usr/bin/env bash
# Read-only host policy evidence. No INPUT/FORWARD/DOCKER-USER mutations.
set -euo pipefail
[[ ${1:-} == check && $# == 1 ]] || {
    echo 'Usage: sudo bash web-input-rules.sh check (read-only; add/remove retired)' >&2
    exit 2
}
[[ $EUID == 0 ]] || { echo 'Run with sudo' >&2; exit 1; }
iptables --version | grep -q nf_tables
iptables -w 5 -S INPUT
iptables -w 5 -S FORWARD
iptables -w 5 -S DOCKER-USER
iptables -w 5 -t nat -S
