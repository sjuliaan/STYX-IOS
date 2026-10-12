// ============================================================================
// STYX-iOS — anogs (Tencent TSS) scoped interposer
//
// Neutralises the anti-cheat's libc calls *for anogs only* by rewriting the
// pointers in its own __la_symbol_ptr table. The rest of the process keeps its
// real libc bindings, so nothing else in the game is affected.
//
// Deliberately NOT hooked:
//   memcpy / memset / memmove / malloc / free / realloc / mmap / munmap /
//   strcmp / strstr / unlink / remove
// The Android mod hooks those process-wide, which is fine on Android but fatal
// on iOS -- those symbols are shared with Unity, UIKit and libc++, and replacing
// them breaks the game immediately. They are also near-worthless here: anogs
// compares its decrypted strings through its own internal routine (sub_18288),
// not libSystem strcmp, and mprotect/mmap are used by its hook engine rather
// than for integrity checks we need to stop.
//
// Network (connect/send/recv) is passed through untouched. Blocking it risks a
// timeout kick, which is worse than a report; that is a later decision if we
// actually observe one.
// ============================================================================
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <dirent.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <pthread.h>
#import <errno.h>
#import <stdint.h>
#import <string.h>
#import <stdio.h>

#import "StyxConfig.h"
#import "StyxAnogs.h"
#import "AnogsOffsets.h"

// The iOS SDK hides the task_info types behind __DARWIN_C_LEVEL guards, and
// <mach/task_info.h> cannot be included reliably from ObjC++. task_info is no
// longer interposed (see the removal note below), so no hand-written typedefs
// are needed here -- that was the second source of ABI corruption during
// bring-up, and dropping the interposer removed the whole class of bug.

StyxAnogsStats StyxAnogs;

// ---------------------------------------------------------------------------
// Image lookup
// ---------------------------------------------------------------------------
static uintptr_t StyxFindAnogsImage(void) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (!nm) continue;
        if (strstr(nm, "anogs.framework/anogs")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Pointer-table writer
//
// The slot is writable __DATA. We still vm_protect it defensively: if the
// section is mapped read-only for any reason, vm_protect succeeds where a plain
// store would fault.
// ---------------------------------------------------------------------------
static BOOL StyxWriteSlot(uintptr_t base, uintptr_t slotOff, void *value) {
    uintptr_t addr = base + slotOff;
    vm_protect(mach_task_self(), (vm_address_t)(addr & ~0xFFFULL), 0x1000,
               FALSE, VM_PROT_READ | VM_PROT_WRITE);
    *(volatile uint64_t *)addr = (uint64_t)(uintptr_t)value;
    return YES;
}

// ---------------------------------------------------------------------------
// Originals (resolved from libSystem, independent of anogs' table)
// ---------------------------------------------------------------------------
typedef const char *(*Fn_dyld_get_image_name)(uint32_t);

static Fn_dyld_get_image_name s_orig_getImageName = NULL;

static int  (*s_orig_sysctl)(int *, unsigned int, void *, size_t *, void *, size_t) = NULL;

static void StyxResolveOriginals(void) {
    if (s_orig_getImageName) return;   // once
    s_orig_getImageName = (Fn_dyld_get_image_name)dlsym(RTLD_DEFAULT, "_dyld_get_image_name");
    s_orig_sysctl      = (int (*)(int *, unsigned int, void *, size_t *, void *, size_t))
                          dlsym(RTLD_DEFAULT, "sysctl");
}

// ---------------------------------------------------------------------------
// What we hide
//
// STYX_INTERPOSE_MIN/MAX bound every pointer we receive from anogs before we
// dereference it. anogs calls these libc functions with arguments that are
// sometimes not pointers at all (its own dlsym() call at sub_240E28 passes
// -2 as a handle; other paths pass small integers). Without this gate a single
// integer reaching strstr faults the whole process -- which is exactly what
// happened twice during bring-up.
//
// arm64 user space lives well inside [0x10000000, 0x00007FFF00000000]; the
// bounds below accept that range and reject low integers and non-canonical
// values.
// ---------------------------------------------------------------------------
#define STYX_INTERPOSE_MIN   0x0000000100000000ULL
#define STYX_INTERPOSE_MAX   0x00007FFF00000000ULL

static inline BOOL StyxPlausiblePtr(const void *p) {
    uintptr_t v = (uintptr_t)p;
    return v >= STYX_INTERPOSE_MIN && v <= STYX_INTERPOSE_MAX;
}

static BOOL StyxPathIsSensitive(const char *path) {
    if (!StyxPlausiblePtr(path)) return NO;
    static const char *needles[] = {
        "/Library/MobileSubstrate",
        "/usr/lib/TweakInject",
        "/var/jb/", "/var/stash", "/private/var/jb",
        "libjailbreak.dylib", "roothidepatch.dylib",
        "/bin/linker",
        // our own injected payload
        "Cloud.framework/Cloud",
        NULL
    };
    for (int i = 0; needles[i]; i++)
        if (strstr(path, needles[i])) return YES;
    return NO;
}

static BOOL StyxImageIsSensitive(const char *name) {
    if (!StyxPlausiblePtr(name)) return NO;
    static const char *needles[] = {
        "Cloud.framework/Cloud",
        "MobileSubstrate", "TweakInject", "SubstrateLoader",
        "libjailbreak", "roothidepatch", "frida",
        NULL
    };
    for (int i = 0; needles[i]; i++)
        if (strstr(name, needles[i])) return YES;
    return NO;
}

// ---------------------------------------------------------------------------
// Interposers
// ---------------------------------------------------------------------------
// Image enumeration: hide matching names.
//
// We return "" rather than NULL. Returning NULL crashes anogs: sub_D0308 in the
// boot path does `v8 = [array objectAtIndex:0]` and only checks `!= nullptr`
// before messaging it -- a NULL name propagates into a string that is then sent
// cStringUsingEncoding:. An empty string cannot match any needle and cannot
// fault.
static const char *Styx_dyld_get_image_name(uint32_t index) {
    if (!s_orig_getImageName) return "";
    const char *n = s_orig_getImageName(index);
    if (!n) return "";
    if (StyxCfg.anogsBypassOn && StyxImageIsSensitive(n)) {
        StyxAnogs.hidImages++;
        return "";
    }
    return n;
}

// REMOVED INTERPOSERS (deliberately):
//   stat, access, opendir, statfs, getenv  -- file-path hiding. On a
//       non-jailbroken device these paths are already absent, so the checks
//       return false on their own. They only added crash surface, and they do
//       not touch game memory, so they bought no real stealth.
//   openat                                 -- variadic; cannot be forwarded
//       portably and forcing mode=0 on O_CREAT creates unusable files.
//   dlopen, dlsym, task_info                -- anogs passes non-pointer values
//       through these (its dlsym call at sub_240E28 uses -2 as a handle).
//
// Two interposers remain. Both are read-only, both leave game memory untouched,
// and both reduce our footprint rather than fighting the SDK.
//
//   1) _dyld_get_image_name -- hides our dylib from image enumeration
//   2) sysctl (KERN_PROC)   -- clears the debugger flag

// sysctl carries the debugger flag (KERN_PROC / KERN_PROC_PID, whose
// kinfo_proc.kp_proc.p_flag contains P_TRACED) and device identity.
//
// CRITICAL: sysctl takes SIX parameters, the first two being an MIB:
//
//   int sysctl(int *name, u_int namelen,
//              void *oldp, size_t *oldlenp,
//              void *newp, size_t newlen);
//
// An earlier revision declared it with five (dropping namelen). That shifted
// every register: the real sysctl then believed the destination buffer was on
// the caller's stack and wrote the result length in bytes straight over
// anogs' saved registers. That stack corruption is what produced the first
// crash -- objc_msgSend on 0xFFFFFFFFFFFFFFFF several seconds later.
//
// We only touch the KERN_PROC debugger probe. Device identity stays genuine:
// faking hw.machine would clash with what the server observes.
static int Styx_sysctl(int *name, unsigned int namelen,
                       void *oldp, size_t *oldlenp,
                       void *newp, size_t newlen) {
    if (StyxCfg.anogsBypassOn && StyxPlausiblePtr(name) && namelen >= 2 &&
        name[0] == 1 /*CTL_KERN*/ && name[1] == 12 /*KERN_PROC*/) {
        // A zeroed kinfo_proc means p_flag == 0, i.e. "not traced", which is
        // the truth on this device.
        if (StyxPlausiblePtr(oldp) && StyxPlausiblePtr(oldlenp) &&
            *oldlenp >= 136 /*sizeof(struct kinfo_proc)*/) {
            memset(oldp, 0, *oldlenp);
            StyxAnogs.neuteredSysctl++;
            return 0;
        }
        if (!oldp && StyxPlausiblePtr(oldlenp)) {
            *oldlenp = 136;          // sizing query
            StyxAnogs.neuteredSysctl++;
            return 0;
        }
    }
    return s_orig_sysctl ? s_orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen) : -1;
}

// ---------------------------------------------------------------------------
// Install
// ---------------------------------------------------------------------------
static void StyxPatchSlot(uintptr_t base, uintptr_t off, void *fn) {
    StyxAnogs.hooksWanted++;
    StyxWriteSlot(base, off, fn);
    StyxAnogs.hooksApplied++;
}

void StyxAnogsInstall(void) {
    if (StyxAnogs.installed) return;

    uintptr_t base = StyxFindAnogsImage();
    if (!base) return;                       // not loaded yet; caller retries
    StyxAnogs.imageBase = base;

    StyxResolveOriginals();

    // Exactly two slots. Both are read-only from the game's point of view:
    // one filters a returned string, the other zeroes a debugger flag. Nothing
    // here touches game memory, allocators, or shared string routines.
    StyxPatchSlot(base, ANOGS_SLOT_dyld_get_image_name, (void *)Styx_dyld_get_image_name);
    StyxPatchSlot(base, ANOGS_SLOT_sysctl,              (void *)Styx_sysctl);

    StyxAnogs.installed = YES;
    NSLog(@"[STYX] anogs bypass installed: %d/%d slots @ base %p",
          StyxAnogs.hooksApplied, StyxAnogs.hooksWanted, (void *)base);
}