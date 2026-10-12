// thermon — sudo-less 1 Hz GPU throttling monitor for Apple Silicon (2026-10-11).
// Prints: time, macOS thermal pressure (ProcessInfo.thermalState), GPU busy %, GPU average active clock (MHz and % of
// the top DVFS state), as text or JSON lines (--json). GPU clocks come from IOReport "GPU Stats / GPU Performance
// States" residencies (the same source macmon uses), weighted by the pmgr "voltage-states9" frequency table.
// A GPU that is busy but well below its top clock while thermal pressure rises = thermal/power throttling.
// Build: clang -O2 -fobjc-arc thermon.m -o thermon -framework Foundation -framework IOKit -lIOReport
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <unistd.h>

typedef struct IOReportSubscriptionCF * IOReportSubscriptionRef;
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef, CFMutableDictionaryRef, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef);
extern int32_t IOReportStateGetCount(CFDictionaryRef);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef, int32_t);
extern int64_t IOReportStateGetResidency(CFDictionaryRef, int32_t);

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
                    double mhz = f > 100000000 ? f / 1e6 : (f > 100000 ? f / 1e3 : f);   // Hz or kHz depending on chip
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

static const char * thermalName(NSProcessInfoThermalState s) {
    switch (s) { case NSProcessInfoThermalStateNominal: return "nominal"; case NSProcessInfoThermalStateFair: return "fair";
                 case NSProcessInfoThermalStateSerious: return "serious"; case NSProcessInfoThermalStateCritical: return "critical"; }
    return "?";
}

int main(int argc, char ** argv) {
    @autoreleasepool {
        bool json = argc > 1 && strcmp(argv[1], "--json") == 0;
        double interval = 1.0;
        NSArray<NSNumber *> * freqs = gpuFreqsMHz();
        double fmax = 0; for (NSNumber * f in freqs) fmax = MAX(fmax, f.doubleValue);
        CFDictionaryRef ch = IOReportCopyChannelsInGroup(CFSTR("GPU Stats"), CFSTR("GPU Performance States"), 0, 0, 0);
        CFMutableDictionaryRef chm = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, ch);
        CFMutableDictionaryRef subbed = NULL;
        IOReportSubscriptionRef sub = IOReportCreateSubscription(NULL, chm, &subbed, 0, NULL);
        if (!sub) { fprintf(stderr, "IOReport subscription failed\n"); return 1; }
        if (!json) fprintf(stderr, "GPU DVFS states: %lu, top %.0f MHz\n", (unsigned long)freqs.count, fmax);
        CFDictionaryRef prev = IOReportCreateSamples(sub, subbed, NULL);
        for (;;) {
            usleep((useconds_t)(interval * 1e6));
            CFDictionaryRef cur = IOReportCreateSamples(sub, subbed, NULL);
            CFDictionaryRef delta = IOReportCreateSamplesDelta(prev, cur, NULL);
            CFRelease(prev); prev = cur;
            NSArray * chans = ((__bridge NSDictionary *)delta)[@"IOReportChannels"];
            double active = 0, total = 0, wsum = 0;
            for (id c in chans) {
                CFDictionaryRef cd = (__bridge CFDictionaryRef)c;
                NSString * cname = (__bridge NSString *)IOReportChannelGetChannelName(cd);
                if (![cname isEqualToString:@"GPUPH"]) continue;
                int32_t n = IOReportStateGetCount(cd);
                int pidx = 0;
                for (int32_t i = 0; i < n; i++) {
                    NSString * sn = (__bridge NSString *)IOReportStateGetNameForIndex(cd, i);
                    double r = (double)IOReportStateGetResidency(cd, i);
                    total += r;
                    if ([sn isEqualToString:@"OFF"] || [sn isEqualToString:@"IDLE"] || [sn isEqualToString:@"DOWN"]) continue;
                    active += r;
                    double f = pidx < (int)freqs.count ? freqs[pidx].doubleValue : 0;
                    wsum += r * f;
                    pidx++;
                }
            }
            CFRelease(delta);
            double util = total > 0 ? 100.0 * active / total : 0;
            double mhz = active > 0 ? wsum / active : 0;
            double pct = fmax > 0 ? 100.0 * mhz / fmax : 0;
            const char * th = thermalName([NSProcessInfo processInfo].thermalState);
            time_t t = time(NULL); char ts[16]; strftime(ts, sizeof ts, "%H:%M:%S", localtime(&t));
            if (json) printf("{\"t\":\"%s\",\"thermal\":\"%s\",\"gpu_busy\":%.1f,\"gpu_mhz\":%.0f,\"gpu_clock_pct\":%.1f,\"gpu_max_mhz\":%.0f}\n", ts, th, util, mhz, pct, fmax);
            else printf("%s thermal=%-8s gpu_busy=%5.1f%% gpu_clock=%5.0f MHz (%5.1f%% of %.0f)\n", ts, th, util, mhz, pct, fmax);
            fflush(stdout);
        }
    }
}
