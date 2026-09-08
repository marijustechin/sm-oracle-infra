#!/usr/bin/env python3
"""Read-only comparison of saved host policy; bootstrap needs no INPUT additions."""
import argparse
from pathlib import Path


def verify_unchanged(before: Path, current: Path) -> None:
    if before.read_bytes() != current.read_bytes():
        raise ValueError('Saved host policy changed; inspect delta, do not restore blindly')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['check'])
    parser.add_argument('before', type=Path)
    parser.add_argument('current', type=Path)
    args = parser.parse_args()
    try:
        verify_unchanged(args.before, args.current)
    except (ValueError, OSError) as error:
        parser.exit(1, f'{error}\n')
    print('Saved host policy unchanged')
