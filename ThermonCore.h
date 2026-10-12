// ThermonCore — sudo-less GPU clock/busy sampler (IOReport) + macOS thermal pressure. Used by ThermonBar and thermon.
#pragma once
#include <stdbool.h>
typedef struct { double gpuBusyPct, gpuMHz, gpuMaxMHz, gpuClockPct; int thermalState; } ThermonSample;  // thermal 0..3
bool thermon_init(void);
bool thermon_sample(ThermonSample * out);   // delta since the previous call
