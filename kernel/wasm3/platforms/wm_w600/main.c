//
//  Wasm3 - high performance WebAssembly interpreter written in C.
//
//  Copyright © 2019 Steven Massey, Volodymyr Shymanskyy.
//  All rights reserved.
//

#include "wm_include.h"

#include "m3/wasm3.h"
#include "m3/m3_env.h"

#include "m3/extra/fib32.wasm.h"

#define FATAL(msg, ...) { printf("Fatal: " msg "\n", ##__VA_ARGS__); return; }

unsigned int millis(void)
{
    return tls_os_get_time()*2;
}

void run_wasm()
{
    M3Result result = m3Err_none;

    uint8_t* wasm = (uint8_t*)fib32_wasm;
    uint32_t fsize = fib32_wasm_len-1;

    printf("Loading WebAssembly...\n");
    IM3Environment env = m3_NewEnvironment ();
    if (!env) FATAL("m3_NewEnvironment failed");

    IM3Runtime runtime = m3_NewRuntime (env, 1024, NULL);
    if (!runtime) FATAL("m3_NewRuntime failed");

    IM3Module module;
    result = m3_ParseModule (env, &module, wasm, fsize);
    if (result) FATAL("m3_ParseModule: %s", result);

    result = m3_LoadModule (runtime, module);
    if (result) FATAL("m3_LoadModule: %s", result);

    IM3Function f;
    result = m3_FindFunction (&f, runtime, "fib");
    if (result) FATAL("m3_FindFunction: %s", result);

    printf("Running...\n");

    const char* i_argv[2] = { "24", NULL };
    result = m3_CallWithArgs (f, 1, i_argv);

    if (result) FATAL("m3_CallWithArgs: %s", result);

    long value = *(uint64_t*)(runtime->stack);
    printf("Result: %ld\n", value);
}


#define USER_TASK_STK_SIZE      32768
#define USER_TASK_PRIO          32

static u8 user_task_stk[USER_TASK_STK_SIZE];

void wasm3_task(void *data)
{
    printf("\nWasm3 v" M3_VERSION " on W600, build " __DATE__ " " __TIME__ "\n");

    u32 start = millis();
    run_wasm();
    u32 end = millis();

    printf("Elapsed: %ld ms\n", (end - start));
}

void UserMain(void)
{
    /* create task */
    tls_os_task_create(NULL,
            "wasm3",
            wasm3_task,
            (void*) 0,
            (void*) &user_task_stk,
            USER_TASK_STK_SIZE,
            USER_TASK_PRIO,
            0);
}
