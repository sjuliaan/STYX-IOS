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
// <mach/task_info.h> cannot be included reliably from ObjC++. Note these are
// written with plain builtin types on purpose: referring to the kernel
// typedef names (natural_t, mach_msg_type_number_t, ...) reintroduces the very
// guards we are avoiding. ABI is identical -- natural_t/integer_t are both
// unsigned int, and task_info is declared with these exact widths:
//
//   int task_info(mach_task_self_t target,
//                 task_flavor_t          flavor,
//                 flavor_t              *out,
//                 mach_msg_type_number_t *count,
//                 void                  *info,
//                 mach_msg_type_number_t  count_size);
typedef unsigned int  styx_task_t;
typedef unsigned int  styx_flavor_t;
typedef unsigned int *styx_flavor_out_t;
typedef unsigned int  styx_msg_count_t;

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
typedef uint32_t    (*Fn_dyld_image_count)(void);

static Fn_dyld_get_image_name s_orig_getImageName = NULL;
static Fn_dyld_image_count    s_orig_imageCount  = NULL;

static int  (*s_orig_stat)(const char *, struct stat *)        = NULL;
static int  (*s_orig_access)(const char *, int)                 = NULL;
static int  (*s_orig_openat)(int, const char *, int, ...)      = NULL;
static DIR *(*s_orig_opendir)(const char *)                     = NULL;
static int  (*s_orig_statfs)(const char *, struct statfs *)    = NULL;
static char *(*s_orig_getenv)(const char *)                    = NULL;
static int  (*s_orig_sysctl)(int, void *, size_t *, void *, size_t) = NULL;
static int  (*s_orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;
static int  (*s_orig_task_info)(styx_task_t, styx_flavor_t, styx_flavor_out_t,
                                styx_msg_count_t *, void *, styx_msg_count_t *) = NULL;
static void *(*s_orig_dlopen)(const char *, int)                = NULL;
static void *(*s_orig_dlsym)(void *, const char *)              = NULL;

static void StyxResolveOriginals(void) {
    if (s_orig_getImageName) return;   // once
    s_orig_getImageName = (Fn_dyld_get_image_name)dlsym(RTLD_DEFAULT, "_dyld_get_image_name");
    s_orig_imageCount  = (Fn_dyld_image_count)dlsym(RTLD_DEFAULT, "_dyld_image_count");
    s_orig_stat        = (int (*)(const char *, struct stat *))dlsym(RTLD_DEFAULT, "stat");
    s_orig_access      = (int (*)(const char *, int))dlsym(RTLD_DEFAULT, "access");
    s_orig_openat      = (int (*)(int, const char *, int, ...))dlsym(RTLD_DEFAULT, "openat");
    s_orig_opendir     = (DIR *(*)(const char *))dlsym(RTLD_DEFAULT, "opendir");
    s_orig_statfs      = (int (*)(const char *, struct statfs *))dlsym(RTLD_DEFAULT, "statfs");
    s_orig_getenv      = (char *(*)(const char *))dlsym(RTLD_DEFAULT, "getenv");
    s_orig_sysctl      = (int (*)(int, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctl");
    s_orig_sysctlbyname= (int (*)(const char *, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctlbyname");
    s_orig_task_info   = (int (*)(styx_task_t, styx_flavor_t, styx_flavor_out_t,
                                  styx_msg_count_t *, void *, styx_msg_count_t *))
                         dlsym(RTLD_DEFAULT, "task_info");
    s_orig_dlopen      = (void *(*)(const char *, int))dlsym(RTLD_DEFAULT, "dlopen");
    s_orig_dlsym       = (void *(*)(void *, const char *))dlsym(RTLD_DEFAULT, "dlsym");
}

// ---------------------------------------------------------------------------
// What we hide
// ---------------------------------------------------------------------------
static BOOL StyxPathIsSensitive(const char *path) {
    if (!path) return NO;
    // Paths from anogs' own decrypted pool, plus our own injection artefacts.
    static const char *needles[] = {
        "/Library/MobileSubstrate",
        "/usr/lib/TweakInject",
        "/var/jb/", "/var/stash", "/private/var/jb",
        "libjailbreak.dylib", "roothidepatch.dylib",
        "/bin/linker", "/Applications/Sileo.app", "/Applications/Cydia.app",
        "/Applications/Icy.app", "/Applications/MxTube.app",
        "/Applications/FakeCarrier.app", "/Applications/GameGemiOS.app",
        "/Applications/iMemEditor.app",
        // our own injected payload + anogs' expectations about it
        "Cloud.framework/Cloud",
        // frida tooling
        "frida", "FRIDA_AGENT_1.0",
        NULL
    };
    for (int i = 0; needles[i]; i++)
        if (strstr(path, needles[i])) return YES;
    return NO;
}

static BOOL StyxImageIsSensitive(const char *name) {
    if (!name) return NO;
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
// Image enumeration: return the real count, but hide matching names.
static const char *Styx_dyld_get_image_name(uint32_t index) {
    if (!StyxCfg.anogsBypassOn) goto passthrough_name;
    if (s_orig_getImageName) {
        const char *n = s_orig_getImageName(index);
        if (StyxImageIsSensitive(n)) { StyxAnogs.hidImages++; return NULL; }
        return n;
    }
passthrough_name:
    return s_orig_getImageName ? s_orig_getImageName(index) : NULL;
}

// Shrink the count so the skipped high indices are never visited.
static uint32_t Styx_dyld_image_count(void) {
    uint32_t real = s_orig_imageCount ? s_orig_imageCount() : 0;
    if (!StyxCfg.anogsBypassOn) return real;
    return real;   // count stays accurate; names return NULL instead
}

static int Styx_stat(const char *path, struct stat *st) {
    if (StyxCfg.anogsBypassOn && StyxPathIsSensitive(path)) {
        StyxAnogs.hidPaths++;
        return -1;   // ENOENT
    }
    return s_orig_stat ? s_orig_stat(path, st) : -1;
}

static int Styx_access(const char *path, int mode) {
    if (StyxCfg.anogsBypassOn && StyxPathIsSensitive(path)) {
        StyxAnogs.hidPaths++;
        return -1;
    }
    return s_orig_access ? s_orig_access(path, mode) : -1;
}

static int Styx_openat(int dirfd, const char *path, int flags, ...) {
    if (StyxCfg.anogsBypassOn && StyxPathIsSensitive(path)) {
        StyxAnogs.hidPaths++;
        errno = ENOENT;
        return -1;
    }
    // mode is only meaningful with O_CREAT; passing 0 is safe otherwise.
    return s_orig_openat ? s_orig_openat(dirfd, path, flags, 0) : -1;
}

static DIR *Styx_opendir(const char *path) {
    if (StyxCfg.anogsBypassOn && StyxPathIsSensitive(path)) {
        StyxAnogs.hidPaths++;
        errno = ENOENT;
        return NULL;
    }
    return s_orig_opendir ? s_orig_opendir(path) : NULL;
}

static int Styx_statfs(const char *path, struct statfs *sfs) {
    if (StyxCfg.anogsBypassOn && StyxPathIsSensitive(path)) {
        StyxAnogs.hidPaths++;
        errno = ENOENT;
        return -1;
    }
    return s_orig_statfs ? s_orig_statfs(path, sfs) : -1;
}

// Environment: no jailbreak indicators here anyway; deny lookups that would
// name injected tooling.
static char *Styx_getenv(const char *name) {
    if (StyxCfg.anogsBypassOn && StyxPathIsSensitive(name)) {
        StyxAnogs.hidPaths++;
        return NULL;
    }
    return s_orig_getenv ? s_orig_getenv(name) : NULL;
}

// sysctl is used for the debugger flag (KERN_PROC / KERN_PROC_PID, whose
// kinfo_proc.kp_proc.p_flag carries P_TRACED) and for device identity.
//
// We neutralise ONLY the KERN_PROC debugger probe. Device identity must stay
// genuine: faking hw.machine would be trivially inconsistent with what the
// server sees and is a worse signal than telling the truth.
static int Styx_sysctl(int name, void *oldp, size_t *oldlenp,
                       void *newp, size_t newlen) {
    if (StyxCfg.anogsBypassOn && name == 1 /*CTL_KERN*/) {
        // KERN_PROC == 12. If the caller is sizing or reading a kinfo_proc for
        // our own pid, hand back a zeroed structure: p_flag == 0 means
        // "not traced", which is true.
        const int kKernProc = 12;
        if (oldp && oldlenp && *oldlenp >= 136 /*sizeof(struct kinfo_proc) on arm64*/) {
            memset(oldp, 0, *oldlenp);
            StyxAnogs.neuteredSysctl++;
            return 0;
        }
        if (newp) {
            StyxAnogs.neuteredSysctl++;
            return 0;   // pretend the write succeeded
        }
        (void)kKernProc;
    }
    return s_orig_sysctl ? s_orig_sysctl(name, oldp, oldlenp, newp, newlen) : -1;
}

static int Styx_sysctlbyname(const char *name, void *oldp, size_t *oldlenp,
                             void *newp, size_t newlen) {
    // Device model must stay genuine. Nothing to hide here by default.
    return s_orig_sysctlbyname ? s_orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
}

// task_info is used by the root/jailbreak detector (sub_7230) with flavor
// TASK_DYLD_INFO (0x13), whose struct is:
//
//   struct task_dyld_info {
//     mach_vm_size_t all_image_info_size;   // +0x00
//     integer_t      all_image_info_format; // +0x08
//     mach_vm_size_t dyld_all_image_info_addr;
//     mach_vm_size_t dyld_all_image_info_size;
//     integer_t      dyld_all_image_info_format;
//   };
//
// It only ever tests that this is >= 1, i.e. "is dyld info available at all".
// We report a plausible constant so the check passes without exposing the real
// image enumeration.
static int Styx_task_info(styx_task_t target, styx_flavor_t flavor,
                          styx_flavor_out_t out, styx_msg_count_t *cnt,
                          void *buf, styx_msg_count_t bufsz) {
    int rc = s_orig_task_info ? s_orig_task_info(target, flavor, out, cnt, buf, bufsz) : -1;
    if (StyxCfg.anogsBypassOn && rc == 0 && buf) {
        if (flavor == 0x13 /*TASK_DYLD_INFO*/) {
            // Force a non-zero "all_image_info_size" without changing anything
            // anogs actually branches on.
            uint32_t *fmt = (uint32_t *)((char *)buf + 0x08);
            if (fmt && *fmt == 0) *fmt = 1;
            StyxAnogs.neuteredSysctl++;
        }
    }
    return rc;
}

// Dynamic module resolution: refuse to hand back injected tooling.
static void *Styx_dlopen(const char *path, int mode) {
    if (StyxCfg.anogsBypassOn && StyxPathIsSensitive(path)) {
        StyxAnogs.hiddenModules++;
        return NULL;
    }
    return s_orig_dlopen ? s_orig_dlopen(path, mode) : NULL;
}

static void *Styx_dlsym(void *handle, const char *symbol) {
    if (StyxCfg.anogsBypassOn && symbol && StyxPathIsSensitive(symbol)) {
        StyxAnogs.hiddenModules++;
        return NULL;
    }
    return s_orig_dlsym ? s_orig_dlsym(handle, symbol) : NULL;
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

    StyxPatchSlot(base, ANOGS_SLOT_dyld_get_image_name, (void *)Styx_dyld_get_image_name);
    StyxPatchSlot(base, ANOGS_SLOT_dyld_image_count,    (void *)Styx_dyld_image_count);
    StyxPatchSlot(base, ANOGS_SLOT_stat,                (void *)Styx_stat);
    StyxPatchSlot(base, ANOGS_SLOT_access,              (void *)Styx_access);
    StyxPatchSlot(base, ANOGS_SLOT_openat,              (void *)Styx_openat);
    StyxPatchSlot(base, ANOGS_SLOT_opendir,             (void *)Styx_opendir);
    StyxPatchSlot(base, ANOGS_SLOT_statfs,              (void *)Styx_statfs);
    StyxPatchSlot(base, ANOGS_SLOT_getenv,              (void *)Styx_getenv);
    StyxPatchSlot(base, ANOGS_SLOT_sysctl,              (void *)Styx_sysctl);
    StyxPatchSlot(base, ANOGS_SLOT_sysctlbyname,        (void *)Styx_sysctlbyname);
    StyxPatchSlot(base, ANOGS_SLOT_task_info,           (void *)Styx_task_info);
    StyxPatchSlot(base, ANOGS_SLOT_dlopen,              (void *)Styx_dlopen);
    StyxPatchSlot(base, ANOGS_SLOT_dlsym,               (void *)Styx_dlsym);

    StyxAnogs.installed = YES;
    NSLog(@"[STYX] anogs bypass installed: %d/%d slots @ base %p",
          StyxAnogs.hooksApplied, StyxAnogs.hooksWanted, (void *)base);
}