# ============================================================================
#  Minecraft PE 0.6.1 — native macOS (10.9 Mavericks) Makefile
# ----------------------------------------------------------------------------
#  Builds a self-contained `Minecraft PE.app` bundle from:
#    * the cross-platform C++ engine under handheld/src/
#    * the macOS AppPlatform (AppPlatform_macOS.{h,mm})
#    * the Cocoa entry point under handheld/project/osxproj/MinecraftMacApp/
#
#  Run from this directory:
#      make            # debug build, produces build/Minecraft\ PE.app
#      make BUILD=release
#      make clean
#      make run        # build + launch the .app
#
#  Target: OS X 10.9 (Mavericks), x86_64 only, legacy OpenGL 2.1 profile.
# ============================================================================

# NOTE: the on-disk bundle name has no space in it (so make / shell rules
# don't have to quote $(APPBUNDLE) everywhere). The user-visible name still
# comes from Info.plist's CFBundleDisplayName="Minecraft PE".
APPNAME   := MinecraftPE
EXECNAME  := MinecraftPE
BUILDDIR  := build
APPBUNDLE := $(BUILDDIR)/$(APPNAME).app
EXECPATH  := $(APPBUNDLE)/Contents/MacOS/$(EXECNAME)

MIN_OSX := 10.9
ARCH    := x86_64

ROOT    := ../..
SRCROOT := $(ROOT)/src
OSXPROJ := MinecraftMacApp
DATAROOT:= $(ROOT)/data

# ---- Toolchain -------------------------------------------------------------
CXX    := clang++
OBJCXX := clang++

WARN  := -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
         -Wno-overloaded-virtual -Wno-writable-strings \
         -Wno-c++11-extensions -Wno-deprecated-register

COMMON_FLAGS := -arch $(ARCH) -mmacosx-version-min=$(MIN_OSX) \
                -I$(SRCROOT) -I$(SRCROOT)/raknet $(WARN)

ifeq ($(BUILD),release)
    OPT    := -O2 -DNDEBUG
    OBJDIR := obj/release
else
    OPT    := -O0 -g
    OBJDIR := obj/debug
endif

CXXFLAGS    := $(COMMON_FLAGS) $(OPT) -std=c++98 -fno-rtti $(EXTRA_CXXFLAGS)
OBJCXXFLAGS := $(COMMON_FLAGS) $(OPT) -std=c++98 -fno-rtti -fno-objc-arc $(EXTRA_CXXFLAGS)

FRAMEWORKS := -framework Cocoa -framework OpenGL -framework OpenAL \
              -framework Foundation -framework AppKit \
              -framework CoreGraphics -framework AudioToolbox \
              -framework CoreFoundation -framework Carbon

LDFLAGS := -arch $(ARCH) -mmacosx-version-min=$(MIN_OSX) -lz $(FRAMEWORKS) $(EXTRA_LDFLAGS)

# ---- Sources ---------------------------------------------------------------
# Recursively pick up everything under handheld/src/ except the entry points
# and AppPlatforms that target other operating systems.
ENGINE_CPP := $(shell find $(SRCROOT) -name '*.cpp' \
                ! -name 'main.cpp' \
                ! -name 'main_*.cpp' \
                ! -name 'AppPlatform_win32.cpp' \
                ! -name 'AppPlatform_android*.cpp' \
                ! -name 'SoundSystemSL.cpp' \
                ! -name 'SoundEngine.cpp')

# For SoundEngine and MoveFolder we use the .mm versions (same as iOS) — they
# contain the OpenAL / NSFileManager integration that the desktop GL build
# needs. The .cpp twin of SoundEngine is excluded from ENGINE_CPP above.
ENGINE_MM  := $(SRCROOT)/AppPlatform_macOS.mm \
              $(SRCROOT)/client/sound/SoundEngine.mm \
              $(SRCROOT)/world/level/storage/MoveFolder.mm

OSXPROJ_MM := \
    $(OSXPROJ)/main.mm \
    $(OSXPROJ)/MinecraftMacAppDelegate.mm \
    $(OSXPROJ)/MinecraftMacGLView.mm

# Object file layout:
#   handheld/src/foo/bar.cpp     -> obj/.../src/foo/bar.cpp.o
#   handheld/src/AppPlatform_macOS.mm -> obj/.../src/AppPlatform_macOS.mm.o
#   MinecraftMacApp/X.mm         -> obj/.../osxproj/MinecraftMacApp/X.mm.o
ENGINE_CPP_OBJS := $(patsubst $(ROOT)/%,$(OBJDIR)/%.o,$(ENGINE_CPP))
ENGINE_MM_OBJS  := $(patsubst $(ROOT)/%,$(OBJDIR)/%.o,$(ENGINE_MM))
OSXPROJ_OBJS    := $(patsubst %,$(OBJDIR)/osxproj/%.o,$(OSXPROJ_MM))

OBJS := $(ENGINE_CPP_OBJS) $(ENGINE_MM_OBJS) $(OSXPROJ_OBJS)
DEPS := $(OBJS:.o=.d)

# ---- Targets ---------------------------------------------------------------
.PHONY: all clean run print-sources

all: $(EXECPATH)

print-sources:
	@echo "Engine cpp sources ($(words $(ENGINE_CPP))):"
	@for s in $(ENGINE_CPP); do echo "  $$s"; done
	@echo "Engine objc++ sources ($(words $(ENGINE_MM))):"
	@for s in $(ENGINE_MM); do echo "  $$s"; done
	@echo "Cocoa entry sources ($(words $(OSXPROJ_MM))):"
	@for s in $(OSXPROJ_MM); do echo "  $$s"; done

# ---- Compile rules ---------------------------------------------------------
$(OBJDIR)/src/%.cpp.o: $(SRCROOT)/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -MMD -MP -c $< -o $@

$(OBJDIR)/src/%.mm.o: $(SRCROOT)/%.mm
	@mkdir -p $(dir $@)
	$(OBJCXX) $(OBJCXXFLAGS) -MMD -MP -c $< -o $@

$(OBJDIR)/osxproj/$(OSXPROJ)/%.mm.o: $(OSXPROJ)/%.mm
	@mkdir -p $(dir $@)
	$(OBJCXX) $(OBJCXXFLAGS) -MMD -MP -c $< -o $@

# ---- Link + bundle ---------------------------------------------------------
$(EXECPATH): $(OBJS) $(OSXPROJ)/Info.plist
	@mkdir -p $(APPBUNDLE)/Contents/MacOS
	@mkdir -p $(APPBUNDLE)/Contents/Resources
	@cp $(OSXPROJ)/Info.plist $(APPBUNDLE)/Contents/Info.plist
	@printf 'APPL????' > $(APPBUNDLE)/Contents/PkgInfo
	$(CXX) $(OBJS) $(LDFLAGS) -o $@
	@# Stage game data next to the binary so the engine can find textures
	@# / sounds via the app-bundle resource lookup paths.
	@if [ -d $(DATAROOT) ]; then \
	    echo "Copying data/ into Resources/"; \
	    cp -R $(DATAROOT)/* $(APPBUNDLE)/Contents/Resources/ 2>/dev/null || true; \
	fi
	@echo ""
	@echo "Built $(APPBUNDLE)"

run: $(EXECPATH)
	open "$(APPBUNDLE)"

clean:
	rm -rf $(OBJDIR) $(BUILDDIR)

-include $(DEPS)
