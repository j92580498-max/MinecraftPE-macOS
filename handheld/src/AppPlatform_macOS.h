#ifndef APPPLATFORM_MACOS_H__
#define APPPLATFORM_MACOS_H__

// Native macOS (10.9 Mavericks and later) AppPlatform implementation.
//
// The iOS port (AppPlatform_iOS) is tied to UIKit / UIViewController and
// CAEAGLLayer. On macOS we use AppKit (NSWindow / NSOpenGLView) and a desktop
// OpenGL 2.1 legacy context. To keep this header importable from both
// Objective-C++ (in osxproj) and plain C++ (in NinecraftApp.cpp etc.) we
// forward-declare the Objective-C view type without dragging Cocoa headers
// into the engine sources.

#include "AppPlatform.h"
#include "client/renderer/gles.h"
#include "platform/log.h"
#include <cmath>
#include <fstream>
#include <sstream>

#ifdef __OBJC__
@class MinecraftMacGLView;
typedef MinecraftMacGLView* MinecraftMacGLViewRef;
#else
typedef void* MinecraftMacGLViewRef;
#endif

class AppPlatform_macOS: public AppPlatform
{
	typedef AppPlatform super;
public:
    AppPlatform_macOS(MinecraftMacGLViewRef view) {
        _view = view;
        srand((unsigned int)time(0));
    }

    void setBasePath(const std::string& bp) { _basePath = bp; }
    void setStoragePath(const std::string& sp) { _storagePath = sp; }
    const std::string& getStoragePath() const { return _storagePath; }

    // Texture / asset loading
    virtual TextureData loadTexture(const std::string& filename_, bool textureFolder);
    virtual BinaryBlob  readAssetFile(const std::string& filename);

    // Dialogs (NSAlert based)
    virtual void showDialog(int dialogId);
    virtual int  getUserInputStatus();
    virtual StringVector getUserInput();

    // Misc helpers
    virtual std::string getDateString(int s);

    virtual void saveScreenshot(const std::string& filename, int glWidth, int glHeight) { /* @todo */ }

    virtual int checkLicense() { return 0; }
    virtual bool hasBuyButtonWhenInvalidLicense() { return false; }

    virtual void buyGame() { /* desktop: no-op */ }

    // Window / screen geometry
    virtual int   getScreenWidth();
    virtual int   getScreenHeight();
    virtual float getPixelsPerMillimeter();
    void          setScreenSize(int w, int h) { _screenW = w; _screenH = h; }

    // Input model: desktop is mouse+keyboard, not touch.
    virtual bool supportsTouchscreen() { return false; }
    virtual void vibrate(int) {}

    virtual bool isNetworkEnabled(bool) { return true; }

    virtual StringVector getOptionStrings();

    // OpenGL / GPU info
    virtual bool isPowerVR();
    virtual bool isSuperFast();

    // Soft keyboard: always available on a desktop, so these are no-ops that
    // still flip the keyboardVisible flag for engine consistency.
    virtual void showKeyboard();
    virtual void hideKeyboard();

    // Called from the GL view when a dialog finishes.
    void setUserInputResult(int status, const StringVector& strings) {
        _dialogResultStatus  = status;
        _dialogResultStrings = strings;
    }

private:
    std::string _basePath;
    std::string _storagePath;
    int _screenW;
    int _screenH;
    int _dialogResultStatus;
    StringVector _dialogResultStrings;
    MinecraftMacGLViewRef _view;
};

#endif /*APPPLATFORM_MACOS_H__*/
