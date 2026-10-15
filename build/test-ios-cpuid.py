#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Regression harness: compile the actual CPUID selector and brand leaf bodies.
from pathlib import Path
import subprocess
import sys
repo=Path(__file__).resolve().parent.parent
fex=Path(sys.argv[1]).resolve()
out=repo/'.work/cpuid-regression'
out.mkdir(parents=True,exist_ok=True)
source='FEXCore/Source/Interface/Core/CPUID.cpp'
old=subprocess.check_output(['git','-C',str(fex),'show','3648ee97e8354bb2e6757da8bdb00c48439a561d:'+source],text=True)
new=(fex/source).read_text()
def function(s,signature):
 a=s.index(signature);b=s.index('\n}',a)+2;return s[a:b]
prefix='''#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <algorithm>
#include <sys/types.h>
static uint32_t HostCPU;
namespace FHU::Syscalls {void getcpu(uint32_t* cpu,void*) {*cpu=HostCPU;}}
namespace FEXCore::CPUID {struct FunctionResults {uint32_t eax,ebx,ecx,edx;};}
using FEXCore::CPUID::FunctionResults;
struct CPUIDEmu {
 struct CPUData {const char* ProductName;};
 std::vector<CPUData> PerCPUData;
 FunctionResults Function_8000_0002h(uint32_t,uint32_t) const;
 FunctionResults Function_8000_0003h(uint32_t,uint32_t) const;
 FunctionResults Function_8000_0004h(uint32_t,uint32_t) const;
};
'''
suffix='''
int main() {
 CPUIDEmu emu; const char brand[]="Synthetic ARM processor for CPUID regression test";
#ifdef FEX_IOS_HOST
 emu.PerCPUData.resize(1,{brand});
#else
 emu.PerCPUData.resize(64,{brand});
#endif
 for(HostCPU=0;HostCPU<64;HostCPU++) {
  auto index=GetCPUID_Syscall();
#ifndef FEX_IOS_HOST
  if(index!=HostCPU)return 2;
#endif
  FunctionResults values[]={emu.Function_8000_0002h(0,index),emu.Function_8000_0003h(0,index),emu.Function_8000_0004h(0,index)};
  if(memcmp(values,brand,48))return 3;
 }
 puts("64 host CPU indices: all brand leaves intact");
}
'''
for label,s,ios,success in [('before',old,True,False),('after',new,True,True),('native',new,False,True)]:
 body=function(s,'static uint32_t GetCPUID_Syscall()')+'\n'
 for n in [2,3,4]:body+=function(s,f'FEXCore::CPUID::FunctionResults CPUIDEmu::Function_8000_000{n}h(uint32_t Leaf, uint32_t CPU)')+'\n'
 cpp=out/f'test-{label}.cpp';cpp.write_text(prefix+body+suffix)
 cmd=['g++','-std=c++17','-fsanitize=address','-g',str(cpp),'-o',str(out/f'test-{label}')]
 if ios:cmd+=['-DFEX_IOS_HOST=1']
 subprocess.run(cmd,check=True)
 r=subprocess.run([str(out/f'test-{label}')],capture_output=True,text=True)
 (out/f'test-{label}.log').write_text(r.stdout+r.stderr)
 print(label,'exit',r.returncode,r.stdout.strip(), 'heap-buffer-overflow' if 'heap-buffer-overflow' in r.stderr else '')
 assert (r.returncode==0)==success
 if not success:assert 'heap-buffer-overflow' in r.stderr
print('Production selector and all three production brand leaves checked with AddressSanitizer.')
