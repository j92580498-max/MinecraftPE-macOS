#include "AppPlatform_macOS.h"

#import <Cocoa/Cocoa.h>
#import <AppKit/AppKit.h>

#include "client/gui/screens/DialogDefinitions.h"

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

static NSString* findBundleResource(const std::string& filename, NSString* ext) {
    NSString *p = [[NSString alloc] initWithUTF8String:filename.c_str()];
    NSString *path = [[NSBundle mainBundle] pathForResource:p ofType:ext];
    [p release];
    if (path) return path;

    // Development fallback: look beside the .app in handheld/data/images
    // (matches the layout used by the Win32 target).
    NSString *bundleParent = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    NSArray *candidates = [NSArray arrayWithObjects:
        [NSString stringWithFormat:@"%@/%s.%@", bundleParent, filename.c_str(), ext],
        [NSString stringWithFormat:@"%@/data/images/%s.%@", bundleParent, filename.c_str(), ext],
        [NSString stringWithFormat:@"%@/data/%s.%@", bundleParent, filename.c_str(), ext],
        [NSString stringWithFormat:@"%@/../data/images/%s.%@", bundleParent, filename.c_str(), ext],
        [NSString stringWithFormat:@"%@/../data/%s.%@", bundleParent, filename.c_str(), ext],
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

    // Strip extension and directory like the iOS port does.
    std::string filename = filename_;
    size_t dotp = filename.rfind(".");
    size_t slashp = filename.rfind("/");
    if (dotp != std::string::npos || slashp != std::string::npos) {
        if (slashp == std::string::npos) slashp = (size_t)-1;
        filename = filename.substr(slashp+1, dotp-(slashp+1));
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
    std::string filename = filename_;
    size_t dotp = filename.rfind(".");
    size_t slashp = filename.rfind("/");
    std::string ext;
    if (dotp != std::string::npos || slashp != std::string::npos) {
        if (dotp != std::string::npos) ext = filename.substr(dotp+1);
        if (slashp == std::string::npos) slashp = (size_t)-1;
        filename = filename.substr(slashp+1, dotp-(slashp+1));
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
    NSDate* date = [NSDate dateWithTimeIntervalSince1970:s];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateStyle:NSDateFormatterMediumStyle];
    [df setTimeStyle:NSDateFormatterShortStyle];
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
// Option strings: mirror iOS by exposing NSUserDefaults entries that look
// like Minecraft option keys.
// ---------------------------------------------------------------------------
StringVector AppPlatform_macOS::getOptionStrings()
{
    StringVector options;
    NSDictionary* d = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *key in d) {
        if ([key hasPrefix:@"mp_"]
         || [key hasPrefix:@"gfx_"]
         || [key hasPrefix:@"ctrl_"]
         || [key hasPrefix:@"feedback_"]
         || [key hasPrefix:@"game_"]) {
            id value = [d objectForKey:key];
            options.push_back([key UTF8String]);
            options.push_back([[value description] UTF8String]);
        }
    }
    return options;
}

// ---------------------------------------------------------------------------
// Dialogs (modal NSAlert with optional text-field accessory view)
// ---------------------------------------------------------------------------
namespace {

struct DialogSpec {
    NSString* title;
    bool wantsName;
    bool wantsSeed;
};

DialogSpec dialogSpecFor(int dialogId) {
    DialogSpec s = { @"Minecraft", false, false };
    if (dialogId == DialogDefinitions::DIALOG_CREATE_NEW_WORLD) {
        s.title = @"Create new world";
        s.wantsName = true;
        s.wantsSeed = true;
    } else if (dialogId == DialogDefinitions::DIALOG_RENAME_MP_WORLD) {
        s.title = @"Rename world";
        s.wantsName = true;
    } else if (dialogId == DialogDefinitions::DIALOG_SET_USERNAME) {
        s.title = @"Set username";
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
        // The iOS port shows InAppSettingsKit here; on macOS we surface a
        // pointer to NSUserDefaults. A richer NSWindow-based settings panel
        // can be wired up later without touching the engine.
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Options"];
        [alert setInformativeText:@"Settings are stored in NSUserDefaults. "
                                    "Use `defaults write com.mojang.MinecraftPE <key> <value>` "
                                    "for now."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        [alert release];
        _dialogResultStatus = 1;
        _dialogResultStrings.clear();
        return;
    }

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:spec.title];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView* accessory = nil;
    NSTextField* nameField = nil;
    NSTextField* seedField = nil;

    CGFloat width = 260.0;
    CGFloat rowH  = 24.0;
    CGFloat pad   = 8.0;
    int rows = (spec.wantsName ? 1 : 0) + (spec.wantsSeed ? 1 : 0);

    if (rows > 0) {
        accessory = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, rows * (rowH + pad))] autorelease];
        CGFloat y = (rows - 1) * (rowH + pad);

        if (spec.wantsName) {
            nameField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, y, width, rowH)] autorelease];
            [[nameField cell] setPlaceholderString:@"Name"];
            [accessory addSubview:nameField];
            y -= (rowH + pad);
        }
        if (spec.wantsSeed) {
            seedField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, y, width, rowH)] autorelease];
            [[seedField cell] setPlaceholderString:@"Seed (optional)"];
            [accessory addSubview:seedField];
        }
        [alert setAccessoryView:accessory];
    }

    NSModalResponse response = [alert runModal];
    bool ok = (response == NSAlertFirstButtonReturn);

    _dialogResultStrings.clear();
    if (ok) {
        if (nameField) {
            std::string name([[nameField stringValue] UTF8String]);
            _dialogResultStrings.push_back("name");
            _dialogResultStrings.push_back(name);
        }
        if (seedField) {
            std::string seed([[seedField stringValue] UTF8String]);
            _dialogResultStrings.push_back("seed");
            _dialogResultStrings.push_back(seed);
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
