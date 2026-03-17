#import "AppRevealModule.h"
#import <React/RCTUtils.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import "RNAppRevealSpec.h"
#endif

// Swift class is accessible via the generated Swift header
#import "appreveal-Swift.h"

@implementation AppRevealModule

RCT_EXPORT_MODULE(AppReveal)

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

// MARK: - Old arch exports

RCT_EXPORT_METHOD(start:(double)port) {
    [[AppRevealRNBridge shared] startWithPort:(NSInteger)port];
}

RCT_EXPORT_METHOD(stop) {
    [[AppRevealRNBridge shared] stop];
}

RCT_EXPORT_METHOD(setScreen:(NSString *)key
                  title:(NSString *)title
                  confidence:(double)confidence) {
    [[AppRevealRNBridge shared] setScreenWithKey:key title:title confidence:confidence];
}

RCT_EXPORT_METHOD(setNavigationStack:(NSArray *)routes
                  current:(NSString *)current
                  modals:(NSArray *)modals) {
    [[AppRevealRNBridge shared] setNavigationStack:routes current:current modals:modals];
}

RCT_EXPORT_METHOD(setFeatureFlags:(NSDictionary *)flags) {
    [[AppRevealRNBridge shared] setFeatureFlags:flags];
}

RCT_EXPORT_METHOD(captureNetworkCall:(NSDictionary *)call) {
    [[AppRevealRNBridge shared] captureNetworkCall:call];
}

RCT_EXPORT_METHOD(captureError:(NSString *)domain
                  message:(NSString *)message
                  stackTrace:(NSString *)stackTrace) {
    [[AppRevealRNBridge shared] captureErrorWithDomain:domain message:message stackTrace:stackTrace];
}

// MARK: - New arch (TurboModules)

#ifdef RCT_NEW_ARCH_ENABLED

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params {
    return std::make_shared<facebook::react::NativeAppRevealSpecJSI>(params);
}

#endif

@end
