#import <Foundation/Foundation.h>
#import "DisplayBridge.h"

// CGVirtualDisplay 是 macOS 私有接口，通过运行时检查类是否存在。
@interface PDDescriptor : NSObject
@property(copy) NSString *name;
@property unsigned maxPixelsWide;
@property unsigned maxPixelsHigh;
@property uint32_t vendorID;
@property uint32_t productID;
@property uint32_t serialNum;
@property CGSize sizeInMillimeters;
@property dispatch_queue_t queue;
@end
@interface PDMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)rate;
@end
@interface PDSettings : NSObject
@property BOOL hiDPI;
@property(copy) NSArray *modes;
@end
@interface PDVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(readonly) CGDirectDisplayID displayID;
@end

void *PDDisplayCreate(const char *name, unsigned width, unsigned height) {
    @autoreleasepool {
        Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
        Class displayClass = NSClassFromString(@"CGVirtualDisplay");
        if (!descriptorClass || !displayClass) return NULL;
        PDDescriptor *descriptor = [[descriptorClass alloc] init];
        descriptor.name = [NSString stringWithUTF8String:name];
        descriptor.maxPixelsWide = width;
        descriptor.maxPixelsHigh = height;
        descriptor.vendorID = 0x5044;
        descriptor.productID = 1;
        descriptor.serialNum = arc4random_uniform(UINT32_MAX - 1) + 1;
        descriptor.sizeInMillimeters = CGSizeMake(width * 25.4 / 220, height * 25.4 / 220);
        descriptor.queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        PDVirtualDisplay *display = [[displayClass alloc] initWithDescriptor:descriptor];
        return (void *)CFBridgingRetain(display);
    }
}

bool PDDisplayApply(void *handle, unsigned width, unsigned height, bool hiDPI) {
    @autoreleasepool {
        Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
        Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
        if (!handle || !settingsClass || !modeClass) return false;
        PDSettings *settings = [[settingsClass alloc] init];
        settings.hiDPI = hiDPI;
        settings.modes = @[[[modeClass alloc] initWithWidth:hiDPI ? width / 2 : width
                                                   height:hiDPI ? height / 2 : height refreshRate:60]];
        return [(__bridge PDVirtualDisplay *)handle applySettings:settings];
    }
}

CGDirectDisplayID PDDisplayID(void *handle) { return [(__bridge PDVirtualDisplay *)handle displayID]; }
void PDDisplayRelease(void *handle) { if (handle) CFRelease(handle); }
