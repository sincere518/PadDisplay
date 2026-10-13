#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

void *PDDisplayCreate(const char *name, unsigned width, unsigned height);
bool PDDisplayApply(void *handle, unsigned width, unsigned height, bool hiDPI);
CGDirectDisplayID PDDisplayID(void *handle);
void PDDisplayRelease(void *handle);
