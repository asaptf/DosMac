#!/usr/bin/env python3
"""Build a CRT-free PE32 guest agent with LLVM and LLD (brew install llvm lld)."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
brew = shutil.which('brew')
if not brew:
    raise SystemExit('Install the developer tools: Homebrew, then brew install llvm lld')
llvm = Path(subprocess.check_output([brew, '--prefix', 'llvm'], text=True).strip()) / 'bin'
lld = Path(subprocess.check_output([brew, '--prefix', 'lld'], text=True).strip()) / 'bin/lld-link'
if not lld.exists():
    raise SystemExit('Install the developer tools: brew install llvm lld')
source = root / 'GuestTools/Agent/agent.c'
output = root / 'Sources/DosMacApp/Resources/GuestTools/dmagent.exe'
imports = {
    'kernel32': [('CreateFileA',28),('ReadFile',20),('WriteFile',20),('CloseHandle',4),('Sleep',4),('ExitProcess',4),('CreateMutexA',12),('GetLastError',0),('GetModuleFileNameA',12)],
    'user32': [('GetSystemMetrics',4),('EnumDisplaySettingsA',12),('ChangeDisplaySettingsA',8),('PeekMessageA',20),('TranslateMessage',4),('DispatchMessageA',4),('MsgWaitForMultipleObjects',20),('FindWindowA',8),('GetWindowRect',8),('PostMessageA',16),('GetDC',4),('ReleaseDC',8)],
    'gdi32': [('GetDeviceCaps',8)],
    'advapi32': [('RegCreateKeyExA',36),('RegSetValueExA',24),('RegCloseKey',4)],
}
with tempfile.TemporaryDirectory(prefix='dosmac-agent-') as temp:
    work = Path(temp)
    libs = []
    for dll, functions in imports.items():
        definition = work / (dll + '.def')
        definition.write_text('LIBRARY ' + dll + '.dll\nEXPORTS\n' + '\n'.join(f'{name}@{size}' for name,size in functions) + '\n')
        lib = work / (dll + '.lib')
        subprocess.run([str(llvm/'llvm-dlltool'),'-m','i386','--kill-at','-d',str(definition),'-l',str(lib)], check=True)
        libs.append(str(lib))
    obj = work / 'agent.obj'
    subprocess.run([str(llvm/'clang'),'--target=i686-pc-windows-msvc','-Os','-march=i386','-mno-sse','-mno-sse2','-mno-mmx','-ffreestanding','-fno-builtin','-fno-stack-protector','-fno-ident','-c',str(source),'-o',str(obj)], check=True)
    subprocess.run([str(lld),'/machine:x86','/subsystem:windows,4.0','/entry:AgentMain@0','/nodefaultlib','/timestamp:0','/safeseh:no','/fixed','/out:'+str(output),str(obj)]+libs, check=True)
manifest = {'source':'GuestTools/Agent/agent.c','sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'target':'Win32 x86, subsystem 4.0, no CRT','sourceSHA256':hashlib.sha256(source.read_bytes() + source.with_name('win32.h').read_bytes()).hexdigest(),'compiler':subprocess.check_output([str(llvm/'clang'),'--version'],text=True).splitlines()[0]}
output.with_suffix('.json').write_text(json.dumps(manifest,indent=2)+'\n')
shutil.copy2(source.with_name('LICENSE'), output.with_name('Agent-LICENSE.txt'))
print('Built',output,manifest['sha256'])
