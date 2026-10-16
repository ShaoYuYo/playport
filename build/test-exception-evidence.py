#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the production bounded exception-key and guest-stack policies."""
from pathlib import Path
import os,subprocess,sys
r=Path(__file__).resolve().parent.parent;t=Path(sys.argv[1]).resolve()
out=r/'.work/exception-evidence-test';out.mkdir(parents=True,exist_ok=True)
os.environ['TMPDIR']=str(out)
code=r'''
#include <stdint.h>
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
typedef int32_t LONG;
static LONG InterlockedCompareExchange(volatile LONG *p,LONG value,LONG expected){__atomic_compare_exchange_n(p,&expected,value,0,__ATOMIC_ACQ_REL,__ATOMIC_ACQUIRE);return expected;}
static LONG InterlockedExchange(volatile LONG *p,LONG value){return __atomic_exchange_n(p,value,__ATOMIC_RELEASE);}
#include "wow64_exception_evidence.h"
static struct wow64_exception_evidence threaded;
static unsigned claimed;
static void *worker(void *unused){(void)unused;for(int i=0;i<10000;i++){struct wow64_exception_key k={1,0xc0000005,0x1234,0x5678,0x9000};if(wow64_exception_claim(&threaded,k))__atomic_fetch_add(&claimed,1,__ATOMIC_RELAXED);}return 0;}
int main(void){
 struct wow64_exception_evidence state={0};
 struct wow64_exception_key key={1,0xc0000005,0x1234,0x5678,0x9000};
 assert(wow64_exception_claim(&state,key)==1);
 for(int i=0;i<100000;i++)assert(!wow64_exception_claim(&state,key));
 key.code=0xe06d7363;assert(wow64_exception_claim(&state,key)==2);
 key.caller++;assert(wow64_exception_claim(&state,key)==3);
 key.pc++;assert(wow64_exception_claim(&state,key)==4);
 key.page++;assert(wow64_exception_claim(&state,key)==5);
 key.tid++;assert(wow64_exception_claim(&state,key)==6);
 for(int i=6;i<32;i++){key.pc++;assert(wow64_exception_claim(&state,key)==(unsigned)i+1);}
 key.pc++;assert(!wow64_exception_claim(&state,key) && state.used==32);
 state.lock=1;assert(!wow64_exception_claim(&state,key));state.lock=0;
 assert(wow64_exception_stack_span(0x10000,0x20000,0x10000,8));
 assert(wow64_exception_stack_span(0x10000,0x20000,0x1fff8,8));
 assert(!wow64_exception_stack_span(0x10000,0x20000,0xffff,8));
 assert(!wow64_exception_stack_span(0x10000,0x20000,0x1fff9,8));
 assert(!wow64_exception_stack_span(0x10000,0x20000,0x20000,1));
 assert(!wow64_exception_stack_span(0x10000,0x20000,0x1fffc,8));
 assert(!wow64_exception_stack_span(0x10000,0x20000,0xfffffff0,32));
 assert(!wow64_exception_stack_span(0x10000,0x20000,0x10000,UINT32_MAX));
 assert(!wow64_exception_stack_span(0,0x20000,0x10000,8));
 assert(!wow64_exception_stack_span(0x20000,0x10000,0x10000,8));
 assert(!wow64_exception_stack_span(0x10000,0x20000,0x10000,0));
 pthread_t threads[8];for(int i=0;i<8;i++)assert(!pthread_create(&threads[i],0,worker,0));
 for(int i=0;i<8;i++)assert(!pthread_join(threads[i],0));
 assert(claimed==1 && threaded.used==1);
 puts("Production policy: duplicate flood, 32 unique keys, busy lock, 11 stack bounds, 80,000 concurrent duplicate calls passed");
}
'''
p=out/'test.c';p.write_text(code);exe=out/'test'
subprocess.run(['clang','-std=c11','-O1','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-pthread','-I'+str(t/'dlls/wow64'),str(p),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
source=(t/'dlls/wow64/syscall.c').read_text()
a=source.index('static int read_exception_stack(');b=source.index('\n/**********************************************************************',a)
helper=source[a:b]
prefix=code[:code.index('static struct wow64_exception_evidence threaded;')]+r'''
#include <string.h>
typedef uint32_t ULONG;
typedef size_t SIZE_T;
typedef struct {struct {ULONG StackLimit,StackBase,ExceptionList;} Tib;} TEB32;
typedef struct {ULONG Eip,Esp,Ebp,Eax,Ebx,Ecx,Edx,Esi,Edi,SegFs;} I386_CONTEXT;
typedef struct {ULONG ExceptionCode,ExceptionFlags,NumberParameters,ExceptionInformation[15];} EXCEPTION_RECORD32;
#define STATUS_ACCESS_VIOLATION 0xc0000005U
static struct {ULONG LastErrorValue,LastStatusValue;} native;
static TEB32 teb;
static unsigned char memory[0x10000];
static unsigned reads,logs;
static int fail;
static uintptr_t wow64_window_base=1;
#define NtCurrentTeb() (&native)
static TEB32 *NtCurrentTeb32(void){return &teb;}
#define GetCurrentThreadId() 1U
#define GetCurrentProcess() 0
#define ERR(...) (++logs)
static void *wow64_to_host(ULONG address){return memory+(address-0x10000);}
static int NtReadVirtualMemory(int process,const void *from,void *to,SIZE_T bytes,SIZE_T *done){
 (void)process;reads++;native.LastErrorValue=999;native.LastStatusValue=888;
 if(fail)return 1;
 assert((const unsigned char*)from>=memory && bytes<=sizeof(memory)-((const unsigned char*)from-memory));
 memcpy(to,from,bytes);*done=bytes;return 0;
}
'''
suffix=r'''
int main(void){
 teb.Tib.StackLimit=0x10000;teb.Tib.StackBase=0x20000;teb.Tib.ExceptionList=0x11200;
 I386_CONTEXT ctx={.Eip=0x401000,.Esp=0x11000,.Ebp=0x11100};
 EXCEPTION_RECORD32 rec={.ExceptionCode=0xc0000005,.NumberParameters=2,.ExceptionInformation={0,0x780}};
 ULONG frame[]={~0U,0x402000};memcpy(wow64_to_host(ctx.Ebp),frame,sizeof(frame));
 memcpy(wow64_to_host(teb.Tib.ExceptionList),frame,sizeof(frame));
 native.LastErrorValue=42;native.LastStatusValue=43;
 report_windowed_exception(&rec,&ctx);
 assert(reads==3 && logs==4 && native.LastErrorValue==42 && native.LastStatusValue==43);
 report_windowed_exception(&rec,&ctx);assert(reads==4 && logs==4);
 fail=1;rec.ExceptionCode=0xe06d7363;
 report_windowed_exception(&rec,&ctx);
 assert(native.LastErrorValue==42 && native.LastStatusValue==43 && logs==7);
 unsigned before=reads;ULONG words[2];
 assert(!read_exception_stack(&teb,0x780,words,sizeof(words)));
 assert(!read_exception_stack(&teb,0xfffffff0,words,sizeof(words)) && reads==before);
 wow64_window_base=0;report_windowed_exception(&rec,&ctx);assert(reads==before);
 puts("Production logger: fault-contained failed reads, duplicate suppression, stack-only reads and both thread error fields preserved");
}
'''
p=out/'logger.c';p.write_text(prefix+helper+suffix);exe=out/'logger'
subprocess.run(['clang','-std=c11','-O1','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-I'+str(t/'dlls/wow64'),str(p),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
