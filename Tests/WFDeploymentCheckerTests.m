#import <XCTest/XCTest.h>
#import "WorkflowKit.h"

/* What the checker finds in resources, as deploying them would: all of
 * it, each problem with its element and its place in the file. */
@interface WFDeploymentCheckerTests : XCTestCase
@end

@implementation WFDeploymentCheckerTests

static NSData *
WFBytes(NSString *text)
{
	return [text dataUsingEncoding:NSUTF8StringEncoding];
}

static NSString *
WFProcess(NSString *body)
{
	return [NSString stringWithFormat:
		@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		@"<definitions xmlns=\"http://www.omg.org/spec/BPMN/20100524/MODEL\"\n"
		@"    xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" id=\"d\">\n"
		@"  <process id=\"order\" isExecutable=\"true\">\n%@  </process>\n</definitions>\n", body];
}

static NSArray *
WFIds(NSArray<WFProblem *> *problems)
{
	NSMutableArray *ids = [NSMutableArray array];
	for (WFProblem *problem in problems) {
		[ids addObject:problem.elementId ?: [NSNull null]];
	}
	return ids;
}

- (void)testEveryProblemIsFoundWithItsElementAndPlace
{
	NSString *xml = WFProcess(
		@"    <startEvent id=\"start\"/>\n"
		@"    <sequenceFlow id=\"f1\" sourceRef=\"start\" targetRef=\"odd\"/>\n"
		@"    <complexGateway id=\"odd\"/>\n"
		@"    <sequenceFlow id=\"f2\" sourceRef=\"odd\" targetRef=\"wait\"/>\n"
		@"    <receiveTask id=\"wait\"/>\n"
		@"    <sequenceFlow id=\"f3\" sourceRef=\"wait\" targetRef=\"end\"/>\n"
		@"    <userTask id=\"stray\"/>\n"
		@"    <endEvent id=\"end\"/>\n");
	NSArray<WFProblem *> *problems = [WFDeploymentChecker problemsInResources:@{ @"order.bpmn": WFBytes(xml) }];
	NSArray *expected = @[ @"odd", @"wait", @"stray" ];
	XCTAssertEqualObjects(WFIds(problems), expected,
		@"each in the file's order, and none for the flows round what could not be read: %@", problems);
	WFProblem *odd = [problems firstObject];
	XCTAssertEqualObjects(odd.resourceName, @"order.bpmn");
	XCTAssertEqual(odd.line, (NSUInteger)7);
	XCTAssertEqual(odd.column, (NSUInteger)5);
	XCTAssertTrue([odd.message hasPrefix:@"odd: "], @"%@", odd.message);
	XCTAssertTrue([[odd description] hasPrefix:@"order.bpmn:7:5: error: odd: "], @"%@", [odd description]);
	XCTAssertEqual([[problems objectAtIndex:2] line], (NSUInteger)11);

	NSError *error = nil;
	XCTAssertNil([WFBpmnReader definitionsFromData:WFBytes(xml) error:&error]);
	XCTAssertEqualObjects([[error userInfo] objectForKey:WFErrorElementIdKey], @"odd", @"the first, named");
}

- (void)testARunnableDeploymentHasNone
{
	NSString *xml = WFProcess(
		@"    <startEvent id=\"start\"/>\n"
		@"    <sequenceFlow id=\"f1\" sourceRef=\"start\" targetRef=\"end\"/>\n"
		@"    <endEvent id=\"end\"/>\n");
	XCTAssertEqualObjects([WFDeploymentChecker problemsInResources:@{ @"order.bpmn": WFBytes(xml) }], @[]);
}

- (void)testWhatTheDeploymentLacksOrHasTwice
{
	NSString *xml = WFProcess(
		@"    <startEvent id=\"start\"/>\n"
		@"    <sequenceFlow id=\"f1\" sourceRef=\"start\" targetRef=\"fill\"/>\n"
		@"    <userTask id=\"fill\" camunda:formKey=\"embedded:deployment:order.xhtml\"/>\n"
		@"    <sequenceFlow id=\"f2\" sourceRef=\"fill\" targetRef=\"end\"/>\n"
		@"    <endEvent id=\"end\"/>\n");
	NSArray<WFProblem *> *problems = [WFDeploymentChecker problemsInResources:@{ @"order.bpmn": WFBytes(xml) }];
	XCTAssertEqualObjects(WFIds(problems), @[ @"fill" ], @"the form it names: %@", problems);
	XCTAssertEqual([[problems firstObject] line], (NSUInteger)7);

	NSDictionary *twice = @{ @"order.bpmn": WFBytes(xml), @"again.bpmn": WFBytes(xml),
	                         @"order.xhtml": WFBytes(@"<form/>") };
	problems = [WFDeploymentChecker problemsInResources:twice];
	XCTAssertEqual([problems count], (NSUInteger)1, @"%@", problems);
	XCTAssertEqualObjects([[problems firstObject] elementId], @"order");
	XCTAssertEqualObjects([[problems firstObject] resourceName], @"order.bpmn", @"the second read, by name");

	problems = [WFDeploymentChecker problemsInResources:@{ @"rules.dmn": WFBytes(@"<definitions/>") }];
	XCTAssertEqual([problems count], (NSUInteger)1, @"a DMN file the engine cannot read");
	XCTAssertEqualObjects([[problems firstObject] resourceName], @"rules.dmn");
}

/* A process that imports an object-role model and a flow beside it
 * (ORMKit's): its tasks done with the model's forms and the flow's
 * entries, by form key; a key naming what it does not import, and an
 * import not beside it, refused. */
- (void)testATaskIsDoneWithAModelsFormOrFlow
{
	NSString *(^process)(NSString *, NSString *) = ^NSString *(NSString *imports, NSString *key) {
		return [NSString stringWithFormat:
			@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
			@"<definitions xmlns=\"http://www.omg.org/spec/BPMN/20100524/MODEL\"\n"
			@"    xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" id=\"d\">\n%@"
			@"  <process id=\"refuel\" isExecutable=\"true\">\n"
			@"    <startEvent id=\"start\"/>\n"
			@"    <sequenceFlow id=\"f1\" sourceRef=\"start\" targetRef=\"record\"/>\n"
			@"    <userTask id=\"record\" camunda:formKey=\"%@\"/>\n"
			@"    <sequenceFlow id=\"f2\" sourceRef=\"record\" targetRef=\"end\"/>\n"
			@"    <endEvent id=\"end\"/>\n"
			@"  </process>\n</definitions>\n", imports, key];
	};
	NSString *imports =
		@"  <import importType=\"http://schemas.neumont.edu/ORM/2006-04/ORMRoot\" location=\"Logbook.orm\" namespace=\"logbook\"/>\n"
		@"  <import importType=\"http://schemas.ormkit.org/2026-10/Flows\" location=\"Records.flow\" namespace=\"records\"/>\n";
	NSData *model = WFBytes(
		@"<ormRoot:ORM2 xmlns:ormRoot=\"http://schemas.neumont.edu/ORM/2006-04/ORMRoot\" xmlns:ormq=\"http://schemas.ormkit.org/2026-10/Queries\">"
		@"<ormq:Queries><ormq:Query id=\"_q1\" Name=\"Vehicles\"/><ormq:Query id=\"_q2\" Name=\"RecordFillUp\" Kind=\"Form\"/></ormq:Queries>"
		@"</ormRoot:ORM2>");
	NSData *flow = WFBytes(
		@"<flow:Flow xmlns:flow=\"http://schemas.ormkit.org/2026-10/Flows\" Name=\"Records\" Model=\"Logbook.orm\">"
		@"<flow:Entry Name=\"Start\" Screen=\"s1\"/></flow:Flow>");
	NSData *bpmn = WFBytes(process(imports, @"ormkit:form:RecordFillUp"));
	NSDictionary *beside = @{ @"Logbook.orm": model, @"Records.flow": flow };

	XCTAssertEqualObjects([WFModelForms importsOfProcess:bpmn], (@[ @"Logbook.orm", @"Records.flow" ]));
	NSArray<WFModelForm *> *forms = [WFModelForms formsImportedBy:bpmn resources:beside];
	XCTAssertEqualObjects([forms valueForKey:@"formKey"], (@[ @"ormkit:form:RecordFillUp", @"ormkit:flow:Records.flow#Start" ]),
		@"the model's forms, not its lists; the flow's entries");
	XCTAssertEqualObjects([[forms firstObject] title], @"RecordFillUp (Logbook.orm)");
	XCTAssertEqualObjects([[forms lastObject] title], @"Records: Start (Records.flow)");
	XCTAssertTrue([[forms lastObject] isFlow]);

	NSMutableDictionary *resources = [beside mutableCopy];
	[resources setObject:bpmn forKey:@"refuel.bpmn"];
	XCTAssertEqualObjects([WFDeploymentChecker problemsInResources:resources], @[], @"a form it imports");
	[resources setObject:WFBytes(process(imports, @"ormkit:flow:Records.flow#Start")) forKey:@"refuel.bpmn"];
	XCTAssertEqualObjects([WFDeploymentChecker problemsInResources:resources], @[], @"a flow's entry");

	[resources setObject:WFBytes(process(imports, @"ormkit:form:RecordService")) forKey:@"refuel.bpmn"];
	NSArray<WFProblem *> *problems = [WFDeploymentChecker problemsInResources:resources];
	XCTAssertEqualObjects(WFIds(problems), @[ @"record" ], @"%@", problems);
	XCTAssertTrue([[[problems firstObject] message] rangeOfString:@"is not a form the process imports"].location != NSNotFound,
		@"%@", [[problems firstObject] message]);

	[resources removeObjectForKey:@"Records.flow"];
	[resources setObject:bpmn forKey:@"refuel.bpmn"];
	problems = [WFDeploymentChecker problemsInResources:resources];
	XCTAssertEqual([problems count], (NSUInteger)1, @"%@", problems);
	XCTAssertTrue([[[problems firstObject] message] rangeOfString:@"imports Records.flow, which is not beside it"].location != NSNotFound,
		@"%@", [[problems firstObject] message]);
}

@end
