#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include "ThermonCore.h"

typedef struct IOReportSubscriptionCF * IOReportSubscriptionRef;
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef, CFMutableDictionaryRef, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef);
extern int32_t IOReportStateGetCount(CFDictionaryRef);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef, int32_t);
extern int64_t IOReportStateGetResidency(CFDictionaryRef, int32_t);

static IOReportSubscriptionRef g_sub;
static CFMutableDictionaryRef g_subbed;
static CFDictionaryRef g_prev;
static NSArray<NSNumber *> * g_freqs;
static double g_fmax;

static NSArray<NSNumber *> * gpuFreqsMHz(void) {
    NSMutableArray * out = [NSMutableArray array];
    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &it) != KERN_SUCCESS) return out;
    io_object_t e;
    while ((e = IOIteratorNext(it))) {
        io_name_t name; IORegistryEntryGetName(e, name);
        if (strcmp(name, "pmgr") == 0) {
            CFTypeRef d = IORegistryEntryCreateCFProperty(e, CFSTR("voltage-states9"), kCFAllocatorDefault, 0);
            if (d && CFGetTypeID(d) == CFDataGetTypeID()) {
                const uint32_t * v = (const uint32_t *)CFDataGetBytePtr((CFDataRef)d);
                size_t n = CFDataGetLength((CFDataRef)d) / 8;
                for (size_t i = 0; i < n; i++) {
                    uint32_t f = v[2 * i];
                    double mhz = f > 100000000 ? f / 1e6 : (f > 100000 ? f / 1e3 : f);
                    if (mhz > 0) [out addObject:@(mhz)];
                }
            }
            if (d) CFRelease(d);
        }
        IOObjectRelease(e);
    }
    IOObjectRelease(it);
    return out;
}

bool thermon_init(void) {
    g_freqs = gpuFreqsMHz();
    g_fmax = 0; for (NSNumber * f in g_freqs) g_fmax = MAX(g_fmax, f.doubleValue);
    CFDictionaryRef ch = IOReportCopyChannelsInGroup(CFSTR("GPU Stats"), CFSTR("GPU Performance States"), 0, 0, 0);
    if (!ch) return false;
    CFMutableDictionaryRef chm = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, ch);
    CFRelease(ch);
    g_sub = IOReportCreateSubscription(NULL, chm, &g_subbed, 0, NULL);
    if (!g_sub) return false;
    g_prev = IOReportCreateSamples(g_sub, g_subbed, NULL);
    return g_prev != NULL;
}

bool thermon_sample(ThermonSample * out) {
    if (!g_sub || !g_prev) return false;
    CFDictionaryRef cur = IOReportCreateSamples(g_sub, g_subbed, NULL);
    if (!cur) return false;
    CFDictionaryRef delta = IOReportCreateSamplesDelta(g_prev, cur, NULL);
    CFRelease(g_prev); g_prev = cur;
    if (!delta) return false;
    double active = 0, total = 0, wsum = 0;
    NSArray * chans = ((__bridge NSDictionary *)delta)[@"IOReportChannels"];
    for (id c in chans) {
        CFDictionaryRef cd = (__bridge CFDictionaryRef)c;
        if (![(__bridge NSString *)IOReportChannelGetChannelName(cd) isEqualToString:@"GPUPH"]) continue;
        int32_t n = IOReportStateGetCount(cd);
        int pidx = 0;
        for (int32_t i = 0; i < n; i++) {
            NSString * sn = (__bridge NSString *)IOReportStateGetNameForIndex(cd, i);
            double r = (double)IOReportStateGetResidency(cd, i);
            total += r;
            if ([sn isEqualToString:@"OFF"] || [sn isEqualToString:@"IDLE"] || [sn isEqualToString:@"DOWN"]) continue;
            active += r;
            wsum += r * (pidx < (int)g_freqs.count ? g_freqs[pidx].doubleValue : 0);
            pidx++;
        }
    }
    CFRelease(delta);
    out->gpuBusyPct = total > 0 ? 100.0 * active / total : 0;
    out->gpuMHz = active > 0 ? wsum / active : 0;
    out->gpuMaxMHz = g_fmax;
    out->gpuClockPct = g_fmax > 0 ? 100.0 * out->gpuMHz / g_fmax : 0;
    out->thermalState = (int)[NSProcessInfo processInfo].thermalState;
    return true;
}
