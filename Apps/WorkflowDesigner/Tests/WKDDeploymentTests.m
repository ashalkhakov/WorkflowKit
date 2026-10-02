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
	NSDictionary *resources = WKDDeploymentResources([self documentWithForms], @"order.bpmn", _directory, &missing);
	XCTAssertEqualObjects([[resources allKeys] sortedArrayUsingSelector:@selector(compare:)],
	                      (@[ @"order.bpmn", @"order.xhtml", @"review.xhtml" ]));
	XCTAssertEqualObjects([resources objectForKey:@"review.xhtml"], @"<review/>");
	XCTAssertTrue([[resources objectForKey:@"order.bpmn"] rangeOfString:@"embedded:deployment:order.xhtml"].location
	              != NSNotFound);
	XCTAssertEqualObjects(missing, @[]);
}

- (void)testAMissingFormStopsTheDeployment
{
	[@"<order/>" writeToURL:[_directory URLByAppendingPathComponent:@"order.xhtml"] atomically:YES
	              encoding:NSUTF8StringEncoding error:NULL];
	NSArray *missing = nil;
	XCTAssertNil(WKDDeploymentResources([self documentWithForms], @"order.bpmn", _directory, &missing));
	XCTAssertEqualObjects(missing, @[ @"review.xhtml" ]);
	XCTAssertNil(WKDDeploymentResources([self documentWithForms], @"order.bpmn", nil, &missing),
	             @"a document never saved has nowhere to find them");
	XCTAssertEqual([missing count], (NSUInteger)2);
	XCTAssertNotNil(WKDDeploymentResources(WKDParse(WKDModellerFile), @"order.bpmn", nil, &missing),
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
