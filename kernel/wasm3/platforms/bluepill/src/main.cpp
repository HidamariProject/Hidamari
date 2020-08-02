//
//  Wasm3 - high performance WebAssembly interpreter written in C.
//
//  Copyright © 2019 Steven Massey, Volodymyr Shymanskyy.
//  All rights reserved.
//

#include "m3/wasm3.h"
#include "m3/m3_env.h"

#include "m3/extra/fib32.wasm.h"

#include <jee.h>

#define FATAL(func, msg) {           \
  puts("Fatal: " func ": ");         \
  puts(msg); return; }

void run_wasm()
{
    M3Result result = m3Err_none;

    uint8_t* wasm = (uint8_t*)fib32_wasm;
    size_t fsize = fib32_wasm_len-1;

    puts("Loading WebAssembly...");

    IM3Environment env = m3_NewEnvironment ();
    if (!env) FATAL("m3_NewEnvironment", "failed");

    IM3Runtime runtime = m3_NewRuntime (env, 1024, NULL);
    if (!runtime) FATAL("m3_NewRuntime", "failed");

    IM3Module module;
    result = m3_ParseModule (env, &module, wasm, fsize);
    if (result) FATAL("m3_ParseModule", result);

    result = m3_LoadModule (runtime, module);
    if (result) FATAL("m3_LoadModule", result);

    IM3Function f;
    result = m3_FindFunction (&f, runtime, "fib");
    if (result) FATAL("m3_FindFunction", result);

    puts("Running...");

    const char* i_argv[2] = { "24", NULL };
    result = m3_CallWithArgs (f, 1, i_argv);

    if (result) FATAL("m3_CallWithArgs", result);

    long value = *(uint64_t*)(runtime->stack);

    printf("Result: %ld\n", value);
}

PinC<13> led;

int main()
{
  enableSysTick();
  led.mode(Pinmode::out);

  puts("Wasm3 v" M3_VERSION " on BluePill, build " __DATE__ " " __TIME__ "\n");

  led = 0;
  run_wasm();
  led = 1;

}
