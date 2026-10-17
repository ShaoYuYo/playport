// SPDX-License-Identifier: GPL-3.0-or-later
#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <unistd.h>
typedef uint32_t DWORD;
typedef int NTSTATUS;
#define STATUS_SUCCESS 0
#define STATUS_NO_MEMORY 12
#define HandleToULong(x) ((DWORD)(uintptr_t)(x))
typedef struct {void *Peb;struct {void *UniqueProcess;} ClientId;} TEB;
struct thread_data {void *stack; void *owner; DWORD pid; pthread_t thread; _Atomic int ready; int native;};
static _Thread_local TEB *teb;
static pthread_key_t ios_teb_tls_key;
static int ios_teb_tls_slot_offset;
static DWORD pid=32;
static sigset_t server_block_set;
static int nb_threads;
static const size_t kernel_stack_size=2<<20;
static _Atomic int completed;
static int fail_create;
static TEB *NtCurrentTeb(void){return teb;}
static void *get_kernel_stack(struct thread_data *data){return data->stack;}
static void InterlockedIncrement(int *p){__atomic_add_fetch(p,1,__ATOMIC_SEQ_CST);}
static void InterlockedDecrement(int *p){__atomic_sub_fetch(p,1,__ATOMIC_SEQ_CST);}
static void server_init_thread(struct thread_data *data);
DWORD ios_current_pid(void);
void *ios_jit_current_peb(void);
static int test_pthread_create(pthread_t *t,const pthread_attr_t *a,void*(*fn)(void*),void *arg){
    if(fail_create)return 11;
    return pthread_create(t,a,fn,arg);
}
#define pthread_create test_pthread_create
#include "actual_worker.h"
#undef pthread_create
static void server_init_thread(struct thread_data *data){
    data->thread=pthread_self();
    atomic_store(&data->ready,1);
    // Before any pipe handoff the no-TEB worker must resolve its creator.
    assert(!NtCurrentTeb());
    assert(ios_jit_current_peb()==data->owner);
    assert(ios_current_pid()==data->pid);
    // A real guest TEB takes precedence over inherited native context.
    TEB real={.Peb=(void*)0x555000,.ClientId={.UniqueProcess=(void*)99}};
    teb=&real;pthread_setspecific(ios_teb_tls_key,teb);
    assert(ios_jit_current_peb()==real.Peb && ios_current_pid()==99);
    teb=NULL;pthread_setspecific(ios_teb_tls_key,NULL);
    assert(ios_jit_current_peb()==data->owner && ios_current_pid()==data->pid);
    // Nested native workers inherit without inventing a TEB.
    if(data->native){
        struct thread_data nested={.owner=data->owner,.pid=data->pid};
        assert(!posix_memalign(&nested.stack,4096,kernel_stack_size));
        assert(!spawn_thread(&nested));
        while(!atomic_load(&nested.ready))usleep(1000);
        pthread_join(nested.thread,NULL);free(nested.stack);
    }
    InterlockedDecrement(&nb_threads);atomic_fetch_add(&completed,1);
}
int main(void){
    pthread_key_create(&ios_teb_tls_key,NULL);sigemptyset(&server_block_set);
    assert(ios_jit_current_peb()==NULL && ios_current_pid()==32);
    for(unsigned batch=0;batch<8;batch++){
        struct thread_data jobs[8]={0};
        for(unsigned i=0;i<8;i++){
            TEB creator={.Peb=(void*)(uintptr_t)(0x10000+4096*i),.ClientId={.UniqueProcess=(void*)(uintptr_t)(40+i)}};
            teb=&creator;pthread_setspecific(ios_teb_tls_key,teb);
            jobs[i].owner=creator.Peb;jobs[i].pid=40+i;jobs[i].native=1;
            assert(!posix_memalign(&jobs[i].stack,4096,kernel_stack_size));
            assert(!spawn_thread(&jobs[i]));
            teb=NULL;pthread_setspecific(ios_teb_tls_key,NULL);
            assert(ios_system_thread_peb()==NULL && ios_current_pid()==32);
        }
        for(unsigned i=0;i<8;i++){
            while(!atomic_load(&jobs[i].ready))usleep(1000);
            pthread_join(jobs[i].thread,NULL);free(jobs[i].stack);
        }
    }
    struct thread_data bad={0};assert(!posix_memalign(&bad.stack,4096,kernel_stack_size));
    fail_create=1;assert(spawn_thread(&bad)==STATUS_NO_MEMORY);free(bad.stack);
    assert(nb_threads==0 && completed==128);
    puts("128 child/nested workers: owner before IPC, TEB precedence, sibling isolation, failure cleanup passed");
}
