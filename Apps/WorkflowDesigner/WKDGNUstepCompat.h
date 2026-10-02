/*
 * Included on GNUstep only (GNUmakefile.preamble), never by Xcode: AppKit
 * names a gnustep-gui lacks, defined by the ones it has, so the sources can
 * use current AppKit. Only names; behaviour belongs in gnustep-gui.
 */
#ifdef __OBJC__
#import <AppKit/AppKit.h>

#define NSCompositingOperationSourceOver NSCompositeSourceOver
#define NSButtonTypeSwitch NSSwitchButton
#define NSBitmapImageFileTypePNG NSPNGFileType
#define NSBezelStyleSmallSquare NSSmallSquareBezelStyle
#endif
