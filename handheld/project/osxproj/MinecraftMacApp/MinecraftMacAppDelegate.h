//
//  MinecraftMacAppDelegate.h
//  minecraftpe – native macOS (10.9 Mavericks) target
//

#import <Cocoa/Cocoa.h>

@class MinecraftMacGLView;

@interface MinecraftMacAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    NSWindow*             _window;
    MinecraftMacGLView*   _glView;
}

@end
