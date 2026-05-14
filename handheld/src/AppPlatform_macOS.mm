#include "AppPlatform_macOS.h"

#import <Cocoa/Cocoa.h>
#import <AppKit/AppKit.h>

#include "client/gui/screens/DialogDefinitions.h"
#include "client/OptionStrings.h"
#include <cstdlib>

// ---------------------------------------------------------------------------
// Texture loading
// ---------------------------------------------------------------------------
// We mirror the iOS implementation: pull a PNG out of the app bundle (or the
// data/ folder beside the .app for development builds), decode it through
// CoreGraphics into RGBA8 pixel data, hand the buffer over to the engine.
//
// On macOS the equivalent of UIImage is NSImage, but NSImage may flip pixels
// or composite premultiplied alpha unexpectedly, so we go via NSBitmapImageRep
// for a deterministic decode path.
//
// Engine callers pass paths like "gui/gui.png", "terrain.png", "mob/cow.png".
// In our app bundle the data/ tree is copied verbatim to Contents/Resources/,
// so the real on-disk location is Contents/Resources/images/<path>.png. We
// purposefully do NOT strip the subdirectory the way the iOS port did — iOS
// puts all PNGs flat in the bundle, but on macOS we keep the nested layout
// because pathForResource:inDirectory: only finds the top-level Resources/
// folder (and *.lproj children) without it.

static NSString* findBundleResource(const std::string& relpath, NSString* ext) {
    // relpath here looks like "gui/gui" or "terrain" or "mob/cow" — no extension.
    std::string sep("/");
    size_t slash = relpath.rfind("/");
    std::string subdir = (slash == std::string::npos) ? std::string() : relpath.substr(0, slash);
    std::string base   = (slash == std::string::npos) ? relpath        : relpath.substr(slash+1);

    NSString *nsBase = [NSString stringWithUTF8String:base.c_str()];

    // Primary: real layout in our bundle is Resources/images/<subdir>/<base>.<ext>
    // pathForResource:ofType:inDirectory: accepts a Resources-relative subdirectory.
    NSMutableArray *bundleSubdirs = [NSMutableArray array];
    if (!subdir.empty()) {
        [bundleSubdirs addObject:[NSString stringWithFormat:@"images/%s", subdir.c_str()]];
        [bundleSubdirs addObject:[NSString stringWithUTF8String:subdir.c_str()]];
    }
    [bundleSubdirs addObject:@"images"];
    [bundleSubdirs addObject:@""];

    for (NSString *sub in bundleSubdirs) {
        NSString *path = [[NSBundle mainBundle] pathForResource:nsBase
                                                         ofType:ext
                                                    inDirectory:sub];
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    }

    // Last-ditch flat fallback (the way the iOS port shipped resources).
    NSString *flat = [[NSBundle mainBundle] pathForResource:nsBase ofType:ext];
    if (flat) return flat;

    // Development fallback: look beside the .app in handheld/data/images
    // (matches the layout used by the Win32 target).
    NSString *bundleParent = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    NSArray *candidates = [NSArray arrayWithObjects:
        [NSString stringWithFormat:@"%@/data/images/%s.%@", bundleParent, relpath.c_str(), ext],
        [NSString stringWithFormat:@"%@/data/%s.%@",        bundleParent, relpath.c_str(), ext],
        [NSString stringWithFormat:@"%@/../data/images/%s.%@", bundleParent, relpath.c_str(), ext],
        [NSString stringWithFormat:@"%@/../data/%s.%@",        bundleParent, relpath.c_str(), ext],
        nil];
    for (NSString *cand in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:cand]) return cand;
    }
    return nil;
}

TextureData AppPlatform_macOS::loadTexture(const std::string& filename_, bool /*textureFolder*/)
{
    TextureData out;
    out.memoryHandledExternally = false;

    // Strip extension only — keep the subdirectory so we can find files like
    // images/gui/gui.png. The iOS port stripped the directory because its
    // bundle was flat, but ours mirrors the source data/ layout.
    std::string filename = filename_;
    size_t dotp = filename.rfind(".");
    if (dotp != std::string::npos) {
        filename = filename.substr(0, dotp);
    }

    NSString *path = findBundleResource(filename, @"png");
    NSData *texData = path ? [[NSData alloc] initWithContentsOfFile:path] : nil;

    NSImage *image = texData ? [[NSImage alloc] initWithData:texData] : nil;
    CGImageRef cgImage = NULL;
    if (image) {
        NSRect rect = NSMakeRect(0, 0, image.size.width, image.size.height);
        cgImage = [image CGImageForProposedRect:&rect context:nil hints:nil];
    }

    if (cgImage) {
        out.w = (int)CGImageGetWidth(cgImage);
        out.h = (int)CGImageGetHeight(cgImage);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        out.data = new unsigned char[4 * out.w * out.h];
        CGContextRef imgctx = CGBitmapContextCreate(
            out.data, out.w, out.h, 8, 4 * out.w, colorSpace,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(colorSpace);
        CGContextClearRect(imgctx, CGRectMake(0, 0, out.w, out.h));
        CGContextDrawImage(imgctx, CGRectMake(0, 0, out.w, out.h), cgImage);
        CGContextRelease(imgctx);
    } else {
        LOGI("Couldn't find file: %s\n", filename.c_str());
        // Same noise-fallback as iOS so the world is still visible
        // even if a texture is missing.
        out.w = 16;
        out.h = 16;
        bool isTerrain = (filename.find("terrain") != std::string::npos);
        int numPixels = out.w * out.h;
        out.data = new unsigned char[4 * numPixels];
        if (isTerrain) {
            for (int i = 0; i < numPixels; ++i) {
                unsigned int color = 0xff000000 | ((rand() & 0xff) << 16) | (rand() & 0xffff);
                *((int*)(&out.data[4*i])) = color;
            }
        } else {
            unsigned int color = 0xff000000 | ((rand() & 0xff) << 16) | (rand() & 0xffff);
            for (int i = 0; i < numPixels; ++i) {
                *((int*)(&out.data[4*i])) = color;
            }
        }
    }
    [image release];
    [texData release];
    return out;
}

BinaryBlob AppPlatform_macOS::readAssetFile(const std::string& filename_)
{
    // Engine callers pass paths like "lang/en_US.lang" or "terrain.png".
    // The iOS port stripped both the directory and the extension because its
    // bundle was completely flat. Our macOS bundle mirrors the source
    // data/ layout (Resources/lang/en_US.lang, Resources/sound/aac/...,
    // Resources/images/...), so we must keep the subdirectory part —
    // otherwise findBundleResource only looks under images/ and the
    // bundle root and lang/ etc. is invisible. Only the extension is
    // stripped; findBundleResource already searches the raw subdir as a
    // fallback.
    std::string filename = filename_;
    std::string ext;
    size_t dotp = filename.rfind(".");
    size_t slashp = filename.rfind("/");
    if (dotp != std::string::npos && (slashp == std::string::npos || dotp > slashp)) {
        ext = filename.substr(dotp + 1);
        filename = filename.substr(0, dotp);
    }

    NSString *rext = [NSString stringWithUTF8String:ext.c_str()];
    NSString *path = findBundleResource(filename, rext);
    if (!path) return BinaryBlob();

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return BinaryBlob();

    unsigned int numBytes = (unsigned int)[data length];
    unsigned char* bytes = new unsigned char[numBytes];
    memcpy(bytes, [data bytes], numBytes);
    return BinaryBlob(bytes, numBytes);
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------
std::string AppPlatform_macOS::getDateString(int s)
{
    // The engine's Font.cpp is a 256-slot bitmap that indexes its glyph
    // sheet by raw byte value, so anything outside 7-bit ASCII renders as
    // a sequence of garbage tiles (Cyrillic locales were producing the
    // “strange symbol” the user reported on the world-list screen).
    // Pin a fixed POSIX locale and ASCII-only format so the date looks
    // the same regardless of system locale.
    NSDate* date = [NSDate dateWithTimeIntervalSince1970:s];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [df setDateFormat:@"yyyy-MM-dd HH:mm"];
    NSString *ts = [df stringFromDate:date];
    std::string out([ts UTF8String]);
    [df release];
    return out;
}

// ---------------------------------------------------------------------------
// Screen geometry
// ---------------------------------------------------------------------------
int AppPlatform_macOS::getScreenWidth()
{
    if (_screenW > 0) return _screenW;
    // Sensible default that matches the Win32 port (854x480) before the
    // GL view tells us its real size via setScreenSize().
    return 854;
}
int AppPlatform_macOS::getScreenHeight()
{
    if (_screenH > 0) return _screenH;
    return 480;
}

float AppPlatform_macOS::getPixelsPerMillimeter()
{
    // Best-effort: ask the main screen for its resolution and physical size.
    NSScreen* screen = [NSScreen mainScreen];
    if (!screen) return 6.4f;

    NSDictionary* desc = [screen deviceDescription];
    NSSize sizeInPixels = [[desc valueForKey:NSDeviceSize] sizeValue];

    CGDirectDisplayID disp = (CGDirectDisplayID)[[desc valueForKey:@"NSScreenNumber"] unsignedIntValue];
    CGSize sizeInMM = CGDisplayScreenSize(disp);

    if (sizeInMM.width <= 0 || sizeInPixels.width <= 0) {
        // 24" @ 1920x1200 fallback (same heuristic as Win32 target).
        const float pixels = sqrtf(1920.0f*1920.0f + 1200.0f*1200.0f);
        const float mm     = 24.0f * 25.4f;
        return pixels / mm;
    }
    return (float)(sizeInPixels.width / sizeInMM.width);
}

// ---------------------------------------------------------------------------
// GPU info
// ---------------------------------------------------------------------------
bool AppPlatform_macOS::isPowerVR()
{
    const char* s = (const char*)glGetString(GL_RENDERER);
    if (!s) return false;
    return (strstr(s, "SGX") != NULL) || (strstr(s, "PowerVR") != NULL);
}

bool AppPlatform_macOS::isSuperFast()
{
    // Treat any desktop GPU as "fast" so engine pulls in the higher-detail
    // code paths (matches what HD iOS hardware would do).
    return true;
}

// ---------------------------------------------------------------------------
// Soft keyboard (no-op on a desktop)
// ---------------------------------------------------------------------------
void AppPlatform_macOS::showKeyboard() { super::showKeyboard(); }
void AppPlatform_macOS::hideKeyboard() { super::hideKeyboard(); }

// ---------------------------------------------------------------------------
// Option strings: expose saved options plus NSUserDefaults overrides.
// ---------------------------------------------------------------------------
StringVector AppPlatform_macOS::getOptionStrings()
{
    StringVector options;

    std::map<std::string, std::string> optionMap = loadOptionMap();
    for (std::map<std::string, std::string>::const_iterator it = optionMap.begin();
         it != optionMap.end(); ++it) {
        options.push_back(it->first);
        options.push_back(it->second);
    }
    return options;
}

std::map<std::string, std::string> AppPlatform_macOS::loadOptionMap()
{
    std::map<std::string, std::string> optionMap;
    std::string storagePath = _storagePath.empty() ? std::string(".") : _storagePath;
    NSString* path = [NSString stringWithFormat:@"%s/options.txt", storagePath.c_str()];
    NSString* contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    if (contents) {
        NSArray* lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString* line in lines) {
            NSRange sep = [line rangeOfString:@":"];
            if (sep.location != NSNotFound && sep.location + 1 < [line length]) {
                NSString* key = [line substringToIndex:sep.location];
                NSString* value = [line substringFromIndex:sep.location + 1];
                optionMap[[key UTF8String]] = [value UTF8String];
            }
        }
    }

    NSDictionary* defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString* key in defaults) {
        if ([key hasPrefix:@"mp_"]
         || [key hasPrefix:@"gfx_"]
         || [key hasPrefix:@"ctrl_"]
         || [key hasPrefix:@"feedback_"]
         || [key hasPrefix:@"game_"]) {
            id value = [defaults objectForKey:key];
            optionMap[[key UTF8String]] = [[value description] UTF8String];
        }
    }
    return optionMap;
}

void AppPlatform_macOS::saveOptionStrings(const StringVector& strings)
{
    std::string storagePath = _storagePath.empty() ? std::string(".") : _storagePath;
    NSString* path = [NSString stringWithFormat:@"%s/options.txt", storagePath.c_str()];
    NSMutableString* contents = [NSMutableString string];
    for (StringVector::const_iterator it = strings.begin(); it != strings.end(); ++it) {
        [contents appendFormat:@"%s\n", it->c_str()];
    }
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// ---------------------------------------------------------------------------
// Dialogs (modal NSAlert with optional text-field accessory view)
// ---------------------------------------------------------------------------
namespace {

struct DialogSpec {
    NSString* title;
    NSString* informative;
    NSString* namePlaceholder;
    NSString* nameLabel;
    bool wantsName;
    bool wantsSeed;
    bool wantsGameMode;
};

DialogSpec dialogSpecFor(int dialogId) {
    DialogSpec s = { @"Minecraft", @"", @"Name", @"Name:", false, false, false };
    if (dialogId == DialogDefinitions::DIALOG_CREATE_NEW_WORLD) {
        s.title = @"Create new world";
        s.informative = @"Pick a name, an optional seed, and a game mode.";
        s.wantsName = true;
        s.wantsSeed = true;
        s.wantsGameMode = true;
    } else if (dialogId == DialogDefinitions::DIALOG_RENAME_MP_WORLD) {
        s.title = @"Rename world";
        s.informative = @"Enter a new name for this world.";
        s.wantsName = true;
    } else if (dialogId == DialogDefinitions::DIALOG_SET_USERNAME) {
        s.title = @"Set username";
        s.informative = @"This is the name other players see in chat.";
        s.namePlaceholder = @"Username";
        s.nameLabel = @"Username:";
        s.wantsName = true;
    } else if (dialogId == DialogDefinitions::DIALOG_MAINMENU_OPTIONS) {
        s.title = @"Options";
    } else if (dialogId == DialogDefinitions::DIALOG_DEMO_FEATURE_DISABLED) {
        s.title = @"Feature not enabled for this demo";
    }
    return s;
}

} // namespace

void AppPlatform_macOS::showDialog(int dialogId)
{
    DialogSpec spec = dialogSpecFor(dialogId);

    if (dialogId == DialogDefinitions::DIALOG_DEMO_FEATURE_DISABLED) {
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:spec.title];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        [alert release];
        _dialogResultStatus = 1;
        _dialogResultStrings.clear();
        return;
    }

    if (dialogId == DialogDefinitions::DIALOG_MAINMENU_OPTIONS) {
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Options"];
        [alert addButtonWithTitle:@"Save"];
        [alert addButtonWithTitle:@"Cancel"];

        std::map<std::string, std::string> optionMap = loadOptionMap();
        CGFloat width = 300.0;
        CGFloat rowH = 26.0;
        CGFloat pad = 8.0;
        NSView* accessory = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, rowH * 5 + pad * 4)] autorelease];

        NSTextField* usernameField = [[[NSTextField alloc] initWithFrame:NSMakeRect(120, rowH * 4 + pad * 4, 180, rowH)] autorelease];
        [[usernameField cell] setPlaceholderString:@"Username"];
        if (optionMap.find(OptionStrings::Multiplayer_Username) != optionMap.end())
            [usernameField setStringValue:[NSString stringWithUTF8String:optionMap[OptionStrings::Multiplayer_Username].c_str()]];

        NSSlider* sensitivitySlider = [[[NSSlider alloc] initWithFrame:NSMakeRect(120, rowH * 3 + pad * 3, 180, rowH)] autorelease];
        [sensitivitySlider setMinValue:0.0];
        [sensitivitySlider setMaxValue:1.0];
        [sensitivitySlider setDoubleValue:0.5];
        if (optionMap.find(OptionStrings::Controls_Sensitivity) != optionMap.end())
            [sensitivitySlider setDoubleValue:atof(optionMap[OptionStrings::Controls_Sensitivity].c_str())];

        NSButton* invertMouse = [[[NSButton alloc] initWithFrame:NSMakeRect(0, rowH * 2 + pad * 2, width, rowH)] autorelease];
        [invertMouse setButtonType:NSSwitchButton];
        [invertMouse setTitle:@"Invert mouse"];
        [invertMouse setState:(optionMap[OptionStrings::Controls_InvertMouse] == "1" || optionMap[OptionStrings::Controls_InvertMouse] == "true") ? NSOnState : NSOffState];

        NSButton* leftHanded = [[[NSButton alloc] initWithFrame:NSMakeRect(0, rowH + pad, width, rowH)] autorelease];
        [leftHanded setButtonType:NSSwitchButton];
        [leftHanded setTitle:@"Left handed"];
        [leftHanded setState:(optionMap[OptionStrings::Controls_IsLefthanded] == "1" || optionMap[OptionStrings::Controls_IsLefthanded] == "true") ? NSOnState : NSOffState];

        NSButton* fancyGraphics = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, width, rowH)] autorelease];
        [fancyGraphics setButtonType:NSSwitchButton];
        [fancyGraphics setTitle:@"Fancy graphics"];
        [fancyGraphics setState:(optionMap.find(OptionStrings::Graphics_Fancy) == optionMap.end() || optionMap[OptionStrings::Graphics_Fancy] == "1" || optionMap[OptionStrings::Graphics_Fancy] == "true") ? NSOnState : NSOffState];

        NSTextField* usernameLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, rowH * 4 + pad * 4, 110, rowH)] autorelease];
        [usernameLabel setStringValue:@"Username"];
        [usernameLabel setEditable:NO];
        [usernameLabel setBordered:NO];
        [usernameLabel setDrawsBackground:NO];
        NSTextField* sensitivityLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, rowH * 3 + pad * 3, 110, rowH)] autorelease];
        [sensitivityLabel setStringValue:@"Sensitivity"];
        [sensitivityLabel setEditable:NO];
        [sensitivityLabel setBordered:NO];
        [sensitivityLabel setDrawsBackground:NO];

        [accessory addSubview:usernameLabel];
        [accessory addSubview:usernameField];
        [accessory addSubview:sensitivityLabel];
        [accessory addSubview:sensitivitySlider];
        [accessory addSubview:invertMouse];
        [accessory addSubview:leftHanded];
        [accessory addSubview:fancyGraphics];
        [alert setAccessoryView:accessory];

        [[alert window] performSelector:@selector(makeFirstResponder:)
                             withObject:usernameField
                             afterDelay:0.0];
        NSInteger response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            optionMap[OptionStrings::Multiplayer_Username] = [[usernameField stringValue] UTF8String];
            optionMap[OptionStrings::Controls_Sensitivity] = [[[NSString stringWithFormat:@"%g", [sensitivitySlider doubleValue]] description] UTF8String];
            optionMap[OptionStrings::Controls_InvertMouse] = ([invertMouse state] == NSOnState) ? "1" : "0";
            optionMap[OptionStrings::Controls_IsLefthanded] = ([leftHanded state] == NSOnState) ? "1" : "0";
            optionMap[OptionStrings::Graphics_Fancy] = ([fancyGraphics state] == NSOnState) ? "1" : "0";
            StringVector saved;
            for (std::map<std::string, std::string>::const_iterator it = optionMap.begin();
                 it != optionMap.end(); ++it) {
                saved.push_back(it->first + ":" + it->second);
            }
            saveOptionStrings(saved);
            _dialogResultStatus = 1;
        } else {
            _dialogResultStatus = 0;
        }
        [alert release];
        _dialogResultStrings.clear();
        return;
    }

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:spec.title];
    if (spec.informative && [spec.informative length] > 0) {
        [alert setInformativeText:spec.informative];
    }
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView* accessory = nil;
    NSTextField* nameField = nil;
    NSTextField* seedField = nil;
    NSPopUpButton* gameModePopup = nil;

    // Lay out rows as <label> | <control>. Labels live in the left
    // gutter so even a single-row dialog (e.g. Set username) shows up as
    // a clearly captioned field rather than a thin unlabelled strip.
    CGFloat labelW = 90.0;
    CGFloat ctrlW  = 200.0;
    CGFloat gap    = 8.0;
    CGFloat width  = labelW + gap + ctrlW;
    CGFloat rowH   = 24.0;
    CGFloat pad    = 10.0;
    int rows = (spec.wantsName ? 1 : 0) + (spec.wantsSeed ? 1 : 0) + (spec.wantsGameMode ? 1 : 0);

    if (rows > 0) {
        CGFloat totalH = rows * rowH + (rows - 1) * pad;
        accessory = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, totalH)] autorelease];
        CGFloat y = totalH - rowH;

        if (spec.wantsName) {
            NSTextField* lbl = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, y, labelW, rowH)] autorelease];
            [lbl setStringValue:spec.nameLabel];
            [lbl setEditable:NO];
            [lbl setBordered:NO];
            [lbl setDrawsBackground:NO];
            [lbl setAlignment:NSRightTextAlignment];
            [accessory addSubview:lbl];

            nameField = [[[NSTextField alloc] initWithFrame:NSMakeRect(labelW + gap, y, ctrlW, rowH)] autorelease];
            [[nameField cell] setPlaceholderString:spec.namePlaceholder];
            // Pre-fill the username dialog with the currently-saved name
            // so the user knows what's there and can edit it in place.
            if (dialogId == DialogDefinitions::DIALOG_SET_USERNAME) {
                std::map<std::string, std::string> optionMap = loadOptionMap();
                std::map<std::string, std::string>::const_iterator cit =
                    optionMap.find(OptionStrings::Multiplayer_Username);
                if (cit != optionMap.end() && !cit->second.empty()) {
                    [nameField setStringValue:[NSString stringWithUTF8String:cit->second.c_str()]];
                }
            }
            [accessory addSubview:nameField];
            y -= (rowH + pad);
        }
        if (spec.wantsSeed) {
            NSTextField* lbl = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, y, labelW, rowH)] autorelease];
            [lbl setStringValue:@"Seed:"];
            [lbl setEditable:NO];
            [lbl setBordered:NO];
            [lbl setDrawsBackground:NO];
            [lbl setAlignment:NSRightTextAlignment];
            [accessory addSubview:lbl];

            seedField = [[[NSTextField alloc] initWithFrame:NSMakeRect(labelW + gap, y, ctrlW, rowH)] autorelease];
            [[seedField cell] setPlaceholderString:@"Seed (optional)"];
            [accessory addSubview:seedField];
            y -= (rowH + pad);
        }
        if (spec.wantsGameMode) {
            NSTextField* lbl = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, y, labelW, rowH)] autorelease];
            [lbl setStringValue:@"Game mode:"];
            [lbl setEditable:NO];
            [lbl setBordered:NO];
            [lbl setDrawsBackground:NO];
            [lbl setAlignment:NSRightTextAlignment];
            [accessory addSubview:lbl];

            gameModePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(labelW + gap, y, ctrlW, rowH) pullsDown:NO] autorelease];
            [gameModePopup addItemWithTitle:@"Creative"];
            [gameModePopup addItemWithTitle:@"Survival"];
            [accessory addSubview:gameModePopup];
        }
        [alert setAccessoryView:accessory];
    }

    // Push focus into the first text field once the modal sheet is laid out.
    if (nameField) {
        [[alert window] performSelector:@selector(makeFirstResponder:)
                             withObject:nameField
                             afterDelay:0.0];
    } else if (seedField) {
        [[alert window] performSelector:@selector(makeFirstResponder:)
                             withObject:seedField
                             afterDelay:0.0];
    }

    NSInteger response = [alert runModal];
    bool ok = (response == NSAlertFirstButtonReturn);

    _dialogResultStrings.clear();
    if (ok) {
        if (nameField) {
            std::string name([[nameField stringValue] UTF8String]);
            _dialogResultStrings.push_back(name);
        }
        if (seedField) {
            std::string seed([[seedField stringValue] UTF8String]);
            _dialogResultStrings.push_back(seed);
        }
        if (gameModePopup) {
            std::string mode = ([gameModePopup indexOfSelectedItem] == 1) ? "survival" : "creative";
            _dialogResultStrings.push_back(mode);
        }
        _dialogResultStatus = 1;
    } else {
        _dialogResultStatus = 0;
    }

    [alert release];
}

int AppPlatform_macOS::getUserInputStatus()
{
    return _dialogResultStatus;
}

StringVector AppPlatform_macOS::getUserInput()
{
    return _dialogResultStrings;
}
