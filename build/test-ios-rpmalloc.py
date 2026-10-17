#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the actual allocator core with iOS geometry in a bounded arena.

Linux TLS/map callbacks replace Windows glue. The allocator algorithms, class
table, alignment, lists and failure paths are compiled from the supplied tree.
"""
from pathlib import Path
import json, subprocess, sys
tree=Path(sys.argv[1]).resolve()
out=Path(__file__).resolve().parent.parent/'.work/tests/ios-rpmalloc'
out.mkdir(parents=True,exist_ok=True)
src=(tree/'rpmalloc/rpmalloc.c').read_text()
# Select all iOS geometry definitions, then use native Linux OS/TLS plumbing.
mark='\n////////////\n'
pos=src.index(mark,src.index('#define SPAN_MASK'))
src=src[:pos]+'\n#undef FEX_IOS_HOST\n'+src[pos:]
(out/'allocator.c').write_text(src)
(out/'rpmalloc.h').write_bytes((tree/'rpmalloc/rpmalloc.h').read_bytes())
(out/'malloc.c').write_bytes((tree/'rpmalloc/malloc.c').read_bytes())
c=r'''
#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sys/mman.h>
#include <stdatomic.h>
#include <signal.h>
#include <execinfo.h>
static void aborted(int sig){void* a[30];int n=backtrace(a,30);backtrace_symbols_fd(a,n,2);_Exit(128+sig);}
static atomic_int reports;
static void* GetStdHandle(unsigned long x) { (void)x; return 0; }
static int WriteFile(void* h,const void* b,unsigned long n,unsigned long* w,void* o) {
 (void)h;(void)b;(void)o;*w=n;atomic_fetch_add(&reports,1);return 1;
}
#define FEX_IOS_HOST 1
#include "allocator.c"
#ifndef SMALL_SPAN_SIZE
#define SMALL_SPAN_SIZE SPAN_SIZE
#define MEDIUM_SPAN_SIZE SPAN_SIZE
#endif
volatile int FEX_AllocWatch_Armed;
void FEX_AllocWatch_Event(const void* p,unsigned int e){(void)p;(void)e;}
#define M ((size_t)1024*1024)
#define CAP (768*M)
#define ARENA_ALIGNMENT (16*M)
static unsigned char* arena;
static unsigned char slots[768*16]; /* 64 KiB granules */
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static size_t current, peak, small_maps, medium_maps, large_maps;
static int deny;
static void* map_mem(size_t size,size_t align,size_t* off,size_t* mapped) {
 pthread_mutex_lock(&lock);
 if(deny){pthread_mutex_unlock(&lock);return 0;}
 size_t count=(size+65535)/65536;
 if(align<65536)align=65536;
 for(size_t i=0;i+count<=sizeof(slots);++i) {
  if(((uintptr_t)(arena+i*65536))&(align-1))continue;
  size_t j=0;while(j<count&&!slots[i+j])++j;
  if(j!=count){i+=j;continue;}
  memset(slots+i,1,count);*off=0;*mapped=count*65536;
  /* A fresh OS mapping is zero-filled, including after address reuse. */
  assert(!madvise(arena+i*65536,*mapped,MADV_DONTNEED));
  current+=*mapped;if(current>peak)peak=current;
  if(align==SPAN_SIZE){if(size==SMALL_SPAN_SIZE)++small_maps;else if(size==MEDIUM_SPAN_SIZE)++medium_maps;else if(size==SPAN_SIZE)++large_maps;}
  pthread_mutex_unlock(&lock);return arena+i*65536;
 }
 pthread_mutex_unlock(&lock);return 0;
}
static void unmap_mem(void* p,size_t off,size_t size) {
 assert(!off);pthread_mutex_lock(&lock);
 size_t i=((unsigned char*)p-arena)/65536;
 assert(i+size/65536<=sizeof(slots));
 for(size_t j=0;j<size/65536;++j){assert(slots[i+j]);slots[i+j]=0;}
 current-=size;pthread_mutex_unlock(&lock);
}
static void commit_mem(void* p,size_t n){assert(p);(void)n;}
static void decommit_mem(void* p,size_t n){assert(p);if(n)assert(!madvise(p,n,MADV_DONTNEED));}
static pthread_barrier_t barrier;
#define CLASSES 37
static void* blocks[10][CLASSES];
static size_t sizes[CLASSES];
static void* worker(void* arg) {
 size_t k=(size_t)arg;rpmalloc_thread_initialize();
 for(int j=0;j<CLASSES;++j){blocks[k][j]=rpmalloc(sizes[j]);assert(blocks[k][j]);memset(blocks[k][j],(int)(k+j+1),sizes[j]);}
 pthread_barrier_wait(&barrier);pthread_barrier_wait(&barrier);
 /* Cross-thread frees exercise the real remote lists. */
 size_t other=(k+1)%10;
 for(int j=0;j<CLASSES;++j){unsigned char* p=blocks[other][j];for(size_t i=0;i<sizes[j];++i)assert(p[i]==other+j+1);rpfree(p);}
 pthread_barrier_wait(&barrier);rpmalloc_thread_finalize();return 0;
}
static void list_checks(void) {
 heap_t h={0};page_t a={0},b={0};h.id=1;
 a.heap=b.heap=&h;a.size_class=b.size_class=1;
 a.page_type=b.page_type=PAGE_SMALL;
 h.page_available[1]=&a;a.next=&b;b.prev=&a;
 page_available_to_full(&a);assert(h.page_available[1]==&b&&!b.prev);
 assert(!rpm_avail_check(&h,1,&b,1,"test"));
 a.prev=&b;page_full_to_available(&a);assert(!a.prev&&a.next==&b&&b.prev==&a);
 assert(!rpm_avail_check(&h,1,&a,1,"test"));
 page_available_to_free(&a);assert(h.page_available[1]==&b&&!b.prev);
 assert(!rpm_avail_check(&h,1,&b,1,"test"));
 /* Fixture covers links; its stack object has no backing page to recommit. */
 a.is_decommitted=0;
 heap_make_free_page_available(&h,1,&a);assert(!a.prev&&b.prev==&a);
 assert(!atomic_load(&reports));
 a.prev=&b;assert(rpm_avail_check(&h,1,&a,1,"injected")&32);a.prev=0;
 b.prev=0;assert(rpm_avail_check(&h,1,&a,1,"injected")&64);b.prev=&a;
 char long_tag[1024];memset(long_tag,'x',sizeof(long_tag)-1);long_tag[sizeof(long_tag)-1]=0;
 a.prev=&b;for(int i=0;i<32;++i)assert(rpm_avail_check(&h,1,&a,1,long_tag)&32);a.prev=0;
 atomic_store(&reports,0);
}
static void* failure_worker(void* arg) {
 (void)arg;rpmalloc_thread_initialize();assert(get_thread_heap()->id==0);
 assert(!rpmalloc(16));assert(!rpmalloc(8192));assert(!rpmalloc(9*M));
 rpmalloc_thread_finalize();return 0;
}
static void* free_huge_worker(void* p){rpfree(p);return 0;}
/* Capacity stress, not a replay of the title: 40 live heaps coexist with
 * 400 MiB reserved for other translator state in the same 768 MiB arena. */
static atomic_int pressure_failures;
static void* pressure_worker(void* unused) {
 (void)unused;void* p[CLASSES]={0};rpmalloc_thread_initialize();
 for(int j=0;j<CLASSES;++j) {
  p[j]=rpmalloc(sizes[j]);
  if(!p[j])atomic_fetch_add(&pressure_failures,1);
  else memset(p[j],0x73,sizes[j]);
 }
 pthread_barrier_wait(&barrier);pthread_barrier_wait(&barrier);
 for(int j=0;j<CLASSES;++j)if(p[j]) {
  for(size_t i=0;i<sizes[j];++i)assert(((unsigned char*)p[j])[i]==0x73);
  rpfree(p[j]);
 }
 rpmalloc_thread_finalize();return 0;
}
static void pressure_test(rpmalloc_interface_t* iface,rpmalloc_config_t* config) {
 assert(!current);size_t off=0,mapped=0;
 void* other=map_mem(400*M,65536,&off,&mapped);assert(other&&mapped==400*M);
 rpmalloc_initialize_config(iface,config);
 pthread_barrier_destroy(&barrier);pthread_barrier_init(&barrier,0,41);
 pthread_t workers[40];
 for(int i=0;i<40;++i)assert(!pthread_create(workers+i,0,pressure_worker,0));
 pthread_barrier_wait(&barrier);
 int failures=atomic_load(&pressure_failures);
 printf("40 live heaps + 400 MiB other state: mapped=%zu MiB refused=%d\n",current/M,failures);
#ifdef EXPECT_PRESSURE_FAILURE
 assert(failures>0);
#else
 assert(!failures);
#endif
 pthread_barrier_wait(&barrier);
 for(int i=0;i<40;++i)pthread_join(workers[i],0);
 rpmalloc_finalize();unmap_mem(other,off,mapped);assert(!current);
}
// REPLAY_FIXTURE
int main(void) {
 setbuf(stdout,0);signal(SIGABRT,aborted);
 void* raw=mmap(0,CAP+ARENA_ALIGNMENT,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);assert(raw!=MAP_FAILED);
 arena=(void*)(((uintptr_t)raw+ARENA_ALIGNMENT-1)&~(uintptr_t)(ARENA_ALIGNMENT-1));
 rpmalloc_interface_t iface={.memory_map=map_mem,.memory_unmap=unmap_mem,.memory_commit=commit_mem,.memory_decommit=decommit_mem};
 rpmalloc_config_t config={.page_size=65536,.unmap_on_finalize=1};
 rpmalloc_initialize_config(&iface,&config);list_checks();
 for(int i=0;i<32;++i)sizes[i]=(i+1)*16;
 sizes[32]=8192;sizes[33]=16384;sizes[34]=65536;sizes[35]=200*1024;sizes[36]=300*1024;
 pthread_barrier_init(&barrier,0,11);pthread_t threads[10];
 for(size_t i=0;i<10;++i)assert(!pthread_create(threads+i,0,worker,(void*)i));
 pthread_barrier_wait(&barrier);
 printf("10 live worker heaps x 37 classes: mapped=%zu MiB peak=%zu MiB cached-maps=%zu small-span=%zu KiB medium-span=%zu KiB\n",current/M,peak/M,small_maps+medium_maps+large_maps,(size_t)SMALL_SPAN_SIZE/1024,(size_t)MEDIUM_SPAN_SIZE/1024);
 assert(small_maps+medium_maps+large_maps>=30);
 size_t expected=(small_maps+medium_maps)*SMALL_SPAN_SIZE+large_maps*SPAN_SIZE;
 assert(current>=expected&&current<expected+2*M);
 pthread_barrier_wait(&barrier);pthread_barrier_wait(&barrier);
 for(int i=0;i<10;++i)pthread_join(threads[i],0);
 /* Every class boundary and realloc preserves data, including 8 MiB blocks. */
 for(size_t cls=1;cls<SIZE_CLASS_COUNT;++cls) {
  size_t n=global_size_class[cls].block_size;
  for(int delta=-1;delta<=1;++delta) {
   size_t len=n+delta;if(!len)continue;
   void* p=rpmalloc(len);assert(p&&rpmalloc_usable_size(p)>=len);memset(p,0x5a,len);
   void* q=rprealloc(p,len+257);assert(q);for(size_t i=0;i<len;++i)assert(((unsigned char*)q)[i]==0x5a);rpfree(q);
  }
 }
 for(size_t a=32;a<=65536;a*=2){void* p=rpaligned_alloc(a,12345);assert(p&&!((uintptr_t)p&(a-1)));memset(p,7,12345);rpfree(p);}
 /* Large requests still work when moved from cached classes to exact maps. */
 const size_t large_sizes[]={M-1,M,M+1,2*M-1,2*M,2*M+1,3*M,4*M,5*M,8*M,9*M,16*M};
 const size_t large_alignments[]={16,65536,131072};
 for(size_t i=0;i<sizeof(large_sizes)/sizeof(large_sizes[0]);++i) {
  for(size_t k=0;k<sizeof(large_alignments)/sizeof(large_alignments[0]);++k) {
   size_t a=large_alignments[k];
   size_t n=large_sizes[i];unsigned char* p=rpaligned_alloc(a,n);assert(p&&!((uintptr_t)p&(a-1)));
   assert(rpmalloc_usable_size(p)>=n);memset(p,0x3d,n);
   unsigned char* q=rpaligned_realloc(p,a,n+4096,0,0);assert(q);
   for(size_t j=0;j<n;++j)assert(q[j]==0x3d);rpfree(q);
  }
 }
 void* remote_huge=rpmalloc(8*M);assert(remote_huge);memset(remote_huge,0x67,8*M);
 pthread_t freer;assert(!pthread_create(&freer,0,free_huge_worker,remote_huge));pthread_join(freer,0);
 assert(!atomic_load(&reports));rpmalloc_finalize();assert(!current);
 /* Inject metadata OOM with no cached heaps available; no recursion or NULL commit. */
 deny=1;rpmalloc_initialize_config(&iface,&config);assert(!rpmalloc(16));assert(!rpmalloc(9*M));
 pthread_t t;assert(!pthread_create(&t,0,failure_worker,0));pthread_join(t,0);
 deny=0;void* recovered=rpmalloc(16);assert(recovered);rpfree(recovered);
 void* original=rpmalloc(128);assert(original);memset(original,0x6b,128);
 deny=1;assert(!rprealloc(original,9*M));for(int i=0;i<128;++i)assert(((unsigned char*)original)[i]==0x6b);rpfree(original);
 deny=1;assert(!rpmalloc(9*M));assert(!rpaligned_alloc(65536,9*M));deny=0;
 rpmalloc_finalize();assert(!current);
 pressure_test(&iface,&config);
 replay_fixture(&iface,&config);
 munmap(raw,CAP+ARENA_ALIGNMENT);
 puts("PASS: real allocator classes, alignment, lists, remote frees, metadata OOM/retry and huge OOM");
}
'''
fixture=json.loads((Path(__file__).parent/'tests/fixtures/host-arena-r10.json').read_text())
assert fixture['arena_bytes']==768*1024*1024
regions=',\n'.join('{'+str(a)+','+str(n)+'}' for a,n in fixture['regions'])
replay=r'''
static const size_t replay_regions[][2]={REGIONS};
static void replay_fixture(rpmalloc_interface_t* iface,rpmalloc_config_t* config) {
 assert(!current);memset(slots,0,sizeof(slots));
 for(size_t i=0;i<sizeof(replay_regions)/sizeof(replay_regions[0]);++i) {
  size_t a=replay_regions[i][0],n=replay_regions[i][1];
  assert(!(a%65536)&&!(n%65536));
  memset(slots+a/65536,2,n/65536);
  memset(arena+a,0xa5,16);memset(arena+a+n-16,0xa5,16);
 }
 size_t off=0,mapped=0;
 assert(!map_mem(4*M,16*M,&off,&mapped));
 rpmalloc_initialize_config(iface,config);
 void* p=rpmalloc(16);
#ifdef EXPECT_FRAGMENTED
 assert(!p);puts("REPRODUCED: r10 layout has hundreds of free MiB but rejects a 16-MiB-aligned span");
#else
 assert(p);memset(p,0x29,16);assert(rpmalloc_usable_size(p)>=16);
 void* medium=rpmalloc(8192);void* large=rpmalloc(300*1024);void* huge=rpaligned_alloc(65536,8*M);
 assert(medium&&large&&huge);memset(medium,0x31,8192);memset(large,0x42,300*1024);memset(huge,0x53,8*M);
 for(size_t i=0;i<8*M;++i)assert(((unsigned char*)huge)[i]==0x53);
 rpfree(huge);rpfree(large);rpfree(medium);rpfree(p);
 puts("PASS: actual allocator uses the r10 fragmented layout for small, medium, large and aligned 8-MiB allocations");
#endif
 rpmalloc_finalize();assert(!current);
 for(size_t i=0;i<sizeof(replay_regions)/sizeof(replay_regions[0]);++i) {
  size_t a=replay_regions[i][0],n=replay_regions[i][1];
  for(int j=0;j<16;++j){assert(arena[a+j]==0xa5);assert(arena[a+n-16+j]==0xa5);}
 }
 memset(slots,0,sizeof(slots));assert(!atomic_load(&reports));
}
'''.replace('REGIONS',regions)
c=c.replace('// REPLAY_FIXTURE',replay)
(out/'test.c').write_text(c)
flags=['-DEXPECT_FRAGMENTED=1'] if '--expect-fragmented' in sys.argv[2:] else []
if '--expect-pressure-failure' in sys.argv[2:]: flags.append('-DEXPECT_PRESSURE_FAILURE=1')
subprocess.run(['clang','-std=c11','-O1','-g','-DENABLE_OVERRIDE=0','-DENABLE_ASSERTS=1','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',*flags,str(out/'test.c'),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True,timeout=120)
