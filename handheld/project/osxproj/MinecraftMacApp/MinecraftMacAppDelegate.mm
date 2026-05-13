//
//  MinecraftMacAppDelegate.mm
//

#import "MinecraftMacAppDelegate.h"
#import "MinecraftMacGLView.h"

#include "../../../src/App.h"

// Mavericks (10.9) used the old, undecorated NSWindowMask names. We keep
// using the legacy spellings so that this file builds cleanly against the
// 10.9 SDK without any version-specific shims.
#ifndef NSWindowStyleMaskTitled
#  define NSWindowStyleMaskTitled        NSTitledWindowMask
#  define NSWindowStyleMaskClosable      NSClosableWindowMask
#  define NSWindowStyleMaskMiniaturizable NSMiniaturizableWindowMask
#  define NSWindowStyleMaskResizable     NSResizableWindowMask
#endif

@implementation MinecraftMacAppDelegate

- (id)init
{
    self = [super init];
    if (!self) return nil;
    _window = nil;
    _glView = nil;
    return self;
}

- (void)dealloc
{
    [_glView release];
    [_window release];
    [super dealloc];
}

// ---------------------------------------------------------------------------
// Menu (File / Edit / Help). Minimal and idiomatic enough to look at home on
// Mavericks. Quit is wired to NSApp terminate:.
// ---------------------------------------------------------------------------
- (void)buildMenuBar
{
    NSMenu* mainMenu = [[[NSMenu alloc] init] autorelease];

    NSMenuItem* appItem = [[[NSMenuItem alloc] init] autorelease];
    [mainMenu addItem:appItem];

    NSMenu* appMenu = [[[NSMenu alloc] init] autorelease];
    NSString* name = [[NSProcessInfo processInfo] processName];
    [appMenu addItemWithTitle:[@"About " stringByAppendingString:name]
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[@"Hide " stringByAppendingString:name]
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:name]
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];

    [NSApp setMainMenu:mainMenu];
}

// ---------------------------------------------------------------------------
- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    (void)aNotification;

    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self buildMenuBar];

    NSRect contentRect = NSMakeRect(0, 0, 854, 480);

    NSUInteger style =
        NSWindowStyleMaskTitled         |
        NSWindowStyleMaskClosable       |
        NSWindowStyleMaskMiniaturizable |
        NSWindowStyleMaskResizable;

    _window = [[NSWindow alloc] initWithContentRect:contentRect
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"Minecraft PE"];
    [_window setDelegate:self];
    [_window setAcceptsMouseMovedEvents:YES];
    [_window center];

    _glView = [[MinecraftMacGLView alloc] initWithFrame:contentRect];
    [_window setContentView:_glView];
    [_window makeFirstResponder:_glView];

    [_glView startEngine];

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
    (void)aNotification;
    [_glView stopEngine];
    if (_glView && [_glView app]) {
        [_glView app]->quit();
    }
}

@end
