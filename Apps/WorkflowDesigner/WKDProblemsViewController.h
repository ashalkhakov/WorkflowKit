#import <AppKit/AppKit.h>
#import "WKDProcessEditor.h"

/*
 * What the engine finds wrong with the process, from WKDProblems.xib: a
 * list of the process editor's problems, in the file's order, kept to them
 * as they are checked again; one chosen selects its element. In UDCode,
 * what the Issues navigator shows.
 */
#if defined(__APPLE__)
@interface WKDProblemsViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
#else
@interface WKDProblemsViewController : NSViewController
#endif

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor;
@property (nonatomic, readonly, strong) WKDProcessEditor *processEditor;

@property (nonatomic, strong) IBOutlet NSTableView *tableView;

@end
