#import <XCTest/XCTest.h>
#import "WKDEditor.h"
#import "WKDDecisions.h"
#import "WKDXML.h"

/* How long editing a large process takes: run with WKD_TIMING set (to the
 * number of tasks, else 1000); each operation's time is logged. */
@interface WKDTimingTests : XCTestCase
@end

@implementation WKDTimingTests

static NSString *
WKDLargeProcess(NSUInteger tasks)
{
	NSMutableString *process = [NSMutableString string], *shapes = [NSMutableString string];
	NSMutableString *upper = [NSMutableString string], *lower = [NSMutableString string];
	NSUInteger rows = (tasks + 19) / 20, upperRows = MAX(rows / 2, (NSUInteger)1);
	for (NSUInteger i = 0; i < tasks; i++) {
		NSString *incoming = i == 0 ? @"" : [NSString stringWithFormat:@"<bpmn:incoming>f%lu</bpmn:incoming>", (unsigned long)i - 1];
		NSString *outgoing = i + 1 == tasks ? @"" : [NSString stringWithFormat:@"<bpmn:outgoing>f%lu</bpmn:outgoing>", (unsigned long)i];
		[process appendFormat:@"<bpmn:userTask id=\"t%lu\" name=\"Task %lu\">%@%@</bpmn:userTask>",
			(unsigned long)i, (unsigned long)i, incoming, outgoing];
		if (i + 1 < tasks) {
			[process appendFormat:@"<bpmn:sequenceFlow id=\"f%lu\" sourceRef=\"t%lu\" targetRef=\"t%lu\"/>",
				(unsigned long)i, (unsigned long)i, (unsigned long)i + 1];
		}
		/* Rows of twenty, the first half in the upper lane. */
		BOOL top = i / 20 < upperRows;
		double x = 200 + (i % 20) * 150, y = 60 + (i / 20) * 200;
		[top ? upper : lower appendFormat:@"<bpmn:flowNodeRef>t%lu</bpmn:flowNodeRef>", (unsigned long)i];
		[shapes appendFormat:@"<bpmndi:BPMNShape id=\"t%lu_di\" bpmnElement=\"t%lu\"><dc:Bounds x=\"%.0f\" y=\"%.0f\" width=\"100\" height=\"80\"/></bpmndi:BPMNShape>",
			(unsigned long)i, (unsigned long)i, x, y];
		if (i + 1 < tasks) {
			[shapes appendFormat:@"<bpmndi:BPMNEdge id=\"f%lu_di\" bpmnElement=\"f%lu\"><di:waypoint x=\"%.0f\" y=\"%.0f\"/><di:waypoint x=\"%.0f\" y=\"%.0f\"/></bpmndi:BPMNEdge>",
				(unsigned long)i, (unsigned long)i, x + 100, y + 40, x + 150, y + 40];
		}
	}
	double split = upperRows * 200.0, height = MAX(rows, upperRows + 1) * 200.0;
	return [NSString stringWithFormat:
		@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		@"xmlns:bpmndi=\"http://www.omg.org/spec/BPMN/20100524/DI\" xmlns:dc=\"http://www.omg.org/spec/DD/20100524/DC\" "
		@"xmlns:di=\"http://www.omg.org/spec/DD/20100524/DI\" id=\"defs\" targetNamespace=\"urn:timing\">"
		@"<bpmn:collaboration id=\"c\"><bpmn:participant id=\"pool\" name=\"Pool\" processRef=\"p\"/></bpmn:collaboration>"
		@"<bpmn:process id=\"p\" isExecutable=\"true\"><bpmn:laneSet id=\"ls\">"
		@"<bpmn:lane id=\"upper\" name=\"Upper\">%@</bpmn:lane><bpmn:lane id=\"lower\" name=\"Lower\">%@</bpmn:lane>"
		@"</bpmn:laneSet>%@</bpmn:process>"
		@"<bpmndi:BPMNDiagram id=\"d\"><bpmndi:BPMNPlane id=\"pl\" bpmnElement=\"c\">"
		@"<bpmndi:BPMNShape id=\"pool_di\" bpmnElement=\"pool\" isHorizontal=\"true\"><dc:Bounds x=\"100\" y=\"0\" width=\"3200\" height=\"%.0f\"/></bpmndi:BPMNShape>"
		@"<bpmndi:BPMNShape id=\"upper_di\" bpmnElement=\"upper\" isHorizontal=\"true\"><dc:Bounds x=\"130\" y=\"0\" width=\"3170\" height=\"%.0f\"/></bpmndi:BPMNShape>"
		@"<bpmndi:BPMNShape id=\"lower_di\" bpmnElement=\"lower\" isHorizontal=\"true\"><dc:Bounds x=\"130\" y=\"%.0f\" width=\"3170\" height=\"%.0f\"/></bpmndi:BPMNShape>"
		@"%@</bpmndi:BPMNPlane></bpmndi:BPMNDiagram></bpmn:definitions>",
		upper, lower, process, height, split, split, height - split, shapes];
}

/* Milliseconds per run of the block, over count runs. */
static double
WKDTime(NSUInteger count, void (^block)(NSUInteger i))
{
	NSDate *start = [NSDate date];
	for (NSUInteger i = 0; i < count; i++) {
		block(i);
	}
	return -[start timeIntervalSinceNow] * 1000.0 / count;
}

- (void)testEditingALargeProcess
{
	NSString *setting = [[[NSProcessInfo processInfo] environment] objectForKey:@"WKD_TIMING"];
	if (setting == nil) {
		return;
	}
	NSUInteger tasks = [setting integerValue] > 0 ? (NSUInteger)[setting integerValue] : 1000;
	NSString *xml = WKDLargeProcess(tasks);
	/* Timed as used: the agreement check reads the whole document. */
	BOOL checks = WKDEditor.checksAgreement;
	WKDEditor.checksAgreement = NO;
	NSUndoManager *undo = [[NSUndoManager alloc] init];
	[undo setGroupsByEvent:NO];
	__block WKDEditor *editor = nil;
	double open = WKDTime(1, ^(NSUInteger i) {
		NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
		editor = [[WKDEditor alloc] initWithDocument:document undoManager:undo];
	});
	XCTAssertNotNil(editor);
	NSString *middle = [NSString stringWithFormat:@"t%lu", (unsigned long)tasks / 2];
	void (^step)(void (^)(void)) = ^(void (^operation)(void)) {
		[undo beginUndoGrouping];
		operation();
		[undo endUndoGrouping];
	};
	double move = WKDTime(20, ^(NSUInteger i) {
		step(^{ [editor moveElements:@[ middle ] by:NSMakeSize(10, 0)]; });
	});
	double undoMove = WKDTime(20, ^(NSUInteger i) { [undo undo]; });
	double name = WKDTime(20, ^(NSUInteger i) {
		step(^{ [editor setName:[NSString stringWithFormat:@"Named %lu", (unsigned long)i] of:middle]; });
	});
	double inspector = WKDTime(20, ^(NSUInteger i) {
		step(^{
			[editor edit:middle action:@"Edit" with:^(NSXMLElement *element, NSXMLDocument *document) {
				WKDSetAttribute(element, @"name", [NSString stringWithFormat:@"Edited %lu", (unsigned long)i]);
			}];
		});
	});
	double rename = WKDTime(10, ^(NSUInteger i) {
		NSString *from = i == 0 ? middle : [NSString stringWithFormat:@"renamed%lu", (unsigned long)i - 1];
		step(^{ [editor renameElement:from to:[NSString stringWithFormat:@"renamed%lu", (unsigned long)i] error:NULL]; });
	});
	double undoRename = WKDTime(10, ^(NSUInteger i) { [undo undo]; });
	double insert = WKDTime(10, ^(NSUInteger i) {
		step(^{ [editor insertNodeOfType:@"task" eventDefinition:nil at:NSMakePoint(400 + i * 150, 120) error:NULL]; });
	});
	NSLog(@"WKDTiming %lu tasks: open %.1f ms; per operation: move %.2f, undo move %.2f, name %.2f, "
	      @"inspector %.2f, rename %.2f, undo rename %.2f, insert %.2f ms",
	      (unsigned long)tasks, open, move, undoMove, name, inspector, rename, undoRename, insert);
	WKDEditor.checksAgreement = checks;
}


static NSString *
WKDLargeTable(NSUInteger rules)
{
	NSMutableString *rows = [NSMutableString string];
	for (NSUInteger i = 0; i < rules; i++) {
		[rows appendFormat:@"<rule id=\"r%lu\"><inputEntry id=\"a%lu\"><text>&lt; %lu</text></inputEntry>"
			@"<inputEntry id=\"b%lu\"><text>-</text></inputEntry><inputEntry id=\"c%lu\"><text>\"x\"</text></inputEntry>"
			@"<outputEntry id=\"d%lu\"><text>%lu</text></outputEntry></rule>",
			(unsigned long)i, (unsigned long)i, (unsigned long)i, (unsigned long)i, (unsigned long)i, (unsigned long)i,
			(unsigned long)i];
	}
	return [NSString stringWithFormat:
		@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
		@"<definitions xmlns=\"https://www.omg.org/spec/DMN/20191111/MODEL/\" id=\"defs\" name=\"D\" namespace=\"urn:t\">"
		@"<decision id=\"big\" name=\"Big\"><decisionTable id=\"t\">"
		@"<input id=\"i1\"><inputExpression id=\"e1\" typeRef=\"integer\"><text>a</text></inputExpression></input>"
		@"<input id=\"i2\"><inputExpression id=\"e2\" typeRef=\"string\"><text>b</text></inputExpression></input>"
		@"<input id=\"i3\"><inputExpression id=\"e3\" typeRef=\"string\"><text>c</text></inputExpression></input>"
		@"<output id=\"o1\" name=\"n\" typeRef=\"integer\"/>%@</decisionTable></decision></definitions>", rows];
}

- (void)testEditingALargeTable
{
	NSString *setting = [[[NSProcessInfo processInfo] environment] objectForKey:@"WKD_TIMING"];
	if (setting == nil) {
		return;
	}
	NSUInteger rules = [setting integerValue] > 0 ? (NSUInteger)[setting integerValue] : 1000;
	NSString *xml = WKDLargeTable(rules);
	BOOL checks = WKDDmnEditor.checksAgreement;
	WKDDmnEditor.checksAgreement = NO;
	NSUndoManager *undo = [[NSUndoManager alloc] init];
	[undo setGroupsByEvent:NO];
	__block WKDDmnEditor *editor = nil;
	double open = WKDTime(1, ^(NSUInteger i) {
		NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
		editor = [[WKDDmnEditor alloc] initWithDocument:document undoManager:undo];
	});
	XCTAssertEqual([[editor decisionWithId:@"big"].rules count], rules);
	void (^step)(void (^)(void)) = ^(void (^operation)(void)) {
		[undo beginUndoGrouping];
		operation();
		[undo endUndoGrouping];
	};
	NSUInteger middle = rules / 2;
	double entry = WKDTime(20, ^(NSUInteger i) {
		step(^{ [editor setEntry:[NSString stringWithFormat:@"> %lu", (unsigned long)i] rule:middle column:0 of:@"big"]; });
	});
	double undoEntry = WKDTime(20, ^(NSUInteger i) { [undo undo]; });
	double insert = WKDTime(10, ^(NSUInteger i) {
		step(^{ [editor insertRuleAt:middle of:@"big"]; });
	});
	double move = WKDTime(10, ^(NSUInteger i) {
		step(^{ [editor moveRule:middle to:0 of:@"big"]; });
	});
	NSLog(@"WKDTiming %lu rules: open %.1f ms; per operation: entry %.2f, undo entry %.2f, insert rule %.2f, "
	      @"move rule %.2f ms", (unsigned long)rules, open, entry, undoEntry, insert, move);
	WKDDmnEditor.checksAgreement = checks;
}

@end
