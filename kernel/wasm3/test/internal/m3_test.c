//
//  m3_test.c
//
//  Created by Steven Massey on 2/27/20.
//  Copyright © 2020 Steven Massey. All rights reserved.
//

#include <stdio.h>

//#include "m3_ext.h"
#include "m3_bind.h"

#define Test(NAME) printf ("\n  test: %s\n", #NAME);
#define expect(TEST) if (not (TEST)) { printf ("failed: (%s) on line: %d\n", #TEST, __LINE__); }

int  main  (int i_argc, const char  * i_argv [])
{
    Test (signatures)
    {
        M3Result result;
        
        IM3FuncType ftype = NULL;
        
        result = SignatureToFuncType (& ftype, "");                     expect (result == m3Err_malformedFunctionSignature)
        m3Free (ftype);
        
        result = SignatureToFuncType (& ftype, "()");                   expect (result == m3Err_malformedFunctionSignature)
        m3Free (ftype);

        result = SignatureToFuncType (& ftype, " v () ");               expect (result == m3Err_none)
                                                                        expect (ftype->returnType == c_m3Type_none)
                                                                        expect (ftype->numArgs == 0)
        m3Free (ftype);

        result = SignatureToFuncType (& ftype, "f(IiF)");               expect (result == m3Err_none)
                                                                        expect (ftype->returnType == c_m3Type_f32)
                                                                        expect (ftype->numArgs == 3)
                                                                        expect (ftype->argTypes [0] == c_m3Type_i64)
                                                                        expect (ftype->argTypes [1] == c_m3Type_i32)
                                                                        expect (ftype->argTypes [2] == c_m3Type_f64)
        
        IM3FuncType ftype2 = NULL;
        result = SignatureToFuncType (& ftype2, "f(I i F)");            expect (result == m3Err_none);
                                                                        expect (AreFuncTypesEqual (ftype, ftype2));
        m3Free (ftype);
        m3Free (ftype2);
    }
    
    
    Test (codepages.simple)
    {
        M3Environment env = { 0 };
        M3Runtime runtime = { 0 };
        runtime.environment = & env;
        
        IM3CodePage page = AcquireCodePage (& runtime);                 expect (page);
                                                                        expect (runtime.numCodePages == 1);
                                                                        expect (runtime.numActiveCodePages == 1);
        
        IM3CodePage page2 = AcquireCodePage (& runtime);                expect (page2);
                                                                        expect (runtime.numCodePages == 2);
                                                                        expect (runtime.numActiveCodePages == 2);

        ReleaseCodePage (& runtime, page);                              expect (runtime.numCodePages == 2);
                                                                        expect (runtime.numActiveCodePages == 1);

        ReleaseCodePage (& runtime, page2);                             expect (runtime.numCodePages == 2);
                                                                        expect (runtime.numActiveCodePages == 0);
        
        Runtime_Release (& runtime);                                    expect (CountCodePages (env.pagesReleased) == 2);
        Environment_Release (& env);                                    expect (CountCodePages (env.pagesReleased) == 0);
    }
    
    Test (codepages.b)
    {
        const u32 c_numPages = 2000;
        IM3CodePage pages [2000] = { NULL };
        
        M3Environment env = { 0 };
        M3Runtime runtime = { 0 };
        runtime.environment = & env;

        u32 numActive = 0;
        
        for (u32 i = 0; i < 2000000; ++i)
        {
            u32 index = rand () % c_numPages;   // printf ("%5u ", index);
            
            if (pages [index] == NULL)
            {
//                printf ("acq\n");
                pages [index] = AcquireCodePage (& runtime);
                ++numActive;
            }
            else
            {
//                printf ("rel\n");
                ReleaseCodePage (& runtime, pages [index]);
                pages [index] = NULL;
                --numActive;
            }
                
            expect (runtime.numActiveCodePages == numActive);
        }
        
        printf ("num pages: %d\n", runtime.numCodePages);
        
        for (u32 i = 0; i < c_numPages; ++i)
        {
            if (pages [i])
            {
                ReleaseCodePage (& runtime, pages [i]);
                pages [i] = NULL;
                --numActive;                                            expect (runtime.numActiveCodePages == numActive);
            }
        }
        
        Runtime_Release (& runtime);
        Environment_Release (& env);
    }
    
    return 0;
}
