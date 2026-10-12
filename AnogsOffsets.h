// ============================================================================
// STYX-iOS — anogs (Tencent TSS) lazy-slot addresses
//
// Target: CODM Garena 1.6.58, anogs.framework (anogs 7.7.58.42114)
// Binary: Payload/codm.app/Frameworks/anogs.framework/anogs
//
// anogs is built with classic lazy binding: LC_DYLD_INFO_ONLY and NO
// LC_DYLD_CHAINED_FIXUPS, with an explicit __stubs + __stub_helper pair. Every
// libc call it makes goes through one pointer in its own writable
// __la_symbol_ptr section, which dyld_stub_binder fills on first use.
//
//     __la_symbol_ptr   vmaddr 0x298270   size 0x900  (288 slots x 8 bytes)
//     __got             vmaddr 0x298000   size 0x270
//     __stubs           vmaddr 0x2414BC
//     __stub_helper     vmaddr 0x24223C
//
// The addresses below are vaddrs WITHIN the anogs image (its __TEXT is mapped
// at vaddr 0), derived by walking the LC_DYLD_INFO bind opcodes: the k-th
// DO_BIND corresponds to the k-th __la_symbol_ptr slot, starting at 0x298270.
//
// WHY THIS MATTERS: rewriting a slot changes what *anogs alone* calls. Unity,
// UIKit, libobjc and libc++ keep their real libc bindings, so the game does not
// crash. The Android mod's approach of hooking these same libc functions
// process-wide cannot be used here -- on iOS that would replace memcpy/strcmp/
// malloc for the entire game and crash it immediately.
//
// Regenerate with tools/anogs_map_imports.py if the anogs build changes.
// ============================================================================
#pragma once

// ---- image enumeration (how anogs would see our injected dylib) ----
#define ANOGS_SLOT_dyld_get_image_name       0x2984F8
#define ANOGS_SLOT_dyld_image_count          0x298508
#define ANOGS_SLOT_dyld_get_image_header     0x2984F0

// ---- dynamic module resolution ----
#define ANOGS_SLOT_dlopen                    0x2985B8
#define ANOGS_SLOT_dlsym                     0x2985C0

// ---- filesystem probes (jailbreak / injection path checks) ----
#define ANOGS_SLOT_stat                      0x2989D0
#define ANOGS_SLOT_access                    0x298510
#define ANOGS_SLOT_openat                    0x298848
#define ANOGS_SLOT_opendir                   0x298850
#define ANOGS_SLOT_readdir                   0x298920
#define ANOGS_SLOT_readlink                  0x298928
#define ANOGS_SLOT_fopen                     0x298608
#define ANOGS_SLOT_statfs                    0x2989D8

// ---- environment / device fingerprint ----
#define ANOGS_SLOT_getenv                    0x298670
#define ANOGS_SLOT_sysctl                    0x298AC0
#define ANOGS_SLOT_sysctlbyname              0x298AC8

// ---- memory-region scan (the iOS equivalent of reading /proc/self/maps) ----
#define ANOGS_SLOT_mach_vm_region_recurse    0x298708
#define ANOGS_SLOT_vm_region_recurse_64      0x298B20
#define ANOGS_SLOT_proc_regionfilename       0x298870

// ---- thread scan ----
#define ANOGS_SLOT_task_info                 0x298AD8
#define ANOGS_SLOT_task_get_special_port     0x298AD0
#define ANOGS_SLOT_pid_for_task              0x298858
#define ANOGS_SLOT_pthread_getname_np        0x2988A0

// Section bounds, used to sanity-check the image at runtime.
#define ANOGS_LA_SYMBOL_PTR_BASE             0x298270
#define ANOGS_LA_SYMBOL_PTR_SIZE             0x900
#define ANOGS_TEXT_VMADDR                    0x0
#define ANOGS_TEXT_VMSIZE                    0x298000