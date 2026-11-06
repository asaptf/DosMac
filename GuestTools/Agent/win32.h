/* Minimal original Win32 ABI declarations, targeting Windows 95/98 without a CRT. */
typedef unsigned char BYTE;
typedef unsigned short WORD;
typedef unsigned long DWORD;
typedef long LONG;
typedef int BOOL;
typedef void *HANDLE;
#define API __declspec(dllimport)
#define CALL __stdcall
API HANDLE CALL CreateFileA(const char *, DWORD, DWORD, void *, DWORD, DWORD, HANDLE);
API BOOL CALL ReadFile(HANDLE, void *, DWORD, DWORD *, void *);
API BOOL CALL WriteFile(HANDLE, const void *, DWORD, DWORD *, void *);
API BOOL CALL CloseHandle(HANDLE);
API void CALL Sleep(DWORD);
API void CALL ExitProcess(DWORD);
API HANDLE CALL CreateMutexA(void *, BOOL, const char *);
API DWORD CALL GetLastError(void);
API int CALL GetSystemMetrics(int);
typedef struct {
    BYTE device[32]; WORD spec, driver, size, extra; DWORD fields;
    BYTE printer[16]; short color, duplex, yResolution, ttOption, collate;
    BYTE form[32]; WORD logPixels;
    DWORD bits, width, height, flags, frequency;
    DWORD icmMethod, icmIntent, mediaType, ditherType, reserved1, reserved2;
} DisplayMode;
_Static_assert(sizeof(DisplayMode) == 148, "Win9x DEVMODEA ABI");
API BOOL CALL EnumDisplaySettingsA(const char *, DWORD, DisplayMode *);
API LONG CALL ChangeDisplaySettingsA(DisplayMode *, DWORD);
typedef struct { HANDLE window; DWORD message, wParam; LONG lParam; DWORD time; LONG x, y; } Message;
API BOOL CALL PeekMessageA(Message *, HANDLE, DWORD, DWORD, DWORD);
API BOOL CALL TranslateMessage(const Message *);
API LONG CALL DispatchMessageA(const Message *);
API DWORD CALL MsgWaitForMultipleObjects(DWORD, const HANDLE *, BOOL, DWORD, DWORD);
typedef struct { LONG left, top, right, bottom; } Rectangle;
API HANDLE CALL FindWindowA(const char *, const char *);
API BOOL CALL GetWindowRect(HANDLE, Rectangle *);
API BOOL CALL PostMessageA(HANDLE, DWORD, DWORD, LONG);
API HANDLE CALL GetDC(HANDLE);
API int CALL ReleaseDC(HANDLE, HANDLE);
API int CALL GetDeviceCaps(HANDLE, int);
API DWORD CALL GetModuleFileNameA(HANDLE, char *, DWORD);
API LONG CALL RegCreateKeyExA(HANDLE, const char *, DWORD, char *, DWORD, DWORD, void *, HANDLE *, DWORD *);
API LONG CALL RegSetValueExA(HANDLE, const char *, DWORD, DWORD, const BYTE *, DWORD);
API LONG CALL RegCloseKey(HANDLE);
