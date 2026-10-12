// ============================================================================
// STYX-iOS — anogs (Tencent TSS) bypass — public interface
// ============================================================================
#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    BOOL        installed;      // anogs image found and pointer table patched
    int         hooksApplied;   // pointers rewritten
    int         hooksWanted;    // pointers we intended to rewrite
    uintptr_t   imageBase;      // resolved anogs base

    // counters, incremented by the interposers
    uint64_t    hidImages;      // _dyld_get_image_name calls hidden
    uint64_t    hidPaths;       // filesystem probes denied
    uint64_t    hidRegions;     // memory regions hidden
    uint64_t    hidThreads;     // suspicious threads hidden
    uint64_t    neuteredSysctl; // debugger probes / task_info neutralised
    uint64_t    hiddenModules;  // dlopen/dlsym blocked
} StyxAnogsStats;

extern StyxAnogsStats StyxAnogs;

// Idempotent. Returns immediately if anogs is not mapped yet; the caller is
// expected to retry (see StyxMain.xm).
void StyxAnogsInstall(void);