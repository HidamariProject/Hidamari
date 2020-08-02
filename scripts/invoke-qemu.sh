#!/bin/sh
exec ${QEMU:-qemu-system-x86_64} -accel kvm -cpu Penryn-v1 -bios /usr/share/ovmf/OVMF.fd -vga std -display gtk -serial stdio -hda fat:rw:$PWD/output "$@"
