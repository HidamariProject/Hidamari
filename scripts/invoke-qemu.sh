#!/bin/sh
exec ${QEMU:-qemu-system-x86_64} -cpu Penryn-v1 -bios scripts/OVMF-with-csm.fd -vga std -serial stdio -display gtk -hda fat:rw:$PWD/output "$@"
