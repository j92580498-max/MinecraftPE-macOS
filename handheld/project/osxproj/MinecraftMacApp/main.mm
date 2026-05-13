//
//  main.mm
//  minecraftpe – native macOS (10.9 Mavericks) target
//

#import <Cocoa/Cocoa.h>
#import "MinecraftMacAppDelegate.h"

int main(int argc, const char* argv[])
{
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        MinecraftMacAppDelegate* d = [[MinecraftMacAppDelegate alloc] init];
        [app setDelegate:d];
        [app run];
        // app retained the delegate, so we just leak it on exit like the
        // standard NSApplicationMain template does.
    }
    (void)argc; (void)argv;
    return 0;
}
