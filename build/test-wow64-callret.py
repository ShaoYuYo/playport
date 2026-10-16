#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Execute the real FEX emitter's three inline guards as AArch64 under Unicorn.

Run with a Python containing Unicorn; no iOS process or game is started.
"""
from pathlib import Path
import subprocess, sys, struct, os
from unicorn import Uc, UcError, UC_ARCH_ARM64, UC_MODE_ARM
from unicorn.arm64_const import UC_ARM64_REG_X0, UC_ARM64_REG_X16, UC_ARM64_REG_X17, UC_ARM64_REG_X25, UC_ARM64_REG_X28, UC_ARM64_REG_NZCV

repo=Path(__file__).resolve().parent.parent
tree=Path(sys.argv[1]).resolve()
headers=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else tree
relative='FEXCore/Source/Interface/Core/JIT/BranchOps.cpp'
fixed=(tree/relative).read_text()
fix=subprocess.check_output(['git','-C',str(tree),'log','-1','--format=%H','--grep=^JIT: guard iOS WoW64 call-return predictions before access$']).decode().strip()
if not fix:raise RuntimeError('guard patch is absent')
old=subprocess.check_output(['git','-C',str(tree),'show',fix+'^:'+relative]).decode()

def guards(source):
    result=[];pos=0
    token='ldr(REG_CALLRET_SP, STATE, offsetof(FEXCore::Core::CpuStateFrame, State.callret_sp));'
    while (pos:=source.find(token,pos))>=0:
        start=source.rfind('#ifdef ARCHITECTURE_arm64ec',0,pos)
        bound=source.index('(void)Bind(&l_callret_ok);',pos)
        end=source.index('#endif',bound)+len('#endif')
        result.append(source[start:end]);pos=end
    assert len(result)==3,len(result)
    return result

prefix=r'''
#include <CodeEmitter/Emitter.h>
#include <FEXCore/Core/CoreState.h>
#include <cstdio>
#include <cstdlib>
namespace FEXCore::Allocator {
void *aligned_alloc(size_t a,size_t n){return ::aligned_alloc(a,n);}
void aligned_free(void *p){::free(p);}
}
namespace fextl {[[noreturn]] void ReportAllocationFailure(size_t,size_t){::abort();}}
namespace LogMan::Throw {[[noreturn]] void MFmt(const char *s,const fmt::format_args& args){auto v=fmt::vformat(s,args);::fputs(v.c_str(),stderr);::abort();}}
namespace LogMan::Msg {void MFmtImpl(DebugLevels,const char *s,const fmt::format_args& args){auto v=fmt::vformat(s,args);::fputs(v.c_str(),stderr);}}
namespace FEXCore::Assert {void ForcedAssert(){::abort();}}
struct GuardEmitter : ARMEmitter::Emitter {
    using ARMEmitter::Emitter::Emitter;
    static constexpr auto STATE=ARMEmitter::XReg::x28;
#ifdef ARCHITECTURE_arm64ec
    static constexpr auto TMP1=ARMEmitter::XReg::x16;
    static constexpr auto REG_CALLRET_SP=ARMEmitter::XReg::x17;
#else
    static constexpr auto TMP1=ARMEmitter::XReg::x0;
    static constexpr auto REG_CALLRET_SP=ARMEmitter::XReg::x25;
#endif
    void Emit(unsigned site) {
      switch(site) {
'''
suffix=r'''
      }
    }
};
int main(int argc,char **argv) {
    if(argc!=3)return 1;
    unsigned char bytes[4096]{};GuardEmitter emitter(bytes,sizeof(bytes));
    emitter.Emit((unsigned)atoi(argv[1]));
    auto out=fopen(argv[2],"wb");if(!out)return 2;
    fwrite(bytes,1,emitter.GetCursorOffset(),out);fclose(out);
    printf("%zu %zu\n",offsetof(FEXCore::Core::CpuStateFrame,State.callret_sp),offsetof(FEXCore::Core::CpuStateFrame,State.callret_sp_base));
}
'''
out=repo/'.work/callret-guard-test';out.mkdir(parents=True,exist_ok=True)
os.environ['TMPDIR']=str(out)
includes=[headers/'CodeEmitter',headers/'FEXCore/include',headers/'FEXHeaderUtils',headers/'External/fmt/include']
code_at=0x100000;state_at=0x200000;base=0x4000000
cases=[0,base-16,base,base+(2<<20)-16,base+(2<<20),base+(4<<20),base+(6<<20)-16,base+(6<<20),base+(16<<20),0xfffffffffffffff0]
for label,source,ios,ec in [('before-wow64',old,True,False),('after-wow64',fixed,True,False),('after-ec',fixed,True,True),('native-wow64',fixed,False,False)]:
    src=out/(label+'.cpp')
    body='\n'.join('case '+str(i)+': {\n'+guard+'\n break;}\n' for i,guard in enumerate(guards(source)))
    src.write_text(prefix+body+suffix);exe=out/label
    command=['g++','-std=c++23','-O2','-DFMT_HEADER_ONLY=1','-DASSERTIONS_ENABLED=1',str(src),'-o',str(exe)]
    if ios:command.append('-DFEX_IOS_HOST=1')
    if ec:command.append('-DARCHITECTURE_arm64ec=1')
    command += ['-I'+str(p) for p in includes]
    subprocess.run(command,check=True)
    checks=0
    for site in range(3):
        binary=out/f'{label}-{site}.bin'
        offsets=subprocess.check_output([str(exe),str(site),str(binary)]).decode().split()
        sp_off,base_off=map(int,offsets);code=binary.read_bytes()
        for value in cases:
            uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM);uc.mem_map(code_at,4096);uc.mem_map(state_at,4096)
            uc.mem_write(state_at+sp_off,struct.pack('<Q',value));uc.mem_write(state_at+base_off,struct.pack('<Q',base))
            uc.mem_write(code_at,code or b'\x1f\x20\x03\xd5')
            reg=UC_ARM64_REG_X17 if ec else UC_ARM64_REG_X25
            uc.reg_write(reg,value);uc.reg_write(UC_ARM64_REG_X28,state_at)
            uc.reg_write(UC_ARM64_REG_X0,0x12345678);uc.reg_write(UC_ARM64_REG_X16,0x87654321)
            uc.reg_write(UC_ARM64_REG_NZCV,0xa0000000)
            if code:uc.emu_start(code_at,code_at+len(code),count=64)
            expected=base+(4<<20) if ios and label!='before-wow64' and not base+(2<<20)<=value<base+(6<<20) else value
            assert uc.reg_read(reg)==expected,(label,site,hex(value),hex(uc.reg_read(reg)),hex(expected))
            assert uc.reg_read(UC_ARM64_REG_NZCV)==0xa0000000,'guest flags clobbered'
            assert uc.reg_read(UC_ARM64_REG_X28)==state_at,'state pointer clobbered'
            if ec:assert uc.reg_read(UC_ARM64_REG_X0)==0x12345678
            else:assert uc.reg_read(UC_ARM64_REG_X16)==0x87654321
            checks+=1
        if label=='before-wow64': assert not code,'old WoW64 unexpectedly has inline guards'
    print(label+': '+str(checks)+' AArch64 guard boundary/flag/register cases passed')
print('Old WoW64 leaves the reported underflow pointer unchanged; all three new sites reset it before memory access.')
