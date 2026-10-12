// ============================================================================
// Minimal ARM64 inline hook — mirrors CLOUD's approach (vm_protect + patch,
// no Substrate/Dobby/fishhook dependency).
//
// Overwrites 16 bytes at the target with:
//     LDR X16, #8      ; 0x58000030
//     BR  X16          ; 0xD61F0200
//     .quad replacement
//
// A trampoline is mmap'd RWX holding the original 16 bytes followed by an
// absolute jump back to target+16, so `orig` can be called normally.
//
// CONSTRAINT: the target function must be >= 16 bytes long. All hooks in this
// project target full generated il2cpp methods, which are far longer.
// ============================================================================
#pragma once
#import <mach/mach.h>
#import <sys/mman.h>
#import <libkern/OSCacheControl.h>
#import <stdint.h>
#import <string.h>

static inline int StyxProtectRWX(uintptr_t addr, size_t size) {
    kern_return_t kr = vm_protect(mach_task_self(),
                                  (vm_address_t)addr, (vm_size_t)size, false,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    return (int)kr;
}

static inline void StyxFlushICache(uintptr_t addr, size_t size) {
    // NOTE: do not use __builtin___clear_cache here. It lowers to a call to the
    // __clear_cache libcall, which modern iOS SDKs do not export; it only exists
    // as a static inline in <libkern/OSCacheControl.h>, so the link fails with
    // "Undefined symbols: ___clear_cache" unless that header is imported.
    __clear_cache((void *)addr, (void *)(addr + size));
}

// Returns a fresh RWX trampoline with `size` bytes copied from target,
// terminated by an absolute branch back to target+size.
static inline void *StyxMakeTrampoline(void *target, size_t size) {
    size_t page = 0x1000;
    void *tramp = mmap(NULL, page, PROT_READ | PROT_WRITE | PROT_EXEC,
                       MAP_ANON | MAP_PRIVATE, -1, 0);
    if (tramp == MAP_FAILED) return NULL;

    memcpy(tramp, target, size);

    // absolute jump back: LDR X17, #8 ; BR X17 ; .quad target+size
    uint32_t back[4] = {0x58000031u, 0xD61F0220u, 0u, 0u};
    back[2] = (uint32_t)((uint64_t)target + size);
    back[3] = (uint32_t)(((uint64_t)target + size) >> 32);
    memcpy((char *)tramp + size, back, sizeof(back));

    StyxFlushICache((uintptr_t)tramp, page);
    return tramp;
}

static inline int StyxHookFunction(void *target, void *replacement, void **orig) {
    if (!target || !replacement) return -1;

    void *tramp = StyxMakeTrampoline(target, 16);
    if (!tramp) return -2;
    if (orig) *orig = tramp;

    if (StyxProtectRWX((uintptr_t)target, 16) != 0) return -3;

    // LDR X16, #8 ; BR X16 ; <64-bit replacement address>
    uint32_t insn[4];
    insn[0] = 0x58000030u;  // LDR X16, #8
    insn[1] = 0xD61F0200u;  // BR X16
    insn[2] = (uint32_t)((uint64_t)replacement);
    insn[3] = (uint32_t)(((uint64_t)replacement) >> 32);
    memcpy(target, insn, sizeof(insn));

    StyxFlushICache((uintptr_t)target, 16);
    return 0;
}
