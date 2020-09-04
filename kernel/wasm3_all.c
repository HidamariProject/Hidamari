#include <stdio.h>

#define d_m3Use32BitSlots 1

//#define DEBUG_OPS

#if 0
#define DEBUG
//#define d_m3LogOutput 1

//#define printf(...) __earlyprintk("m3log:" #__VA_ARGS__ "\r\n")

#define __PRNK_DBG(f,l,fn) __earlyprintk("m3debug: " f ":" #l " in "fn" ()\r\n");
#define PRNK_DBG() __PRNK_DBG(__FILE__, "???", "???");
#endif

#include "wasm3/source/m3_core.c"
//#include "wasm3/source/m3_api_libc.c"
//#include "wasm3/source/m3_api_meta_wasi.c"
//#include "wasm3/source/m3_api_tracer.c"
//#include "wasm3/source/m3_api_uvwasi.c"
//#include "wasm3/source/m3_api_wasi.c"
#include "wasm3/source/m3_bind.c"
#include "wasm3/source/m3_code.c"
#include "wasm3/source/m3_compile.c"
#include "wasm3/source/m3_emit.c"
#include "wasm3/source/m3_env.c"
#include "wasm3/source/m3_exec.c"
#include "wasm3/source/m3_info.c"
#include "wasm3/source/m3_module.c"
#include "wasm3/source/m3_optimize.c"
#include "wasm3/source/m3_parse.c"

