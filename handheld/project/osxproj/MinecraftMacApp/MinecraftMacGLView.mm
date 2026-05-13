//
//  MinecraftMacGLView.mm
//

#import "MinecraftMacGLView.h"

#include "../../../src/NinecraftApp.h"
#include "../../../src/platform/input/Mouse.h"
#include "../../../src/platform/input/Multitouch.h"
#include "../../../src/platform/input/Keyboard.h"

#import <Carbon/Carbon.h> // kVK_* virtual key codes for special keys

#include <string>

// ---------------------------------------------------------------------------
// Key code translation
// ---------------------------------------------------------------------------
// The cross-platform Keyboard class indexes by Windows-style virtual key
// codes (KEY_A == 65, KEY_RETURN == 13, KEY_ESCAPE == 27, etc.). NSEvent
// gives us either a hardware scancode (`keyCode`) or the text produced
// (`charactersIgnoringModifiers`). We translate to the engine's codes here.
static int translateNSKeyCodeToEngineKey(unsigned short macKeyCode, NSString* chars)
{
    // 1) Map well-known function / special keys via kVK_* constants.
    switch (macKeyCode) {
        case kVK_Return:           return Keyboard::KEY_RETURN;
        case kVK_ANSI_KeypadEnter: return Keyboard::KEY_RETURN;
        case kVK_Delete:           return Keyboard::KEY_BACKSPACE; // backspace on Apple keyboards
        case kVK_Escape:           return Keyboard::KEY_ESCAPE;
        case kVK_Space:            return Keyboard::KEY_SPACE;
        case kVK_Tab:              return 9;
        case kVK_LeftArrow:        return 37;
        case kVK_UpArrow:          return 38;
        case kVK_RightArrow:       return 39;
        case kVK_DownArrow:        return 40;
        case kVK_Shift:            return Keyboard::KEY_LSHIFT;
        case kVK_RightShift:       return Keyboard::KEY_LSHIFT;
        case kVK_F1:               return Keyboard::KEY_F1;
        case kVK_F2:               return Keyboard::KEY_F2;
        case kVK_F3:               return Keyboard::KEY_F3;
        case kVK_F4:               return Keyboard::KEY_F4;
        case kVK_F5:               return Keyboard::KEY_F5;
        case kVK_F6:               return Keyboard::KEY_F6;
        case kVK_F7:               return Keyboard::KEY_F7;
        case kVK_F8:               return Keyboard::KEY_F8;
        case kVK_F9:               return Keyboard::KEY_F9;
        case kVK_F10:              return Keyboard::KEY_F10;
        case kVK_F11:              return Keyboard::KEY_F11;
        case kVK_F12:              return Keyboard::KEY_F12;
        default: break;
    }

    // 2) Fall back to the first printable character upper-cased. This makes
    //    'a' / 'A' both map to 0x41 (== Keyboard::KEY_A), matching the
    //    convention used by the Win32 entry point.
    if (chars && [chars length] > 0) {
        unichar c = [chars characterAtIndex:0];
        if (c >= 'a' && c <= 'z') return (int)(c - 'a' + 'A');
        if (c < 128) return (int)c;
    }
    return 0;
}

// ---------------------------------------------------------------------------
@implementation MinecraftMacGLView

- (id)initWithFrame:(NSRect)frameRect
{
    // We need the legacy / 2.1 compatibility profile so the engine's
    // fixed-function calls (glPushMatrix, glEnableClientState, ...) work.
    //
    // Try three attribute sets in order of preference:
    //   1. accelerated, 24-bit colour + 24-bit depth, legacy profile
    //      (the path real Mac hardware will take)
    //   2. same but without NSOpenGLPFAAccelerated  (headless / VM /
    //      Apple Silicon under Rosetta runners — no accelerated legacy GL)
    //   3. plain double-buffered legacy profile (last-resort minimum)
    NSOpenGLPixelFormatAttribute attrs_accel[] = {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAColorSize,   (NSOpenGLPixelFormatAttribute)24,
        NSOpenGLPFADepthSize,   (NSOpenGLPixelFormatAttribute)24,
        NSOpenGLPFAAccelerated,
        NSOpenGLPFAOpenGLProfile,
            (NSOpenGLPixelFormatAttribute)NSOpenGLProfileVersionLegacy,
        (NSOpenGLPixelFormatAttribute)0
    };
    NSOpenGLPixelFormatAttribute attrs_sw[] = {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAColorSize,   (NSOpenGLPixelFormatAttribute)24,
        NSOpenGLPFADepthSize,   (NSOpenGLPixelFormatAttribute)24,
        NSOpenGLPFAOpenGLProfile,
            (NSOpenGLPixelFormatAttribute)NSOpenGLProfileVersionLegacy,
        (NSOpenGLPixelFormatAttribute)0
    };
    NSOpenGLPixelFormatAttribute attrs_min[] = {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAOpenGLProfile,
            (NSOpenGLPixelFormatAttribute)NSOpenGLProfileVersionLegacy,
        (NSOpenGLPixelFormatAttribute)0
    };

    NSOpenGLPixelFormat* pf = nil;
    const char* picked = "none";
    pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs_accel];
    if (pf) { picked = "accelerated"; }
    else {
        pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs_sw];
        if (pf) { picked = "software"; }
        else {
            pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs_min];
            if (pf) { picked = "minimum"; }
        }
    }
    if (!pf) {
        NSLog(@"Couldn't create any OpenGL pixel format (legacy profile)");
        return nil;
    }
    NSLog(@"OpenGL pixel format: %s", picked);
    self = [super initWithFrame:frameRect pixelFormat:pf];
    [pf release];
    if (!self) return nil;

    _app        = NULL;
    _appContext = NULL;
    _platform   = NULL;
    _timer      = nil;
    _running    = NO;
    return self;
}

- (void)dealloc
{
    [self stopEngine];
    delete _app;        _app = NULL;
    delete _platform;   _platform = NULL;
    delete _appContext; _appContext = NULL;
    [super dealloc];
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isOpaque              { return YES; }

// ---------------------------------------------------------------------------
// Engine lifecycle
// ---------------------------------------------------------------------------
- (void)prepareOpenGL
{
    [super prepareOpenGL];
    [[self openGLContext] makeCurrentContext];

    // Standard vsync via swap interval = 1.
    GLint swap = 1;
    [[self openGLContext] setValues:&swap forParameter:NSOpenGLCPSwapInterval];

    if (!_platform) {
        _platform   = new AppPlatform_macOS(self);
        _appContext = new AppContext();
        _appContext->platform = _platform;
        _appContext->doRender = false;

        // External storage path: ~/Library/Application Support/MinecraftPE
        NSString* appSupport = [NSSearchPathForDirectoriesInDomains(
            NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        NSString* storage = [appSupport stringByAppendingPathComponent:@"MinecraftPE"];
        [[NSFileManager defaultManager] createDirectoryAtPath:storage
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        const char* cstorage = [storage UTF8String];
        _platform->setStoragePath(cstorage);

        _app = new NinecraftApp();
        ((Minecraft*)_app)->externalStoragePath      = cstorage;
        ((Minecraft*)_app)->externalCacheStoragePath = cstorage;
    }
}

- (void)startEngine
{
    if (_running) return;
    _running = YES;

    [[self openGLContext] makeCurrentContext];

    NSRect b = [self bounds];
    int w = (int)b.size.width;
    int h = (int)b.size.height;
    if (w < 1) w = 854;
    if (h < 1) h = 480;
    _platform->setScreenSize(w, h);

    if (!_app->isInited()) {
        _app->init(*_appContext);
    } else {
        _app->onGraphicsReset(*_appContext);
    }
    _app->setSize(w, h);

    _timer = [[NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                               target:self
                                             selector:@selector(drawFrame:)
                                             userInfo:nil
                                              repeats:YES] retain];
    // Make sure the timer also fires while the user resizes the window etc.
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSEventTrackingRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSModalPanelRunLoopMode];
}

- (void)stopEngine
{
    _running = NO;
    if (_timer) {
        [_timer invalidate];
        [_timer release];
        _timer = nil;
    }
}

- (void)drawFrame:(NSTimer*)t
{
    (void)t;
    if (!_app || !_running) return;
    if (_app->wantToQuit()) {
        [NSApp terminate:nil];
        return;
    }
    [[self openGLContext] makeCurrentContext];
    _app->update();
    [[self openGLContext] flushBuffer];
}

- (void)reshape
{
    [super reshape];
    NSRect b = [self bounds];
    int w = (int)b.size.width;
    int h = (int)b.size.height;
    if (w < 1 || h < 1) return;
    if (_platform) _platform->setScreenSize(w, h);
    if (_app)      _app->setSize(w, h);
}

// ---------------------------------------------------------------------------
// Mouse + multitouch (one pointer, id 0)
// ---------------------------------------------------------------------------
- (void)pointWithEvent:(NSEvent*)e outX:(short*)outX outY:(short*)outY
{
    NSPoint loc = [self convertPoint:[e locationInWindow] fromView:nil];
    // Cocoa origin is bottom-left, the engine expects top-left.
    NSRect b = [self bounds];
    *outX = (short)loc.x;
    *outY = (short)(b.size.height - loc.y);
}

- (void)mouseDown:(NSEvent*)e
{
    short x, y; [self pointWithEvent:e outX:&x outY:&y];
    Mouse::feed(MouseAction::ACTION_LEFT, MouseAction::DATA_DOWN, x, y);
    Multitouch::feed(1, 1, x, y, 0);
}

- (void)mouseUp:(NSEvent*)e
{
    short x, y; [self pointWithEvent:e outX:&x outY:&y];
    Mouse::feed(MouseAction::ACTION_LEFT, MouseAction::DATA_UP, x, y);
    Multitouch::feed(1, 0, x, y, 0);
}

- (void)mouseDragged:(NSEvent*)e
{
    short x, y; [self pointWithEvent:e outX:&x outY:&y];
    Mouse::feed(MouseAction::ACTION_MOVE, MouseAction::DATA_UP, x, y);
    Multitouch::feed(0, 0, x, y, 0);
}

- (void)mouseMoved:(NSEvent*)e
{
    short x, y; [self pointWithEvent:e outX:&x outY:&y];
    Mouse::feed(MouseAction::ACTION_MOVE, MouseAction::DATA_UP, x, y);
    Multitouch::feed(0, 0, x, y, 0);
}

- (void)rightMouseDown:(NSEvent*)e
{
    short x, y; [self pointWithEvent:e outX:&x outY:&y];
    Mouse::feed(MouseAction::ACTION_RIGHT, MouseAction::DATA_DOWN, x, y);
}
- (void)rightMouseUp:(NSEvent*)e
{
    short x, y; [self pointWithEvent:e outX:&x outY:&y];
    Mouse::feed(MouseAction::ACTION_RIGHT, MouseAction::DATA_UP, x, y);
}

- (void)scrollWheel:(NSEvent*)e
{
    short x, y; [self pointWithEvent:e outX:&x outY:&y];
    short dy = (short)[e deltaY];
    Mouse::feed(MouseAction::ACTION_WHEEL, MouseAction::DATA_UP, x, y, 0, dy);
}

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------
- (void)keyDown:(NSEvent*)event
{
    NSString* chars = [event charactersIgnoringModifiers];
    int engineKey = translateNSKeyCodeToEngineKey([event keyCode], chars);
    if (engineKey > 0) {
        Keyboard::feed((unsigned char)engineKey, 1);
    }

    // Also feed printable text so the chat / dialog code paths get the
    // characters the user actually typed (matches the Win32 WM_CHAR path).
    NSString* text = [event characters];
    if (text) {
        for (NSUInteger i = 0; i < [text length]; ++i) {
            unichar c = [text characterAtIndex:i];
            if (c == '\r' || c == '\n') {
                Keyboard::feed((unsigned char)Keyboard::KEY_RETURN, 1);
                Keyboard::feed((unsigned char)Keyboard::KEY_RETURN, 0);
            } else if (c == 0x7f /*DEL*/ || c == 0x08 /*BS*/) {
                // handled via keyCode above
            } else if (c >= 32 && c < 0xF700) {
                Keyboard::feedText((char)c);
            }
        }
    }
}

- (void)keyUp:(NSEvent*)event
{
    NSString* chars = [event charactersIgnoringModifiers];
    int engineKey = translateNSKeyCodeToEngineKey([event keyCode], chars);
    if (engineKey > 0) {
        Keyboard::feed((unsigned char)engineKey, 0);
    }
}

- (void)flagsChanged:(NSEvent*)event
{
    // NSEventModifierFlags was introduced in the 10.10 SDK; on the 10.9
    // SDK the underlying type is just NSUInteger.
    NSUInteger mods = [event modifierFlags];
    static NSUInteger prevMods = 0;

    NSUInteger changed = mods ^ prevMods;
    if (changed & NSShiftKeyMask) {
        Keyboard::feed((unsigned char)Keyboard::KEY_LSHIFT,
                       (mods & NSShiftKeyMask) ? 1 : 0);
    }
    prevMods = mods;
}

// ---------------------------------------------------------------------------
- (App*)app                   { return _app; }
- (AppPlatform_macOS*)platform{ return _platform; }

@end
