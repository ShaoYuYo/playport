#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile the actual patched limit function against deterministic mmap/task_info stubs."""
import pathlib, subprocess, sys, tempfile
p=pathlib.Path(sys.argv[1]);s=p.read_text();start=s.index('static void *get_host_addr_space_limit(void)');begin=s.index('{',start)
depth=1;end=begin+1
while depth:
    depth += (s[end]=='{')-(s[end]=='}');end+=1
function=s[start:end]
preamble=r'''
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#define WINE_IOS 1
#define __APPLE__ 1
#define MAP_PRIVATE 1
#define MAP_ANON 2
#define MAP_FAILED ((void*)-1)
#define PROT_NONE 0
#define TASK_VM_INFO_COUNT 1
#define TASK_VM_INFO 1
#define KERN_SUCCESS 0
typedef uintptr_t UINT_PTR;
typedef int mach_msg_type_number_t;
typedef void* task_info_t;
typedef struct { uintptr_t max_address; } task_vm_info_data_t;
static uintptr_t boundary, kernel;
static int query_ok;
static const uintptr_t host_page_size=16384;
static void* mmap(void* a, uintptr_t size, int prot, unsigned flags, int fd, int off) {
 (void)size;(void)prot;(void)flags;(void)fd;(void)off;errno=0;
 return (uintptr_t)a < boundary ? a : MAP_FAILED;
}
static void ios_pool_va_warn(const char* s,void* a,uintptr_t n){(void)s;(void)a;(void)n;}
static void munmap(void* a,uintptr_t n){(void)a;(void)n;}
static int mach_task_self(void){return 0;}
static int task_info(int a,int b,void* v,void* c){(void)a;(void)b;(void)c;((task_vm_info_data_t*)v)->max_address=kernel;return query_ok?0:1;}
'''
checks=r'''
int main(void){
 query_ok=1;boundary=0x8000000000ULL;kernel=0x7180000000ULL;
 assert((uintptr_t)get_host_addr_space_limit()==kernel); /* reported device: lower */
 boundary=0x800000000ULL;kernel=0xfc0000000ULL;
 assert((uintptr_t)get_host_addr_space_limit()==kernel); /* hint underestimates */
 boundary=0x8000000000ULL;kernel=0;
 assert((uintptr_t)get_host_addr_space_limit()==boundary);
 kernel=0x1000;assert((uintptr_t)get_host_addr_space_limit()==boundary);
 query_ok=0;kernel=0x7180000000ULL;
 assert((uintptr_t)get_host_addr_space_limit()==boundary);
 puts("VA ceiling: five production-function cases passed.");
}
'''
with tempfile.TemporaryDirectory() as temp:
    source=pathlib.Path(temp)/'check.c';exe=pathlib.Path(temp)/'check';source.write_text(preamble+function+checks)
    subprocess.run(['cc','-std=c11','-D_DEFAULT_SOURCE',str(source),'-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True)
