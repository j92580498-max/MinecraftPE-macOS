//
//  MinecraftMacGLView.h
//  minecraftpe – native macOS (10.9 Mavericks) target
//
//  NSOpenGLView subclass that owns the engine instance, drives the update /
//  render loop with an NSTimer, and forwards mouse + keyboard events into the
//  cross-platform Mouse / Keyboard / Multitouch input layer.

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>

#include "../../../src/App.h"
#include "../../../src/AppPlatform_macOS.h"

@interface MinecraftMacGLView : NSOpenGLView {
    NSTimer*  _timer;
    BOOL      _running;

    App*               _app;
    AppContext*        _appContext;
    AppPlatform_macOS* _platform;
}

- (id)initWithFrame:(NSRect)frameRect;

- (void)startEngine;
- (void)stopEngine;

- (App*)app;
- (AppPlatform_macOS*)platform;

@end
