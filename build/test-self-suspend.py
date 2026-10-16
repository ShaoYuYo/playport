#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run actual native suspend/resume functions with a pthread server/select model.

Pass the series-applied Madeira tree. This checks the client return barrier,
not Mach holding, wineserver IPC, FEX or a complete game on iOS.
"""
from pathlib import Path
import os,subprocess,sys
repo=Path(__file__).resolve().parent.parent
tree=Path(sys.argv[1]).resolve()
source=(tree/'build/ntdll-unix/thread_ios.c').read_text()
out=repo/'.work/self-suspend-test';out.mkdir(parents=True,exist_ok=True)
os.environ['TMPDIR']=str(out)
def extract(name):
 a=source.index('NTSTATUS WINAPI '+name+'(')
 b=source.index('\n/******************************************************************************',a)
 return source[a:b]
functions=extract('NtSuspendThread')+extract('NtResumeThread')
prefix=r'''
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#define WINE_IOS 1
#define WINAPI
typedef unsigned int NTSTATUS,ULONG;
typedef intptr_t HANDLE;
typedef int BOOL;
#define GetCurrentThread() ((HANDLE)-2)
#define HandleToULong(h) ((unsigned int)(h))
#define wine_server_obj_handle(h) (h)
#define SELECT_INTERRUPTIBLE 1
static _Thread_local struct {struct {HANDLE UniqueThread;} ClientId;} teb;
#define NtCurrentTeb() (&teb)
static _Thread_local unsigned int self;
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed=PTHREAD_COND_INITIALIZER;
static unsigned int counts[3],gate_calls,race_resume;
struct request {unsigned int operation;HANDLE handle;};
struct response {ULONG count;};
#define suspend_thread 1
#define resume_thread 2
#define SERVER_START_REQ(op) {struct request request={.operation=op};struct response response={0};struct request *req=&request;struct response *reply=&response;
#define SERVER_END_REQ }
/* Match Wine's request macros, exposing the response for the mock server. */
static unsigned int mock_call(struct request *req,struct response *reply){
 unsigned int slot;
 if(req->handle==GetCurrentThread())slot=self;
 else if(req->handle==100)slot=1;
 else if(req->handle==101)slot=2;
 else return 9;
 pthread_mutex_lock(&lock);
 reply->count=counts[slot];
 if(req->operation==suspend_thread){
  if(counts[slot]==127){pthread_mutex_unlock(&lock);return 10;}
  ++counts[slot];
  if(race_resume && slot==self){--counts[slot];race_resume=0;}
 }else if(counts[slot])--counts[slot];
 pthread_cond_broadcast(&changed);
 pthread_mutex_unlock(&lock);
 return 0;
}
#define wine_server_call(req) mock_call(req,reply)
static __attribute__((unused)) unsigned int server_select(const void *op,unsigned int size,unsigned int flags,
 int timeout,void *context,void *apc){
 assert(!op && !size && flags==SELECT_INTERRUPTIBLE && !timeout && !context && !apc);
 pthread_mutex_lock(&lock);++gate_calls;
 while(counts[self])pthread_cond_wait(&changed,&lock);
 pthread_mutex_unlock(&lock);return 0;
}
static void pause_briefly(void){struct timespec t={0,20000000};nanosleep(&t,0);}
'''
suffix=r'''
static atomic_int returned;
static HANDLE trial_handle;
static ULONG trial_old;
static int null_count;
static void *trial(void *unused){
 (void)unused;self=1;teb.ClientId.UniqueThread=0x4c;
 assert(!NtSuspendThread(trial_handle,null_count?NULL:&trial_old));
 atomic_store(&returned,1);return NULL;
}
static void wait_count(unsigned int n){
 pthread_mutex_lock(&lock);while(counts[1]!=n)pthread_cond_wait(&changed,&lock);pthread_mutex_unlock(&lock);
}
static void run_trial(HANDLE handle,unsigned int initial){
 counts[1]=initial;atomic_store(&returned,0);trial_handle=handle;trial_old=999;
 pthread_t worker;assert(!pthread_create(&worker,NULL,trial,NULL));
 wait_count(initial+1);pause_briefly();
#ifdef EXPECT_BROKEN
 assert(atomic_load(&returned)==1);
#else
 assert(!atomic_load(&returned));
#endif
 ULONG old=999;
 if(initial){assert(!NtResumeThread(100,&old) && old==2);pause_briefly();
#ifndef EXPECT_BROKEN
 assert(!atomic_load(&returned));
#endif
 }
 assert(!NtResumeThread(100,&old) && old==1);
 assert(!pthread_join(worker,NULL));assert(atomic_load(&returned));
 if(!null_count)assert(trial_old==initial);
}
#ifndef EXPECT_BROKEN
static unsigned int job,finished;
static unsigned char *pixels;
static int stopping;
static void *draw_worker(void *unused){
 (void)unused;self=1;
 server_select(NULL,0,SELECT_INTERRUPTIBLE,0,NULL,NULL);
 for(unsigned int expected=1;;expected++){
  pthread_mutex_lock(&lock);
  if(stopping){pthread_mutex_unlock(&lock);break;}
  assert(job==expected);unsigned char *target=pixels;
  pthread_mutex_unlock(&lock);
  for(unsigned int i=0;i<4096;i++)target[i]=(unsigned char)expected;
  pthread_mutex_lock(&lock);finished=expected;pthread_cond_broadcast(&changed);pthread_mutex_unlock(&lock);
  assert(!NtSuspendThread(GetCurrentThread(),NULL));
 }
 return NULL;
}
static void resume_worker(void){
 ULONG old;
 do {assert(!NtResumeThread(100,&old));}while(!old);
 assert(old==1);
}
static void draw_tasks(void){
 counts[1]=1;pthread_t worker;assert(!pthread_create(&worker,NULL,draw_worker,NULL));
 for(unsigned int n=1;n<=10000;n++){
  unsigned char *buffer=malloc(4096);assert(buffer);
  pthread_mutex_lock(&lock);job=n;pixels=buffer;pthread_mutex_unlock(&lock);
  resume_worker();
  pthread_mutex_lock(&lock);while(finished!=n)pthread_cond_wait(&changed,&lock);pthread_mutex_unlock(&lock);
  for(unsigned int i=0;i<4096;i++)assert(buffer[i]==(unsigned char)n);
  free(buffer); /* Same lifetime as a completed bitmap task. */
 }
 pthread_mutex_lock(&lock);stopping=1;pthread_mutex_unlock(&lock);
 resume_worker();assert(!pthread_join(worker,NULL));assert(finished==10000);
}
#endif
int main(void){
 self=0;teb.ClientId.UniqueThread=0x2c;
 run_trial(GetCurrentThread(),0);
#ifdef EXPECT_BROKEN
 puts("Baseline reproduced: self-suspend returned with suspend count 1 and no resume");
#else
 run_trial(100,0);run_trial(100,1);null_count=1;run_trial(GetCurrentThread(),0);null_count=0;
 ULONG old=42;unsigned int calls=gate_calls;
 assert(NtSuspendThread(999,&old)==9 && old==42 && gate_calls==calls);
 counts[2]=127;assert(NtSuspendThread(101,&old)==10 && old==42 && gate_calls==calls);counts[2]=0;
 assert(!NtSuspendThread(101,&old) && old==0 && counts[2]==1);
 assert(!NtResumeThread(101,&old) && old==1 && !counts[2]);
 race_resume=1;assert(!NtSuspendThread(GetCurrentThread(),&old) && !counts[0] && old==0);
 draw_tasks();
 puts("Self-suspend return barrier: pseudo/real self handles, nested resume, null count, failures, other target, racing resume and 10,000 bitmap task lifetimes passed");
#endif
}
'''
for broken in (True,False):
 code=functions
 if broken:
  a=code.index('#ifdef WINE_IOS');b=code.index('#endif',a)+len('#endif')
  code=code[:a]+code[b:]
 name='before' if broken else 'after';p=out/(name+'.c');exe=out/name
 p.write_text(prefix+code+suffix)
 command=['clang','-std=c11','-O1','-Wall','-Wextra','-Werror','-pthread','-fsanitize=address,undefined']
 if broken:command+=['-DEXPECT_BROKEN']
 subprocess.run(command+[str(p),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True,timeout=35)
