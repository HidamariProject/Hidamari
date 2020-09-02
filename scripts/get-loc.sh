#!/bin/sh
{
	find apps -iname '*.zig';
	find kernel -iname '*.zig';
	find kernel/klibc -iname '*.[ch]';
	find kernel -maxdepth 1 -iname '*.c';
} | xargs wc -l
