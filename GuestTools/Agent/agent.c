/* DosMac display agent. Original code, MIT licensed; see LICENSE.
 * Only accepts bounded display requests. No command execution or clipboard access.
 * Transport uses the managed H: live share; this process never opens a host path.
 */
#include "win32.h"
void *memcpy(void *dest, const void *src, unsigned n) {
    BYTE *d=dest; const BYTE *s=src; unsigned i; for(i=0;i<n;i++) d[i]=s[i]; return dest;
}
#define BAD_HANDLE ((HANDLE)-1)
#define REQUEST "H:\\DMTOOLS\\REQUEST.TXT"
#define STATUS "H:\\DMTOOLS\\STATUS.TXT"
static char input[160], output[8192], token[33];
static unsigned used, lastID;
static int hasID, helloPublished;
static void zero(void *p, unsigned n) { BYTE *b = p; while (n--) *b++ = 0; }
static void text(const char *p) { while (*p && used < sizeof(output)-1) output[used++] = *p++; }
static void number(unsigned n) { char b[12]; unsigned k=0; do { b[k++]=(char)('0'+n%10); n/=10; } while(n); while(k) { char c[2]={b[--k],0}; text(c); } }
static void dimensions(void) { number(GetSystemMetrics(0)); text(" "); number(GetSystemMetrics(1)); }
static BOOL publishAt(const char *path) {
    DWORD written=0; HANDLE f=CreateFileA(path,0x40000000,3,0,2,0x80,0);
    if(f==BAD_HANDLE) return 0;
    BOOL ok=WriteFile(f,output,used,&written,0); CloseHandle(f); return ok && written==used;
}
static BOOL publish(void) { return publishAt(STATUS); }
static BOOL modeAt(unsigned i, DisplayMode *m) { zero(m,sizeof(*m)); m->size=sizeof(*m); return EnumDisplaySettingsA(0,i,m); }
static int valid(DisplayMode *m) { return m->width>=640 && m->height>=480 && m->width<=1600 && m->height<=1200 && (m->bits==8 || m->bits==16 || m->bits==24 || m->bits==32); }
static BOOL ready(void) {
    DisplayMode m; unsigned i, count=0;
    used=0; text("DMAC1 READY "); text(token); text(" "); dimensions(); text("\n");
    for(i=0;i<512 && modeAt(i,&m);i++) if(valid(&m) && count++<128) {
        text("MODE "); number(m.width); text(" "); number(m.height); text("\n");
    }
    text("END\n"); return publish();
}
static int equal(const char *a,const char *b) { while(*a && *a==*b) {a++;b++;} return *a==*b; }
static int word(char **p, const char *wanted) { while(*wanted) if(*(*p)++ != *wanted++) return 0; return 1; }
static int uint(char **p,unsigned *n) {
    unsigned v=0, count=0; while(**p>='0' && **p<='9') {
        unsigned digit=(unsigned)(*(*p)++-'0'); if(v>429496729 || (v==429496729 && digit>5)) return 0;
        v=v*10+digit; if(++count>10) return 0;
    } *n=v; return count!=0;
}
static int readToken(char **p,char *out) {
    unsigned i; for(i=0;i<32;i++) { char c=*(*p)++; if(!((c>='0'&&c<='9')||(c>='a'&&c<='f'))) return 0; out[i]=c; }
    out[32]=0; return 1;
}
static void pump(DWORD wait) {
    Message message;
    while(PeekMessageA(&message,0,0,0,1)) {
        if(message.message==0x12) ExitProcess(0);
        TranslateMessage(&message); DispatchMessageA(&message);
    }
    MsgWaitForMultipleObjects(0,0,0,wait,0x00FF);
}
static BOOL shellFits(unsigned w,unsigned h) {
    Rectangle r; HANDLE tray=FindWindowA("Shell_TrayWnd",0);
    if(!tray || !GetWindowRect(tray,&r)) return 0;
    /* Win9x returns the taskbar's outer rectangle, including its off-screen
     * two-pixel borders. Compare its span with a small non-client tolerance. */
    LONG rw=r.right-r.left, rh=r.bottom-r.top;
    return (rw>=(LONG)w-8 && rw<=(LONG)w+8) || (rh>=(LONG)h-8 && rh<=(LONG)h+8);
}
static void notifyDisplay(DisplayMode *m) {
    /* Legacy shells can retain an old work area even after a driver mode set.
     * Post the documented notification and keep processing our Win32 queue. */
    PostMessageA((HANDLE)0xFFFF,0x7E,m->bits,(LONG)((m->height<<16)|m->width));
}
static void resize(unsigned id,unsigned width,unsigned height) {
    DisplayMode m,best,current; unsigned i; int score=0; LONG result=-2;
    BOOL hasCurrent=0;
    unsigned currentW=GetSystemMetrics(0), currentH=GetSystemMetrics(1), currentBits=8;
    HANDLE dc=GetDC(0);
    if(dc) { currentBits=GetDeviceCaps(dc,12)*GetDeviceCaps(dc,14); ReleaseDC(0,dc); }
    for(i=0;i<512 && modeAt(i,&m);i++) {
        if(m.width==currentW && m.height==currentH && m.bits==currentBits) { current=m; hasCurrent=1; break; }
    }
    for(i=0;i<512 && modeAt(i,&m);i++) if(valid(&m) && m.width==width && m.height==height) {
        int rank=m.bits==currentBits?5:m.bits==16?4:m.bits==32?3:m.bits==24?2:1;
        if(rank>score) { best=m; score=rank; }
    }
    if(score && hasCurrent) {
        best.fields=0x1C0000; best.extra=0; /* bits, width, height only; no refresh rate. */
        result=ChangeDisplaySettingsA(&best,2); /* CDS_TEST, before any change. */
        if(result==0) result=ChangeDisplaySettingsA(&best,1); /* CDS_UPDATEREGISTRY: update the full Win9x desktop. */
        if(result==0) {
            notifyDisplay(&best);
            for(i=0;i<40 && !shellFits(width,height);i++) pump(100);
            if(!shellFits(width,height)) {
                /* Never acknowledge a framebuffer whose desktop still has the old bounds. */
                current.fields=0x1C0000; current.extra=0;
                ChangeDisplaySettingsA(&current,1); notifyDisplay(&current);
                result=-1;
            }
        }
    }
    {
        Rectangle r; HANDLE tray=FindWindowA("Shell_TrayWnd",0);
        used=0; text("Result "); if(result<0) { text("-"); number((unsigned)-result); } else number(result);
        text(" Depth "); number(currentBits); text(" Current "); number(hasCurrent); text(" Screen "); dimensions(); text(" Tray ");
        if(tray && GetWindowRect(tray,&r)) { number(r.left); text(" "); number(r.top); text(" "); number(r.right); text(" "); number(r.bottom); }
        else text("missing");
        text("\n"); publishAt("H:\\DMTOOLS\\DISPLAY.LOG");
    }
    used=0; text("DMAC1 RESULT "); text(token); text(" "); number(id); text(result==0?" OK ":" FAILED "); dimensions(); text("\nEND\n");
    if(publish()) { lastID=id; hasID=1; }
}
static void poll(void) {
    DWORD n=0; char incoming[33]; char *p=input; unsigned id,w,h;
    HANDLE f=CreateFileA(REQUEST,0x80000000,3,0,3,0x80,0);
    if(f==BAD_HANDLE) return;
    BOOL ok=ReadFile(f,input,sizeof(input)-1,&n,0); CloseHandle(f);
    if(!ok || n==0 || n>=sizeof(input)-1) return; input[n]=0;
    if(word(&p,"DMAC1 HELLO ")) {
        if(!readToken(&p,incoming) || !equal(p,"\n")) return;
        if(!equal(token,incoming)) { unsigned i; for(i=0;i<33;i++) token[i]=incoming[i]; hasID=0; helloPublished=0; }
        if(!helloPublished) helloPublished=ready();
        return;
    }
    p=input;
    if(!word(&p,"DMAC1 RESIZE ") || !readToken(&p,incoming) || !equal(token,incoming) || *p++!=' ') return;
    if(!uint(&p,&id) || *p++!=' ' || !uint(&p,&w) || *p++!=' ' || !uint(&p,&h) || !equal(p,"\n")) return;
    if(w<640 || h<480 || w>1600 || h>1200 || (hasID && id==lastID)) return;
    resize(id,w,h);
}
void CALL AgentMain(void) {
    HANDLE singleton=CreateMutexA(0,0,"DosMacDisplayAgentV1");
    if(!singleton || GetLastError()==183) ExitProcess(0);
    for(;;) { pump(500); poll(); }
}
