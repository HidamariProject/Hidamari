# The Hidamari Project

(C) 2020 Ronsor Labs.

## Introduction

This is an operating system primarily geared at running WebAssembly code that uses functions conforming to the WASI specifications.
All main components are included in this repository, including the kernel, drivers, and userspace applications.

## TODO:

0. Finish implementing WASI APIs.
1. Clean up all the TODOs in code.
2. Fix security issues.
3. Exit UEFI boot services at some point.
4. GUI
5. Networking
6. Audio
7. Many more things.

## Building and running.

This is pretty simple. Clone the repo and run `zig build`. The kernel will be built as `output/efi/boot/bootx64.efi` and you
can test in QEMU using `sh scripts/invoke-qemu.sh`.
