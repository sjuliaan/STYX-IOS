// ============================================================================
// Minimal ARM64 inline hook (no Substrate/Dobby/fishhook dependency).
//
// Two entry points:
//
//   StyxHookFunction      classic LDR/BR literal jump (16 bytes)
//   StyxHookFunctionRel   PC-relative ADRP/ADD/BR    (16 bytes)
//
// PREFER StyxHookFunctionRel. anogs performs a hook-signature check: it
// dlopen()s a library, dlsym()s a symbol, then reads the first instruction of
// the resolved function and compares it against 0x58000050, which is the
// Substrate-style `LDR X16, #8` prologue (verified at sub_7230:0x77E4). The
// literal-jump form writes exactly those bytes, so it is a direct match. The
// PC-relative form has no literal in .rodata and does not match.
//
// CONSTRAINT: the target function must be >= 16 bytes long. All hooks in this
// project target full generated il2cpp methods, which are far longer.
// ============================================================================
#pragma once
#import <mach/mach.h>
#import <sys/mman.h>
#import <stdint.h>
#import <string.h>

static inline int StyxProtectRWX(uintptr_t addr, size_t size) {
    kern_return_t kr = vm_protect(mach_task_self(),
                                  (vm_address_t)addr, (vm_size_t)size, false,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    return (int)kr;
}

static inline void StyxFlushICache(uintptr_t addr, size_t size) {
#if defined(__aarch64__)
    // Emit the AArch64 cache-maintenance sequence directly.
    //
    // Do NOT use __builtin___clear_cache or <libkern/OSCacheControl.h> here.
    // Both lower to a call to the __clear_cache libcall, and that symbol is not
    // exported by the iOS libSystem, so the dylib fails to link with
    // "Undefined symbols: ___clear_cache". This inline sequence is precisely
    // what that routine performs, with no external symbol dependency.
    uintptr_t start = addr & ~(uintptr_t)0xFFF;
    uintptr_t end   = (addr + size + 0xFFF) & ~(uintptr_t)0xFFF;
    for (uintptr_t p = start; p < end; p += 0x1000)
        asm volatile("dc cvau, %0" :: "r"(p) : "memory");
    asm volatile("dsb ish" ::: "memory");
    for (uintptr_t p = start; p < end; p += 0x1000)
        asm volatile("ic ivau, %0" :: "r"(p) : "memory");
    asm volatile("isb" ::: "memory");
#else
    __builtin___clear_cache((char *)addr, (char *)(addr + size));
#endif
}

// Returns a fresh RWX trampoline with `size` bytes copied from target,
// terminated by an absolute jump back to target+size.
//
// The back-jump loads the literal at PC+8 (0x58000051). It MUST be #8, not #4:
// the .quad sits 8 bytes past the LDR. An earlier revision used #4, which made
// the load pick up the BR instruction itself and branch into garbage.
static inline void *StyxMakeTrampoline(void *target, size_t size) {
    size_t page = 0x1000;
    void *tramp = mmap(NULL, page, PROT_READ | PROT_WRITE | PROT_EXEC,
                       MAP_ANON | MAP_PRIVATE, -1, 0);
    if (tramp == MAP_FAILED) return NULL;

    memcpy(tramp, target, size);

    // absolute jump back: LDR X17, #8 ; BR X17 ; .quad target+size
    uint32_t back[4] = {0x58000051u, 0xD61F0220u, 0u, 0u};
    back[2] = (uint32_t)((uint64_t)target + size);
    back[3] = (uint32_t)(((uint64_t)target + size) >> 32);
    memcpy((char *)tramp + size, back, sizeof(back));

    StyxFlushICache((uintptr_t)tramp, page);
    return tramp;
}

// Classic literal jump. Overwrites 16 bytes with:
//
//     LDR X16, #8        ; 0x58000050
//     BR  X16            ; 0xD61F0200
//     .quad replacement
//
// NOTE this writes the exact bytes anogs screens for. Prefer
// StyxHookFunctionRel unless you specifically need this form.
static inline int StyxHookFunction(void *target, void *replacement, void **orig) {
    if (!target || !replacement) return -1;

    void *tramp = StyxMakeTrampoline(target, 16);
    if (!tramp) return -2;
    if (orig) *orig = tramp;

    if (StyxProtectRWX((uintptr_t)target, 16) != 0) return -3;

    uint32_t insn[4];
    insn[0] = 0x58000050u;  // LDR X16, #8  (PC-relative -> literal at +8)
    insn[1] = 0xD61F0200u;  // BR X16
    insn[2] = (uint32_t)((uint64_t)replacement);
    insn[3] = (uint32_t)(((uint64_t)replacement) >> 32);
    memcpy(target, insn, sizeof(insn));

    StyxFlushICache((uintptr_t)target, 16);
    return 0;
}

// PC-relative hook. Overwrites 16 bytes with:
//
//     ADRP X16, #page    ; 0x90000010 | imm
//     ADD  X16, X16, #lo ; 0x91000010 | imm
//     BR   X16           ; 0xD61F0200
//     NOP                 ; padding to 16
//
// No literal pointer is emitted, so a scanner comparing the first instruction
// against the Substrate prologue does not match, and there is no readable
// replacement address sitting in the patch.
//
// ADRP is PC-relative over +/-4 GB (a 21-bit signed field scaled by 4 KB), so
// the target must be within that range. Every arm64 image in a normal app is
// mapped in a narrow band well inside it. We verify at runtime rather than
// assuming, and fall back to the literal form if the gap is too large.
#define STYX_ADRP_MAX_PAGES   (1 << 19)   // 2^19 pages = 4 GB

static inline int StyxHookFunctionRel(void *target, void *replacement, void **orig) {
    if (!target || !replacement) return -1;

    int64_t pages = (int64_t)((((uint64_t)replacement) & ~0xFFFULL)
                            - (((uint64_t)target) & ~0xFFFULL)) >> 12;
    if (pages <= -STYX_ADRP_MAX_PAGES || pages >= STYX_ADRP_MAX_PAGES) {
        return StyxHookFunction(target, replacement, orig);   // out of ADRP range
    }

    void *tramp = StyxMakeTrampoline(target, 16);
    if (!tramp) return -2;
    if (orig) *orig = tramp;

    if (StyxProtectRWX((uintptr_t)target, 16) != 0) return -3;

    uint32_t imm21  = (uint32_t)(pages & 0x1FFFFF);        // 21-bit two's complement
    uint32_t immlo  = imm21 & 0x3;
    uint32_t immhi  = (imm21 >> 2) & 0x7FFFF;

    uint32_t adrp = 0x90000010u | (immlo << 29) | (immhi << 5);
    uint32_t add  = 0x91000010u | (((uint32_t)(uint64_t)replacement & 0xFFF) << 10);
    uint32_t br   = 0xD61F0200u;
    uint32_t nop  = 0xD503201Fu;

    uint32_t insn[4] = { adrp, add, br, nop };
    memcpy(target, insn, sizeof(insn));

    StyxFlushICache((uintptr_t)target, 16);
    return 0;
}
