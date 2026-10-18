#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile actual Windows callret init/geometry against a bounded mapping API.

The thread-state layout, OS mapping and logging are stubs; the constants,
GetInfoThread, failure handling, InitializeThread and DestroyThread are source.
"""
from pathlib import Path
import os,subprocess,sys
r=Path(__file__).resolve().parent.parent;tree=Path(sys.argv[1]).resolve()
out=r/'.work/callret-reservation-test';out.mkdir(parents=True,exist_ok=True);os.environ['TMPDIR']=str(out)
h=(tree/'FEXCore/include/FEXCore/Debug/InternalThreadState.h').read_text()
a=h.index('  static constexpr size_t CALLRET_STACK_SIZE');b=h.index('  // The low address of the call-ret stack allocation',a)
start=h.rfind('#ifdef FEX_IOS_HOST',0,a)
if start>=0 and h[start:a].strip()=='#ifdef FEX_IOS_HOST':a=start
geometry=h[a:b]
s=(tree/'Source/Windows/Common/CallRetStack.h').read_text();a=s.index('namespace FEX::Windows::CallRetStack {');b=s.index('void DestroyThread(',a);end=s.index('\n}',b)+2
actual=s[a:end]+'\n}\n'
prefix=r'''
#define FEX_IOS_HOST 1
#include <algorithm>
#include <atomic>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>
#include <sys/mman.h>
namespace FEXCore::Utils {constexpr size_t FEX_PAGE_SIZE=4096;}
namespace FEXCore::X86State {constexpr int REG_RSP=4;}
namespace FEXCore::Core {
struct CPUState {uint64_t rip,gregs[16],callret_sp,callret_sp_base,flags;};
struct CpuStateFrame {CPUState State;};
struct InternalThreadState {
GEOMETRY
void* CallRetStackBase{};CpuStateFrame* CurrentFrame{};
};}
namespace LogMan::Msg {template<class... T>void EFmt(const char*,T...) {}}
constexpr size_t M=1024*1024,CAP=768*M,GRANULE=65536;
static unsigned char* arena;static unsigned char used[CAP/GRANULE];
uintptr_t ios_fex_band_base,ios_fex_band_end;
struct MEM_ADDRESS_REQUIREMENTS {void* LowestStartingAddress;void* HighestEndingAddress;size_t Alignment;};
struct MEM_EXTENDED_PARAMETER {unsigned Type;void* Pointer;};
constexpr int MemExtendedParameterAddressRequirements=1;
constexpr int MEM_RESERVE=0x2000,MEM_COMMIT=0x1000,MEM_RELEASE=0x8000,MEM_TOP_DOWN=0x100000;
constexpr int PAGE_NOACCESS=1,PAGE_READWRITE=4;
struct Mapping {void* base;size_t size,rounded;bool committed;};
static std::vector<Mapping> mappings;static size_t releases,commits;
static void* VirtualAlloc2(void*,void*,size_t n,int flags,int protection,MEM_EXTENDED_PARAMETER* p,int count) {
 assert((flags&MEM_RESERVE)&&(flags&MEM_TOP_DOWN)&&protection==PAGE_NOACCESS&&count==1);
 auto* req=(MEM_ADDRESS_REQUIREMENTS*)p->Pointer;
 assert((uintptr_t)req->LowestStartingAddress==ios_fex_band_base&&(uintptr_t)req->HighestEndingAddress==ios_fex_band_end);
 size_t slots=(n+GRANULE-1)/GRANULE;
 for(size_t end=sizeof(used);end>=slots;--end) {
  size_t begin=end-slots,j=0;while(j<slots&&!used[begin+j])++j;
  if(j!=slots)continue;
  memset(used+begin,1,slots);void* result=arena+begin*GRANULE;
  mappings.push_back({result,n,slots*GRANULE,false});return result;
 }
 return nullptr;
}
static void* VirtualAlloc(void* p,size_t n,int flags,int protection) {
 assert(flags==MEM_COMMIT&&protection==PAGE_READWRITE);
 for(auto& m:mappings)if((char*)p==(char*)m.base+4096) {
  assert(n+8192==m.size);assert(!m.committed);m.committed=true;
  assert(!mprotect(p,n,PROT_READ|PROT_WRITE));++commits;return p;
 }
 assert(false);return nullptr;
}
static bool VirtualFree(void* p,size_t n,int flags) {
 assert(!n&&flags==MEM_RELEASE);
 for(size_t i=0;i<mappings.size();++i)if(mappings[i].base==p) {
  auto m=mappings[i];size_t begin=((unsigned char*)p-arena)/GRANULE;
  for(size_t j=0;j<m.rounded/GRANULE;++j){assert(used[begin+j]==1);used[begin+j]=0;}
  assert(!mprotect(p,m.rounded,PROT_NONE));assert(!madvise(p,m.rounded,MADV_DONTNEED));
  mappings.erase(mappings.begin()+i);++releases;return true;
 }
 assert(false);return false;
}
namespace FEXCore::Allocator {
enum class THPControl {Disable};
void VirtualName(const char*,const void*,size_t) {}
void VirtualTHPControl(const void*,size_t,THPControl) {}
size_t ZeroScrub(void* p,size_t n) {
 for(auto& m:mappings)if((char*)p==(char*)m.base+4096){assert(m.committed&&n+8192==m.size);return 0;}
 assert(false);return 0;
}
}
'''.replace('GEOMETRY',geometry)
suffix=r'''
int main(int argc,char** argv) {
 arena=(unsigned char*)mmap(nullptr,CAP,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);assert(arena!=MAP_FAILED);
 ios_fex_band_base=(uintptr_t)arena;ios_fex_band_end=ios_fex_band_base+CAP-1;
 // Hold the other arena users constant to compare reservation packing.
 memset(used,2,460*M/GRANULE);
 using TS=FEXCore::Core::InternalThreadState;using Frame=FEXCore::Core::CpuStateFrame;
 constexpr size_t Size=TS::CALLRET_STACK_SIZE;
 static_assert(TS::CALLRET_DEFAULT_OFFSET==Size/2&&TS::CALLRET_LIVE_OFFSET==Size/4&&TS::CALLRET_LIVE_SIZE==Size/2);
 static_assert(TS::CALLRET_DEFAULT_OFFSET-TS::CALLRET_LIVE_OFFSET>=65536*16);
 Frame frames[64]{};TS threads[64]{};size_t started=0;
 for(size_t i=0;i<64;++i){
  threads[i].CurrentFrame=&frames[i];
  bool ok=FEX::Windows::CallRetStack::InitializeThread(&threads[i]);
  if(!ok){assert(!threads[i].CallRetStackBase);break;}
  ++started;auto info=FEX::Windows::CallRetStack::GetInfoThread(&threads[i]);
  assert(info.DefaultLocation==(uintptr_t)threads[i].CallRetStackBase+TS::CALLRET_DEFAULT_OFFSET);
  assert(info.AllocationEnd-info.AllocationBase==Size+8192);
  assert(frames[i].State.callret_sp==info.DefaultLocation&&frames[i].State.callret_sp_base==(uintptr_t)threads[i].CallRetStackBase);
  auto* sp=(uint64_t*)frames[i].State.callret_sp;sp[-2]=0x12345678;sp[-1]=0x87654321;
 }
 if(argc>1){
  assert(!started);if(!strcmp(argv[1],"commit"))assert(releases==1&&mappings.empty());else assert(!releases);
  // Injection is one-shot; the following initialization must recover.
  assert(FEX::Windows::CallRetStack::InitializeThread(&threads[0]));FEX::Windows::CallRetStack::DestroyThread(&threads[0]);
  assert(mappings.empty());puts("PASS: actual init failure path releases mappings and next initialization succeeds");
 }else{
  assert((Size==4*M&&started==64)||(Size==8*M&&started==38));
  printf("Actual init: reservation=%zu MiB, %zu/64 stacks in a 768 MiB arena with 460 MiB fixed other users\n",Size/M,started);
  for(size_t i=0;i<started;++i)FEX::Windows::CallRetStack::DestroyThread(&threads[i]);
  assert(mappings.empty()&&releases==started);
 }
 munmap(arena,CAP);
}
'''
(out/'test.cpp').write_text(prefix+actual+suffix)
subprocess.run(['g++','-std=c++23','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',str(out/'test.cpp'),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True,timeout=60)
for name in ['reserve','commit']:
 env=os.environ.copy();env['MADEIRA_FEX_FAIL_CALLRET']=name+':1'
 subprocess.run([str(out/'test'),name],env=env,check=True,timeout=60)

# Compare the previous real reservation constants against exactly the same
# arena and mapping fixture. No game, phone or system address map is changed.
revision=subprocess.check_output(['git','-C',str(tree),'log','-1','--format=%H',
    '--grep=^iOS: bound return predictions in a compact per-thread reservation$']).decode().strip()
if not revision:raise RuntimeError('compact prediction patch is absent')
prior=subprocess.check_output(['git','-C',str(tree),'show',revision+'^:FEXCore/include/FEXCore/Debug/InternalThreadState.h']).decode()
a=prior.index('#ifdef FEX_IOS_HOST',prior.index('// The prediction cache'))
b=prior.index('  // The low address of the call-ret stack allocation',a)
(out/'baseline.cpp').write_text(prefix.replace(geometry,prior[a:b])+actual+suffix)
subprocess.run(['g++','-std=c++23','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',str(out/'baseline.cpp'),'-o',str(out/'baseline')],check=True)
subprocess.run([str(out/'baseline')],check=True,timeout=60)
