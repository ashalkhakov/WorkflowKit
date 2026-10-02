#import <XCTest/XCTest.h>
#import "WKDDeployment.h"
#import "WKDXML.h"
#import "WKDFixtures.h"

@interface WKDDeploymentTests : XCTestCase
@end

@implementation WKDDeploymentTests
{
	NSURL *_directory;
}

- (void)setUp
{
	[super setUp];
	_directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
		[[NSProcessInfo processInfo] globallyUniqueString]] isDirectory:YES];
	[[NSFileManager defaultManager] createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:nil
	                                               error:NULL];
}

- (void)tearDown
{
	[[NSFileManager defaultManager] removeItemAtURL:_directory error:NULL];
	[super tearDown];
}

/* The modeller file with forms: one embedded twice, and a key the
 * application resolves, which is not the deployment's business. */
- (NSXMLDocument *)documentWithForms
{
	NSXMLDocument *document = WKDParse(WKDModellerFile);
	NSXMLElement *process = WKDChild([document rootElement], WKDBpmnNamespace, @"process");
	NSDictionary *keys = @{ @"start": @"embedded:deployment:order.xhtml", @"review": @"embedded:deployment:review.xhtml",
	                        @"pack": @"app:packing" };
	for (NSXMLElement *element in WKDDescendants(process, WKDBpmnNamespace, nil)) {
		NSString *key = [keys objectForKey:WKDAttribute(element, @"id") ?: @""];
		if (key != nil) {
			WKDSetQualifiedAttribute(document, element, WKDCamundaNamespace, @"formKey", key);
		}
	}
	return document;
}

- (void)testTheFormsAProcessEmbeds
{
	XCTAssertEqualObjects(WKDEmbeddedForms([self documentWithForms]), (@[ @"order.xhtml", @"review.xhtml" ]));
	XCTAssertEqualObjects(WKDEmbeddedForms(WKDParse(WKDModellerFile)), @[]);
}

- (void)testTheProcessGoesWithItsForms
{
	[@"<order/>" writeToURL:[_directory URLByAppendingPathComponent:@"order.xhtml"] atomically:YES
	              encoding:NSUTF8StringEncoding error:NULL];
	[@"<review/>" writeToURL:[_directory URLByAppendingPathComponent:@"review.xhtml"] atomically:YES
	               encoding:NSUTF8StringEncoding error:NULL];
	NSArray *missing = nil;
	NSDictionary *resources = WKDDeploymentResources([self documentWithForms], @"order.bpmn", _directory, nil,
	                                                 &missing);
	XCTAssertEqualObjects([[resources allKeys] sortedArrayUsingSelector:@selector(compare:)],
	                      (@[ @"order.bpmn", @"order.xhtml", @"review.xhtml" ]));
	XCTAssertEqualObjects([resources objectForKey:@"review.xhtml"], @"<review/>");
	XCTAssertTrue([[resources objectForKey:@"order.bpmn"] rangeOfString:@"embedded:deployment:order.xhtml"].location
	              != NSNotFound);
	XCTAssertEqualObjects(missing, @[]);

	/* A form open in the form editor goes as it is there, saved or not. */
	resources = WKDDeploymentResources([self documentWithForms], @"order.bpmn", _directory,
	                                   @{ @"review.xhtml": @"<review>edited</review>" }, &missing);
	XCTAssertEqualObjects([resources objectForKey:@"review.xhtml"], @"<review>edited</review>");
	XCTAssertEqualObjects([resources objectForKey:@"order.xhtml"], @"<order/>");
	resources = WKDDeploymentResources([self documentWithForms], @"order.bpmn", nil,
	                                   @{ @"order.xhtml": @"<order/>", @"review.xhtml": @"<review/>" }, &missing);
	XCTAssertNotNil(resources, @"all open: no directory needed");
}

/* The DMN files beside that define its business rule tasks' decisions:
 * not other files', nor a decision an expression names. */
- (void)testTheProcessGoesWithItsDecisions
{
	NSXMLDocument *document = WKDParse(WKDModellerFile);
	NSXMLElement *process = WKDChild([document rootElement], WKDBpmnNamespace, @"process");
	NSXMLElement *rules = WKDNewElement(document, WKDBpmnNamespace, @"businessRuleTask");
	WKDSetAttribute(rules, @"id", @"rules");
	WKDSetQualifiedAttribute(document, rules, WKDCamundaNamespace, @"decisionRef", @"dish");
	[process addChild:rules];
	NSXMLElement *dynamic = WKDNewElement(document, WKDBpmnNamespace, @"businessRuleTask");
	WKDSetAttribute(dynamic, @"id", @"dynamic");
	WKDSetQualifiedAttribute(document, dynamic, WKDCamundaNamespace, @"decisionRef", @"${which}");
	[process addChild:dynamic];
	NSArray *refs = @[ @"dish" ];
	XCTAssertEqualObjects(WKDDecisionRefs(document), refs);

	[WKDDecisionsFile writeToURL:[_directory URLByAppendingPathComponent:@"dishes.dmn"] atomically:YES
	                    encoding:NSUTF8StringEncoding error:NULL];
	NSString *other = [WKDDecisionsFile stringByReplacingOccurrencesOfString:@"\"dish\"" withString:@"\"plate\""];
	[other writeToURL:[_directory URLByAppendingPathComponent:@"other.dmn"] atomically:YES
	         encoding:NSUTF8StringEncoding error:NULL];
	XCTAssertEqualObjects(WKDDecisionFileDefining(@"dish", _directory, nil), @"dishes.dmn");
	XCTAssertNil(WKDDecisionFileDefining(@"dessert", _directory, nil));
	NSDictionary *resources = WKDDeploymentResources(document, @"order.bpmn", _directory, nil, NULL);
	NSArray *names = @[ @"dishes.dmn", @"order.bpmn" ];
	XCTAssertEqualObjects([[resources allKeys] sortedArrayUsingSelector:@selector(compare:)], names);
	/* As the decision editor has it, saved or not. */
	resources = WKDDeploymentResources(document, @"order.bpmn", _directory, @{ @"dishes.dmn": WKDDecisionsFile }, NULL);
	XCTAssertEqualObjects([resources objectForKey:@"dishes.dmn"], WKDDecisionsFile);
	[[NSFileManager defaultManager] removeItemAtURL:[_directory URLByAppendingPathComponent:@"dishes.dmn"] error:NULL];
	resources = WKDDeploymentResources(document, @"order.bpmn", _directory, nil, NULL);
	XCTAssertNotNil(resources, @"a decision deployed on its own is not missing");
	XCTAssertNil([resources objectForKey:@"other.dmn"]);
}

- (void)testAMissingFormStopsTheDeployment
{
	[@"<order/>" writeToURL:[_directory URLByAppendingPathComponent:@"order.xhtml"] atomically:YES
	              encoding:NSUTF8StringEncoding error:NULL];
	NSArray *missing = nil;
	XCTAssertNil(WKDDeploymentResources([self documentWithForms], @"order.bpmn", _directory, nil, &missing));
	XCTAssertEqualObjects(missing, @[ @"review.xhtml" ]);
	XCTAssertNil(WKDDeploymentResources([self documentWithForms], @"order.bpmn", nil, nil, &missing),
	             @"a document never saved has nowhere to find them");
	XCTAssertEqual([missing count], (NSUInteger)2);
	XCTAssertNotNil(WKDDeploymentResources(WKDParse(WKDModellerFile), @"order.bpmn", nil, nil, &missing),
	                @"one without forms needs no directory");
}

/* A form to start from: the fields, as the engine makes their form. */
- (void)testAFormIsMadeFromItsFields
{
	NSXMLDocument *document = WKDParse(WKDModellerFile);
	NSXMLElement *extensions = WKDEnsureChild(document, WKDElementWithId(document, @"review"), WKDBpmnNamespace,
	                                          @"extensionElements");
	NSXMLElement *data = WKDNewElement(document, WKDCamundaNamespace, @"formData");
	NSXMLElement *field = WKDNewElement(document, WKDCamundaNamespace, @"formField");
	WKDSetAttribute(field, @"id", @"amount");
	WKDSetAttribute(field, @"label", @"Amount");
	WKDSetAttribute(field, @"type", @"long");
	NSXMLElement *validation = WKDNewElement(document, WKDCamundaNamespace, @"validation");
	NSXMLElement *required = WKDNewElement(document, WKDCamundaNamespace, @"constraint");
	WKDSetAttribute(required, @"name", @"required");
	[validation addChild:required];
	[field addChild:validation];
	[data addChild:field];
	[extensions addChild:data];
	XCTAssertNil(WKDEmbeddedFormOf(document, WKDElementWithId(document, @"review")));
	NSError *error = nil;
	NSXMLDocument *form = WKDGeneratedForm(document, @"review", &error);
	XCTAssertNotNil(form, @"%@", error);
	NSString *text = [form XMLString];
	XCTAssertTrue([text rangeOfString:@"<amount"].location != NSNotFound, @"the instance: %@", text);
	XCTAssertTrue([text rangeOfString:@"required"].location != NSNotFound, @"the bind: %@", text);
	XCTAssertTrue([text rangeOfString:@"Amount"].location != NSNotFound, @"the control's label: %@", text);
	NSXMLElement *review = WKDElementWithId(document, @"review");
	WKDSetQualifiedAttribute(document, review, WKDCamundaNamespace, @"formKey", @"embedded:deployment:review.xhtml");
	XCTAssertEqualObjects(WKDEmbeddedFormOf(document, review), @"review.xhtml");
	WKDSetQualifiedAttribute(document, review, WKDCamundaNamespace, @"formKey", @"app:review");
	XCTAssertNil(WKDEmbeddedFormOf(document, review), @"a key the application resolves");
}

@end
