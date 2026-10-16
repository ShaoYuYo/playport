#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise production pool ownership and the full WoW64 init function on host.

Pass the patched FEX tree. OS mappings and thread termination are modeled;
the allocator/CAS and init control flow are the actual production code.
"""
from pathlib import Path
import os,subprocess,sys
r=Path(__file__).resolve().parent.parent;t=Path(sys.argv[1]).resolve()
out=r/'.work/ios-scratch-test';out.mkdir(parents=True,exist_ok=True);os.environ['TMPDIR']=str(out)
stubs={
'FEXCore/Utils/Allocator.h':'''#pragma once
#include <cstdlib>
#include <cassert>
namespace FEXCore::Allocator {using std::malloc;using std::free;struct FEXAllocOperators {}; enum class ProtectOptions {None};
inline void* VirtualAlloc(size_t n){return malloc(n);} inline void VirtualFree(void*p,size_t){free(p);}
inline void VirtualName(const char*,void*,size_t){} inline bool VirtualProtect(void*,size_t,ProtectOptions){return true;}}
namespace FEXCore::Utils {constexpr size_t FEX_PAGE_SIZE=4096;}
''',
'FEXCore/Utils/LogManager.h':'''#pragma once
#include <cassert>
#define LOGMAN_THROW_A_FMT(test,...) assert(test)
namespace LogMan::Msg {template<class...T>void EFmt(const char*,T...) {}}
''',
'FEXCore/Utils/MathUtils.h':'''#pragma once
#include <cstdint>
inline uintptr_t AlignDown(uintptr_t n,size_t a){return n&~(a-1);}
''',
'FEXCore/Utils/TypeDefines.h':'#pragma once\n',
'FEXCore/fextl/list.h':'#pragma once\n#include <list>\nnamespace fextl {template<class T> using list=std::list<T>;}\n',
}
for name,s in stubs.items():p=out/'include'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
code=r'''
#include <FEXCore/Utils/ThreadPoolAllocator.h>
#include <memory>
#include <vector>
#include <thread>
#include <barrier>
using namespace FEXCore::Utils;
class Pool:public IntrusivePooledAllocator {
public:unsigned maps=0,live=0;~Pool(){FreeAllBuffers();assert(live==0);}
private:void* Alloc(size_t n)override{++maps;++live;return malloc(n);}
void Free(void*p,size_t)override{--live;free(p);}
};
using Client=PoolBufferWithTimedRetirement<unsigned char*,5000,500>;
int main(){
 {Pool p;std::vector<std::unique_ptr<Client>> clients;
  // Keep clients alive, and hot enough to retain their disowned buffer.
  for(int i=0;i<24;i++){
   clients.emplace_back(std::make_unique<Client>(p,16*1024*1024));
   auto& c=*clients.back();auto* bytes=c.ReownOrClaimBuffer();bytes[0]=7;c.DelayedDisownBuffer();
   bytes=c.ReownOrClaimBuffer();bytes[0]=8;c.DelayedDisownBuffer();
  }
#ifdef FEX_IOS_HOST
  assert(p.maps==1);
#else
  assert(p.maps==24);
#endif
  for(auto& c:clients){auto*b=c->ReownOrClaimBuffer();b[0]=9;c->DelayedDisownBuffer();}
 }
 {Pool p;std::barrier barrier(8);unsigned char* pointers[8]={};std::vector<std::thread> threads;
  for(int n=0;n<8;n++)threads.emplace_back([&,n]{Client c(p,4096);
   for(int i=0;i<500;i++){
    auto* b=c.ReownOrClaimBuffer();pointers[n]=b;b[0]=n;b[4095]=n;
    barrier.arrive_and_wait();
    for(int j=0;j<8;j++)if(j!=n)assert(pointers[j]!=b);
    assert(b[0]==n && b[4095]==n);barrier.arrive_and_wait();c.DelayedDisownBuffer();
    barrier.arrive_and_wait();
   }
  });
  for(auto&th:threads)th.join();assert(p.maps==8);
 }
#ifdef FEX_IOS_HOST
 puts("iOS production pool: 24 hot disowned 16 MiB scratch clients share one mapping; 8 concurrent owners x 500 reclaims remain distinct");
#else
 puts("Non-iOS production pool: original five-second retention keeps 24 mappings; concurrent ownership passed");
#endif
}
'''
p=out/'pool.cpp';p.write_text(code)
for ios in (False,True):
 exe=out/('pool-ios-test' if ios else 'pool-native-test')
 cmd=['clang++','-std=c++20','-O1','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fsanitize=address,undefined','-pthread','-I'+str(out/'include'),'-I'+str(t/'FEXCore/include')]
 if ios:cmd+=['-DFEX_IOS_HOST=1']
 subprocess.run(cmd+[str(p),'-o',str(exe)],check=True);subprocess.run([str(exe)],check=True,timeout=60)
source=(t/'Source/Windows/WOW64/Module.cpp').read_text();a=source.index('void BTCpuThreadInit() {');b=source.index('\nvoid BTCpuThreadTerm(',a)
fn=source[a:b]
prefix=r'''
#include <cassert>
#include <map>
#include <mutex>
#include <cstdint>
#include <cstdio>
#define FEX_IOS_HOST 1
using HANDLE=void*;
constexpr int STATUS_NO_MEMORY=0xc0000017;
static int mode,crt,states,segments,frontends;
namespace LogMan::Msg {template<class...T>void EFmt(const char*,T...) {}}
namespace FEXCore::Core {
struct CPUState {struct gdt_segment {int L,D;static void*operator new[](size_t n){++segments;return ::operator new[](n);}static void operator delete[](void*p){--segments;::operator delete[](p);}};
 gdt_segment*segment_arrays[2]={};int cs_idx=0,cs_cached=0;
 enum{SEGMENT_ARRAY_INDEX_GDT,SEGMENT_ARRAY_INDEX_LDT};
 static void SetGDTBase(gdt_segment*,int){}static void SetGDTLimit(gdt_segment*,int){}static int CalculateGDTBase(gdt_segment&){return 0;}};
struct Frame {CPUState State;};
struct InternalThreadState {Frame*CurrentFrame=new Frame;void*FrontendPtr=nullptr;void*ThreadStats=nullptr;~InternalThreadState(){delete CurrentFrame;}};
}
using Thread=FEXCore::Core::InternalThreadState;
static Thread*published;
namespace FEX::Windows {void InitCRTThread(){++crt;}void DeinitCRTThread(){--crt;}
namespace CallRetStack{bool InitializeThread(Thread*){return mode!=2;}}}
struct Context {Thread*CreateThread(){if(mode==1)return nullptr;++states;return new Thread;}void DestroyThread(Thread*t){--states;delete t;}} context;
static Context*CTX=&context;
static std::mutex ThreadCreationMutex;
struct TLS {Thread*&ThreadState()const{return published;}};
TLS GetTLS(){return {};}
struct FrontendThreadData {FrontendThreadData(TLS){++frontends;}~FrontendThreadData(){--frontends;}};
static std::map<int,Thread*>Threads;
struct Stats {void*AllocateSlot(int){return nullptr;}};
static Stats*StatAllocHandler=nullptr;
int GetCurrentThreadId(){return 0x4c;}HANDLE NtCurrentProcess(){return (HANDLE)-1;}
struct Terminated{};
void NtTerminateProcess(HANDLE h,int status){
 assert(h==NtCurrentProcess() && status==STATUS_NO_MEMORY);
 assert(!crt && !states && !segments && !published && Threads.empty());
 assert(ThreadCreationMutex.try_lock());ThreadCreationMutex.unlock();throw Terminated{};
}
'''
suffix=r'''
int main(){
 for(mode=1;mode<=2;mode++){bool ended=false;try{BTCpuThreadInit();}catch(Terminated&){ended=true;}assert(ended);}
 mode=0;BTCpuThreadInit();assert(published && crt==1 && states==1 && segments==1 && frontends==1 && Threads.size()==1);
 assert(ThreadCreationMutex.try_lock());ThreadCreationMutex.unlock();
 delete static_cast<FrontendThreadData*>(published->FrontendPtr);
 delete[] published->CurrentFrame->State.segment_arrays[0];CTX->DestroyThread(published);published=nullptr;FEX::Windows::DeinitCRTThread();Threads.clear();
 assert(!crt && !states && !segments && !frontends);
 puts("Production WoW64 init: thread-state and prediction-stack failures unwind before guest termination; successful initialization publishes only complete state");
}
'''
p=out/'init.cpp';p.write_text(prefix+fn+suffix);exe=out/'init'
subprocess.run(['clang++','-std=c++20','-O1','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',str(p),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
