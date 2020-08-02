//
//  m3_env.c
//
//  Created by Steven Massey on 4/19/19.
//  Copyright © 2019 Steven Massey. All rights reserved.
//

#include <stdarg.h>

#include "m3_env.h"
#include "m3_compile.h"
#include "m3_exec.h"
#include "m3_exception.h"
#include "m3_info.h"


M3Result AllocFuncType (IM3FuncType * o_functionType, u32 i_numArgs)
{
    size_t funcTypeSize = sizeof (M3FuncType) - 3 /* sizeof (argTypes [3]) */ + i_numArgs;

    return m3Alloc (o_functionType, u8, funcTypeSize);
}


bool  AreFuncTypesEqual  (const IM3FuncType i_typeA, const IM3FuncType i_typeB)
{
    if (i_typeA->returnType == i_typeB->returnType)
    {
        if (i_typeA->numArgs == i_typeB->numArgs)
        {
            return (memcmp (i_typeA->argTypes, i_typeB->argTypes, i_typeA->numArgs) == 0);
        }
    }

    return false;
}


void Runtime_ReleaseCodePages (IM3Runtime i_runtime)
{

}


void  Function_Release  (IM3Function i_function)
{
    m3Free (i_function->constants);

    // name can be an alias of fieldUtf8
    if (i_function->name != i_function->import.fieldUtf8)
    {
        m3Free (i_function->name);
    }

    FreeImportInfo (& i_function->import);

    if (i_function->ownsWasmCode)
        m3Free (i_function->wasm);

    // Function_FreeCompiledCode (func);

#   if (d_m3EnableCodePageRefCounting)
    {
        m3Free (i_function->codePageRefs);
        i_function->numCodePageRefs = 0;
    }
#   endif
}


void  Function_FreeCompiledCode (IM3Function i_function)
{
#   if (d_m3EnableCodePageRefCounting)
    {
        i_function->compiled = NULL;

        while (i_function->numCodePageRefs--)
        {
            IM3CodePage page = i_function->codePageRefs [i_function->numCodePageRefs];

            if (--(page->info.usageCount) == 0)
            {
//                printf ("free %p\n", page);
            }
        }

        m3Free (i_function->codePageRefs);

        Runtime_ReleaseCodePages (i_function->module->runtime);
    }
#   endif
}



cstr_t  GetFunctionName  (IM3Function i_function)
{
    if (i_function->import.fieldUtf8)
        return i_function->import.fieldUtf8;
    else
        return (i_function->name) ? i_function->name : "<unnamed>";
}


cstr_t  GetFunctionImportModuleName  (IM3Function i_function)
{
    return (i_function->import.moduleUtf8) ? i_function->import.moduleUtf8 : "";
}


u32  GetFunctionNumArgs  (IM3Function i_function)
{
    u32 numArgs = 0;

    if (i_function)
    {
        if (i_function->funcType)
            numArgs = i_function->funcType->numArgs;
    }

    return numArgs;
}


u32  GetFunctionNumReturns  (IM3Function i_function)
{
    u32 numReturns = 0;

    if (i_function->funcType)
        numReturns = i_function->funcType->returnType ? 1 : 0;

    return numReturns;
}


u8  GetFunctionReturnType  (IM3Function i_function)
{
    u8 returnType = c_m3Type_none;

    if (i_function->funcType)
        returnType = i_function->funcType->returnType;

    return returnType;
}


u32  GetFunctionNumArgsAndLocals (IM3Function i_function)
{
    if (i_function)
        return i_function->numLocals + GetFunctionNumArgs (i_function);
    else
        return 0;
}


void FreeImportInfo (M3ImportInfo * i_info)
{
    m3Free (i_info->moduleUtf8);
    m3Free (i_info->fieldUtf8);
}


IM3Environment  m3_NewEnvironment  ()
{
    IM3Environment env = NULL;
    m3Alloc (& env, M3Environment, 1);

    return env;
}


void  Environment_Release  (IM3Environment i_environment)
{
    IM3FuncType ftype = i_environment->funcTypes;

    while (ftype)
    {
        IM3FuncType next = ftype->next;
        m3Free (ftype);
        ftype = next;
    }                                                       m3log (runtime, "freeing %d pages from environment", CountCodePages (i_environment->pagesReleased));
    FreeCodePages (& i_environment->pagesReleased);
}


void  m3_FreeEnvironment  (IM3Environment i_environment)
{
    if (i_environment)
    {
        Environment_Release (i_environment);
        m3Free (i_environment);
    }
}


void  Environment_AddFuncType  (IM3Environment i_environment, IM3FuncType * io_funcType)
{
    IM3FuncType addType = * io_funcType;
    IM3FuncType newType = i_environment->funcTypes;

    while (newType)
    {
        if (AreFuncTypesEqual (newType, addType))
        {
            m3Free (addType);
            break;
        }

        newType = newType->next;
    }

    if (newType == NULL)
    {
        newType = addType;
        newType->next = i_environment->funcTypes;
        i_environment->funcTypes = newType;
    }

    * io_funcType = newType;
}


IM3CodePage RemoveCodePageOfCapacity (M3CodePage ** io_list, u32 i_minimumLineCount)
{
    IM3CodePage prev = NULL;
    IM3CodePage page = * io_list;

    while (page)
    {
        if (NumFreeLines (page) >= i_minimumLineCount)
        {                                                           d_m3Assert (page->info.usageCount == 0);
            IM3CodePage next = page->info.next;
            if (prev)
                prev->info.next = next; // mid-list
            else
                * io_list = next;       // front of list

            break;
        }

        prev = page;
        page = page->info.next;
    }

    return page;
}


IM3CodePage  Environment_AcquireCodePage (IM3Environment i_environment, u32 i_minimumLineCount)
{
    return RemoveCodePageOfCapacity (& i_environment->pagesReleased, i_minimumLineCount);
}


void  Environment_ReleaseCodePages  (IM3Environment i_environment, IM3CodePage i_codePageList)
{
    IM3CodePage end = i_codePageList;

    while (end)
    {
        end->info.lineIndex = 0; // reset page

        IM3CodePage next = end->info.next;
        if (not next)
            break;

        end = next;
    }

    if (end)
    {
        // push list to front
        end->info.next = i_environment->pagesReleased;
        i_environment->pagesReleased = i_codePageList;
    }
}


IM3Runtime  m3_NewRuntime  (IM3Environment i_environment, u32 i_stackSizeInBytes, void * unused)
{
    IM3Runtime runtime = NULL;
    m3Alloc (& runtime, M3Runtime, 1);

    if (runtime)
    {
        m3_ResetErrorInfo(runtime);

        runtime->environment = i_environment;

        m3Alloc (& runtime->stack, u8, i_stackSizeInBytes);

        if (runtime->stack)
        {
            runtime->numStackSlots = i_stackSizeInBytes / sizeof (m3slot_t);         m3log (runtime, "new stack: %p", runtime->stack);
        }
        else m3Free (runtime);
    }

    return runtime;
}


typedef void * (* ModuleVisitor) (IM3Module i_module, void * i_info);

void *  ForEachModule  (IM3Runtime i_runtime, ModuleVisitor i_visitor, void * i_info)
{
    void * r = NULL;

    IM3Module module = i_runtime->modules;

    while (module)
    {
        IM3Module next = module->next;
        r = i_visitor (module, i_info);
        if (r)
            break;

        module = next;
    }

    return r;
}


void *  _FreeModule  (IM3Module i_module, void * i_info)
{
    m3_FreeModule (i_module);
    return NULL;
}



void  FreeCompilationPatches  (IM3Compilation o)
{
    IM3BranchPatch patches = o->releasedPatches;

    while (patches)
    {
        IM3BranchPatch next = patches->next;
        m3Free (patches);
        patches = next;
    }
}


void  Runtime_Release  (IM3Runtime i_runtime)
{
    ForEachModule (i_runtime, _FreeModule, NULL);                   d_m3Assert (i_runtime->numActiveCodePages == 0);

    Environment_ReleaseCodePages (i_runtime->environment, i_runtime->pagesOpen);
    Environment_ReleaseCodePages (i_runtime->environment, i_runtime->pagesFull);

    FreeCompilationPatches (& i_runtime->compilation);

    m3Free (i_runtime->stack);
    m3Free (i_runtime->memory.mallocated);
}


void  m3_FreeRuntime  (IM3Runtime i_runtime)
{
    if (i_runtime)
    {
        m3_PrintProfilerInfo ();

        Runtime_Release (i_runtime);
        m3Free (i_runtime);
    }
}


M3Result  EvaluateExpression  (IM3Module i_module, void * o_expressed, u8 i_type, bytes_t * io_bytes, cbytes_t i_end)
{
    M3Result result = m3Err_none;

    m3slot_t stack [d_m3MaxFunctionSlots]; // stack on the stack

    // create a temporary runtime context
    M3Runtime runtime;
    M3_INIT (runtime);

    runtime.environment = i_module->runtime->environment;
    runtime.numStackSlots = d_m3MaxFunctionSlots;
    runtime.stack = & stack;

    IM3Runtime savedRuntime = i_module->runtime;
    i_module->runtime = & runtime;

    IM3Compilation o = & runtime.compilation;
    o->runtime = & runtime;
    o->module =  i_module;
    o->wasm =    * io_bytes;
    o->wasmEnd = i_end;

    o->block.depth = -1;  // so that root compilation depth = 0

    //  OPTZ: this code page could be erased after use.  maybe have 'empty' list in addition to full and open?
    o->page = AcquireCodePage (& runtime);  // AcquireUnusedCodePage (...)

    if (o->page)
    {
        pc_t m3code = GetPagePC (o->page);
        result = CompileBlock (o, i_type, c_waOp_block);

        if (not result)
        {
            m3ret_t r = Call (m3code, stack, NULL, d_m3OpDefaultArgs);
            result = runtime.runtimeError;

            if (r == 0 and not result)
            {
                if (SizeOfType (i_type) == sizeof (u32))
                {
                    * (u32 *) o_expressed = * ((u32 *) stack);
                }
                else
                {
                    * (u64 *) o_expressed = * ((u64 *) stack);
                }
            }
        }

        // TODO: EraseCodePage (...) see OPTZ above
        ReleaseCodePage (& runtime, o->page);
    }
    else result = m3Err_mallocFailedCodePage;

    runtime.stack = NULL;        // prevent free(stack) in ReleaseRuntime
    Runtime_Release (& runtime);
    i_module->runtime = savedRuntime;

    * io_bytes = o->wasm;

    return result;
}


M3Result  InitMemory  (IM3Runtime io_runtime, IM3Module i_module)
{
    M3Result result = m3Err_none;                                     //d_m3Assert (not io_runtime->memory.wasmPages);

    if (not i_module->memoryImported)
    {
        u32 maxPages = i_module->memoryInfo.maxPages;
        io_runtime->memory.maxPages = maxPages ? maxPages : 65536;

        result = ResizeMemory (io_runtime, i_module->memoryInfo.initPages);
    }

    return result;
}


M3Result  ResizeMemory  (IM3Runtime io_runtime, u32 i_numPages)
{
    M3Result result = m3Err_none;

    u32 numPagesToAlloc = i_numPages;

    M3Memory * memory = & io_runtime->memory;

#if 0 // Temporary fix for memory allocation
    if (memory->mallocated) {
        memory->numPages = i_numPages;
        memory->mallocated->end = memory->wasmPages + (memory->numPages * c_m3MemPageSize);
        return result;
    }

    i_numPagesToAlloc = 256;
#endif

    if (numPagesToAlloc <= memory->maxPages)
    {
        size_t numPageBytes = numPagesToAlloc * d_m3MemPageSize;

        // Limit the amount of memory that gets allocated
        if (io_runtime->memoryLimit) {
            numPageBytes = M3_MIN (numPageBytes, io_runtime->memoryLimit);
        }

        size_t numBytes = numPageBytes + sizeof (M3MemoryHeader);

        size_t numPreviousBytes = memory->numPages * d_m3MemPageSize;
        if (numPreviousBytes)
            numPreviousBytes += sizeof (M3MemoryHeader);

_       (m3Reallocate (& memory->mallocated, numBytes, numPreviousBytes));

# if d_m3LogRuntime
        M3MemoryHeader * oldMallocated = memory->mallocated;
# endif

        memory->numPages = numPagesToAlloc;

        memory->mallocated->length =  numPageBytes;
        memory->mallocated->runtime = io_runtime;

        memory->mallocated->maxStack = (m3slot_t *) io_runtime->stack + io_runtime->numStackSlots;

        m3log (runtime, "resized old: %p; mem: %p; length: %zu; pages: %d", oldMallocated, memory->mallocated, memory->mallocated->length, memory->numPages);
    }
    else result = m3Err_wasmMemoryOverflow;

    _catch: return result;
}


M3Result  InitGlobals  (IM3Module io_module)
{
    M3Result result = m3Err_none;

    if (io_module->numGlobals)
    {
        // placing the globals in their structs isn't good for cache locality, but i don't really know what the global
        // access patterns typcially look like yet.

        //          io_module->globalMemory = m3Alloc (m3reg_t, io_module->numGlobals);

        //          if (io_module->globalMemory)
        {
            for (u32 i = 0; i < io_module->numGlobals; ++i)
            {
                M3Global * g = & io_module->globals [i];                        m3log (runtime, "initializing global: %d", i);

                if (g->initExpr)
                {
                    bytes_t start = g->initExpr;
                    result = EvaluateExpression (io_module, & g->intValue, g->type, & start, g->initExpr + g->initExprSize);

                    if (not result)
                    {
                        // io_module->globalMemory [i] = initValue;
                    }
                    else break;
                }
                else
                {                                                               m3log (runtime, "importing global");

                }
            }
        }
        //          else result = ErrorModule (m3Err_mallocFailed, io_module, "could allocate globals for module: '%s", io_module->name);
    }

    return result;
}


M3Result  InitDataSegments  (M3Memory * io_memory, IM3Module io_module)
{
    M3Result result = m3Err_none;

    for (u32 i = 0; i < io_module->numDataSegments; ++i)
    {
        M3DataSegment * segment = & io_module->dataSegments [i];

        i32 segmentOffset;
        bytes_t start = segment->initExpr;
_       (EvaluateExpression (io_module, & segmentOffset, c_m3Type_i32, & start, segment->initExpr + segment->initExprSize));

        m3log (runtime, "loading data segment: %d; size: %d; offset: %d", i, segment->size, segmentOffset);

        if (io_memory->mallocated)
        {
            u8 * dest = m3MemData (io_memory->mallocated) + segmentOffset;

            if ((size_t) segmentOffset + segment->size <= io_memory->mallocated->length)
                memcpy (dest, segment->data, segment->size);
            else
                _throw ("data segment overflowing linear memory");
        }
        else _throw ("unallocated linear memory");
    }

    _catch: return result;
}


M3Result  InitElements  (IM3Module io_module)
{
    M3Result result = m3Err_none;

    bytes_t bytes = io_module->elementSection;
    cbytes_t end = io_module->elementSectionEnd;

    for (u32 i = 0; i < io_module->numElementSegments; ++i)
    {
        u32 index;
_       (ReadLEB_u32 (& index, & bytes, end));

        if (index == 0)
        {
            i32 offset;
_           (EvaluateExpression (io_module, & offset, c_m3Type_i32, & bytes, end));

            u32 numElements;
_           (ReadLEB_u32 (& numElements, & bytes, end));

            u32 endElement = numElements + offset;

            if (endElement > offset) // TODO: check this, endElement depends on offset
            {
_               (m3ReallocArray (& io_module->table0, IM3Function, endElement, io_module->table0Size));

                io_module->table0Size = endElement;

                for (u32 e = 0; e < numElements; ++e)
                {
                    u32 functionIndex;
_                       (ReadLEB_u32 (& functionIndex, & bytes, end));

                    if (functionIndex < io_module->numFunctions)
                    {
                        IM3Function function = & io_module->functions [functionIndex];      d_m3Assert (function); //printf ("table: %s\n", function->name);
                        io_module->table0 [e + offset] = function;
                    }
                    else _throw ("function index out of range");
                }
            }
            else _throw ("table overflow");
        }
        else _throw ("element table index must be zero for MVP");
    }

    _catch: return result;
}

M3Result  InitStartFunc  (IM3Module io_module)
{
    M3Result result = m3Err_none;

    if (io_module->startFunction >= 0)
    {
        IM3Function function = & io_module->functions [io_module->startFunction];

        if (not function->compiled)
        {
_           (Compile_Function (function));
        }

_       (m3_Call(function));
    }

    _catch: return result;
}

// TODO: deal with main + side-modules loading efforcement
M3Result  m3_LoadModule  (IM3Runtime io_runtime, IM3Module io_module)
{
    M3Result result = m3Err_none;

    if (not io_module->runtime)
    {
        io_module->runtime = io_runtime;
        M3Memory * memory = & io_runtime->memory;

_       (InitMemory (io_runtime, io_module));
_       (InitGlobals (io_module));
_       (InitDataSegments (memory, io_module));
_       (InitElements (io_module));

        io_module->next = io_runtime->modules;
        io_runtime->modules = io_module;

        // Functions expect module to be linked to a runtime, so we call start here
_       (InitStartFunc (io_module));
    }
    else result = m3Err_moduleAlreadyLinked;

    if (result)
        io_module->runtime = NULL;

    _catch: return result;
}


void *  v_FindFunction  (IM3Module i_module, const char * const i_name)
{
    for (u32 i = 0; i < i_module->numFunctions; ++i)
    {
        IM3Function f = & i_module->functions [i];

        if (f->name)
        {
            if (strcmp (f->name, i_name) == 0)
                return f;
        }
    }

    return NULL;
}


M3Result  m3_FindFunction  (IM3Function * o_function, IM3Runtime i_runtime, const char * const i_functionName)
{
    M3Result result = m3Err_none;

    if (!i_runtime->modules) {
        return "no modules loaded";
    }

    IM3Function function = (IM3Function) ForEachModule (i_runtime, (ModuleVisitor) v_FindFunction, (void *) i_functionName);

    if (function)
    {
        if (not function->compiled)
        {
            result = Compile_Function (function);
            if (result)
                function = NULL;
        }
    }
    else result = ErrorModule (m3Err_functionLookupFailed, i_runtime->modules, "'%s'", i_functionName);

    * o_function = function;

    return result;
}


M3Result  m3_Call  (IM3Function i_function)
{
    return m3_CallWithArgs (i_function, 0, NULL);
}


M3Result  m3_CallWithArgs  (IM3Function i_function, uint32_t i_argc, const char * const * i_argv)
{
    M3Result result = m3Err_none;

    if (i_function->compiled)
    {
        IM3Module module = i_function->module;

        IM3Runtime runtime = module->runtime;
        runtime->argc = i_argc;
        runtime->argv = i_argv;
        if (i_function->name and strcmp (i_function->name, "_start") == 0) // WASI
            i_argc = 0;

        IM3FuncType ftype = i_function->funcType;                               m3log (runtime, "calling %s", SPrintFuncTypeSignature (ftype));
        if (i_argc != ftype->numArgs)
            _throw (m3Err_argumentCountMismatch);

        // args are always 64-bit aligned
        u64 * stack = (u64 *) runtime->stack;

        // The format is currently not user-friendly by default,
        // as this is used in spec tests
        for (u32 i = 0; i < ftype->numArgs; ++i)
        {
            u64 * s = & stack [i];
            ccstr_t str = i_argv[i];

            switch (ftype->argTypes[i]) {
#ifdef USE_HUMAN_FRIENDLY_ARGS
            case c_m3Type_i32:  *(i32*)(s) = atol(str);  break;
            case c_m3Type_i64:  *(i64*)(s) = atoll(str); break;
            case c_m3Type_f32:  *(f32*)(s) = atof(str);  break;
            case c_m3Type_f64:  *(f64*)(s) = atof(str);  break;
#else
            case c_m3Type_i32:
            case c_m3Type_f32:  *(u32*)(s) = strtoul(str, NULL, 10);  break;
            case c_m3Type_i64:
            case c_m3Type_f64:  *(u64*)(s) = strtoull(str, NULL, 10); break;
#endif
            default: _throw("unknown argument type");
            }
        }

        m3StackCheckInit();
_       ((M3Result) Call (i_function->compiled, (m3stack_t) stack, runtime->memory.mallocated, d_m3OpDefaultArgs));

#if d_m3LogOutput
        switch (ftype->returnType) {
        case c_m3Type_none: fprintf (stderr, "Result: <Empty Stack>\n"); break;
#ifdef USE_HUMAN_FRIENDLY_ARGS
        case c_m3Type_i32:  fprintf (stderr, "Result: %" PRIi32 "\n", *(i32*)(stack));  break;
        case c_m3Type_i64:  fprintf (stderr, "Result: %" PRIi64 "\n", *(i64*)(stack));  break;
        case c_m3Type_f32:  fprintf (stderr, "Result: %f\n",   *(f32*)(stack));  break;
        case c_m3Type_f64:  fprintf (stderr, "Result: %lf\n",  *(f64*)(stack));  break;
#else
        case c_m3Type_i32:
        case c_m3Type_f32:
            fprintf (stderr, "Result: %u\n",  *(u32*)(stack));  break;
        case c_m3Type_i64:
        case c_m3Type_f64:
            fprintf (stderr, "Result: %" PRIu64 "\n", *(u64*)(stack));  break;
#endif // USE_HUMAN_FRIENDLY_ARGS
        default: _throw("unknown return type");
        }

#if d_m3LogNativeStack
        size_t stackUsed =  m3StackGetMax();
        fprintf (stderr, "Native stack used: %d\n", stackUsed);
#endif // d_m3LogNativeStack

#endif // d_m3LogOutput

        //u64 value = * (u64 *) (stack);
        //m3log (runtime, "return64: %" PRIu64 " return32: %u", value, (u32) value);
    }
    else _throw (m3Err_missingCompiledCode);

    _catch: return result;
}

#if 0
M3Result  m3_CallMain  (IM3Function i_function, uint32_t i_argc, const char * const * i_argv)
{
    M3Result result = m3Err_none;

    if (i_function->compiled)
    {
        IM3Module module = i_function->module;

        IM3Runtime runtime = module->runtime;

        u8 * linearMemory = runtime->memory.wasmPages;

        m3stack_t stack = (m3stack_t) runtime->stack;

        if (i_argc)
        {
            IM3Memory memory = & runtime->memory;
            // FIX: memory allocation in general

            i32 offset = AllocatePrivateHeap (memory, sizeof (i32) * i_argc);

            i32 * pointers = (i32 *) (memory->wasmPages + offset);

            for (u32 i = 0; i < i_argc; ++i)
            {
                size_t argLength = strlen (i_argv [i]) + 1;

                if (argLength < 4000)
                {
                    i32 o = AllocatePrivateHeap (memory, (i32) argLength);
                    memcpy (memory->wasmPages + o, i_argv [i], argLength);

                    * pointers++ = o;
                }
                else _throw ("insane argument string length");
            }

            stack [0] = i_argc;
            stack [1] = offset;
        }

_       ((M3Result)Call (i_function->compiled, stack, linearMemory, d_m3OpDefaultArgs));

        //u64 value = * (u64 *) (stack);
        //m3log (runtime, "return64: % " PRIu64 " return32: %" PRIu32, value, (u32) value);
    }
    else _throw (m3Err_missingCompiledCode);

    _catch: return result;
}
#endif


void  ReleaseCodePageNoTrack (IM3Runtime i_runtime, IM3CodePage i_codePage)
{
    if (i_codePage)
    {
        IM3CodePage * list;

        bool pageFull = (NumFreeLines (i_codePage) < d_m3CodePageFreeLinesThreshold);
        if (pageFull)
            list = & i_runtime->pagesFull;
        else
            list = & i_runtime->pagesOpen;

        PushCodePage (list, i_codePage);                        m3log (emit, "release page: %d to queue: '%s'", i_codePage->info.sequence, pageFull ? "full" : "open")
    }
}


IM3CodePage  AcquireCodePageWithCapacity  (IM3Runtime i_runtime, u32 i_minLineCount)
{
    IM3CodePage page = RemoveCodePageOfCapacity (& i_runtime->pagesOpen, i_minLineCount);

    if (not page)
    {
        page = Environment_AcquireCodePage (i_runtime->environment, i_minLineCount);

        if (not page)
            page = NewCodePage (i_minLineCount);

        if (page)
            i_runtime->numCodePages++;
    }

    if (page)
    {                                                            m3log (emit, "acquire page: %d", page->info.sequence);
        i_runtime->numActiveCodePages++;
    }

    return page;
}


IM3CodePage  AcquireCodePage  (IM3Runtime i_runtime)
{
    return AcquireCodePageWithCapacity (i_runtime, d_m3CodePageFreeLinesThreshold);
}


void  ReleaseCodePage  (IM3Runtime i_runtime, IM3CodePage i_codePage)
{
    if (i_codePage)
    {
        ReleaseCodePageNoTrack (i_runtime, i_codePage);
        i_runtime->numActiveCodePages--;

#       if defined (DEBUG)
            u32 numOpen = CountCodePages (i_runtime->pagesOpen);
            u32 numFull = CountCodePages (i_runtime->pagesFull);

            m3log (runtime, "runtime: %p; open-pages: %d; full-pages: %d; active: %d; total: %d", i_runtime, numOpen, numFull, i_runtime->numActiveCodePages, i_runtime->numCodePages);

            d_m3Assert (numOpen + numFull + i_runtime->numActiveCodePages == i_runtime->numCodePages);

#           if d_m3LogCodePages
                dump_code_page (i_codePage, /* startPC: */ NULL);
#           endif
#       endif
    }
}


#if d_m3VerboseLogs
M3Result  m3Error  (M3Result i_result, IM3Runtime i_runtime, IM3Module i_module, IM3Function i_function,
                    const char * const i_file, u32 i_lineNum, const char * const i_errorMessage, ...)
{
    if (i_runtime)
    {
        i_runtime->error = (M3ErrorInfo){ i_result, i_runtime, i_module, i_function, i_file, i_lineNum };
        i_runtime->error.message = i_runtime->error_message;

        va_list args;
        va_start (args, i_errorMessage);
        vsnprintf (i_runtime->error_message, sizeof(i_runtime->error_message), i_errorMessage, args);
        va_end (args);
    }

    return i_result;
}
#endif


void  m3_GetErrorInfo  (IM3Runtime i_runtime, M3ErrorInfo* info)
{
    *info = i_runtime->error;

    m3_ResetErrorInfo (i_runtime);
}


void m3_ResetErrorInfo (IM3Runtime i_runtime)
{
    M3_INIT(i_runtime->error);
    i_runtime->error.message = "";
}

uint8_t *  m3_GetMemory  (IM3Runtime i_runtime, uint32_t * o_memorySizeInBytes, uint32_t i_memoryIndex)
{
    uint8_t * memory = NULL;
    d_m3Assert (i_memoryIndex == 0);

    if (i_runtime)
    {
        u32 size = (u32) i_runtime->memory.mallocated->length;

        if (o_memorySizeInBytes)
            * o_memorySizeInBytes = size;

        if (size)
            memory = m3MemData (i_runtime->memory.mallocated);
    }

    return memory;
}
