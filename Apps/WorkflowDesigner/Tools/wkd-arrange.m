/*
 * wkd-arrange -- Diagram > Arrange without a window: each BPMN file laid
 * out afresh, left to right, its diagram written into it.
 *
 *   wkd-arrange file.bpmn...
 *
 * Only the diagram changes; what the engine reads is as it was.
 */
#import <Foundation/Foundation.h>
#import "WKDEditor.h"

int
main(int argc, const char *argv[])
{
	@autoreleasepool {
		if (argc < 2) {
			fprintf(stderr, "usage: wkd-arrange file.bpmn...\n");
			return 2;
		}
		int status = 0;
		for (int i = 1; i < argc; i++) {
			NSString *path = [NSString stringWithUTF8String:argv[i]];
			NSError *error = nil;
			NSData *data = [NSData dataWithContentsOfFile:path];
			NSXMLDocument *document = data != nil ? [[NSXMLDocument alloc] initWithData:data options:0 error:&error] : nil;
			WKDEditor *editor = document != nil ? [[WKDEditor alloc] initWithDocument:document undoManager:nil] : nil;
			if (editor.diagram.process == nil) {
				fprintf(stderr, "wkd-arrange: %s is not a BPMN process%s%s\n", argv[i],
				        error != nil ? ": " : "", error != nil ? [[error localizedDescription] UTF8String] : "");
				status = 1;
				continue;
			}
			[editor arrange];
			if (![[editor.document XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement] writeToFile:path atomically:YES]) {
				fprintf(stderr, "wkd-arrange: cannot write %s\n", argv[i]);
				status = 1;
			}
		}
		return status;
	}
}
