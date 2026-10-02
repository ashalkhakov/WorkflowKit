#import <XCTest/XCTest.h>
#import "WDFormDocument.h"

/* A form as the engine writes one for fields, and as one is deployed. */
static NSString * const WDFieldsForm =
	@"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
	@"<head><title>approve</title><xf:model>"
	@"<xf:instance><data xmlns=\"\"><amount/><approved/></data></xf:instance>"
	@"<xf:bind ref=\"approved\" type=\"xsd:boolean\"/>"
	@"</xf:model></head><body><xf:input ref=\"amount\"><xf:label>Amount</xf:label></xf:input></body></html>";

static NSString * const WDDeployedForm =
	@"<h:html xmlns:h=\"http://www.w3.org/1999/xhtml\" xmlns=\"http://www.w3.org/2002/xforms\">"
	@"<h:head><model id=\"m\"><instance id=\"lookup\" src=\"lookup.xml\"/></model>"
	@"<model><instance src=\"order.xml\"/><instance id=\"other\"><x/></instance></model></h:head>"
	@"<h:body/></h:html>";

@interface WDFormDocumentTests : XCTestCase
@end

@implementation WDFormDocumentTests

- (NSXMLDocument *)parse:(NSString *)text
{
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:&error];
	XCTAssertNotNil(document, @"%@", error);
	return document;
}

- (NSXMLElement *)instanceOf:(NSXMLDocument *)document at:(NSUInteger)index
{
	NSMutableArray *found = [NSMutableArray array];
	NSMutableArray *nodes = [NSMutableArray arrayWithObject:[document rootElement]];
	while ([nodes count] > 0) {
		NSXMLNode *node = [nodes objectAtIndex:0];
		[nodes removeObjectAtIndex:0];
		if ([node kind] == NSXMLElementKind && [[node localName] isEqualToString:@"instance"]) {
			[found addObject:node];
		}
		[nodes insertObjects:[node children] ?: @[]
		           atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [[node children] count])]];
	}
	return index < [found count] ? [found objectAtIndex:index] : nil;
}

- (void)testTheTasksInstanceReplacesTheDefault
{
	NSError *error = nil;
	NSString *merged = WDFormDocumentWithInstance(WDFieldsForm,
		@"<data><amount>12</amount><approved>true</approved></data>", &error);
	XCTAssertNotNil(merged, @"%@", error);
	NSXMLDocument *document = [self parse:merged];
	NSXMLElement *instance = [self instanceOf:document at:0];
	XCTAssertEqual([[instance children] count], (NSUInteger)1);
	NSXMLElement *data = (NSXMLElement *)[[instance children] firstObject];
	XCTAssertEqualObjects([data localName], @"data");
	/* Still in no namespace, under XHTML's default. */
	XCTAssertEqual([[data URI] length], (NSUInteger)0, @"%@", [data URI]);
	XCTAssertEqualObjects([[[data elementsForName:@"amount"] firstObject] stringValue], @"12");
	/* The rest of the form as it was. */
	XCTAssertEqual([[[document rootElement] elementsForName:@"body"] count], (NSUInteger)1);
}

/* Names keep their case: Apple's takes an <html> root for HTML, and would
 * write applicationId as applicationid, which the form's binds and
 * controls -- ref="applicationId" -- then miss. */
- (void)testNamesKeepTheirCase
{
	NSString *form = [WDFieldsForm stringByReplacingOccurrencesOfString:@"amount" withString:@"applicationId"];
	NSError *error = nil;
	NSString *merged = WDFormDocumentWithInstance(form,
		@"<data><applicationId>A-1</applicationId><approved/></data>", &error);
	XCTAssertNotNil(merged, @"%@", error);
	XCTAssertTrue([merged rangeOfString:@"<applicationId>A-1</applicationId>"].location != NSNotFound, @"%@", merged);
	XCTAssertTrue([merged rangeOfString:@"applicationid"].location == NSNotFound, @"%@", merged);
}

- (void)testTheFirstModelsFirstInstanceIsTheDefault
{
	NSError *error = nil;
	NSString *merged = WDFormDocumentWithInstance(WDDeployedForm, @"<order><n>1</n></order>", &error);
	XCTAssertNotNil(merged, @"%@", error);
	NSXMLDocument *document = [self parse:merged];
	NSXMLElement *first = [self instanceOf:document at:0];
	XCTAssertEqualObjects([[first attributeForName:@"id"] stringValue], @"lookup");
	XCTAssertNil([first attributeForName:@"src"], @"%@", merged);
	XCTAssertEqualObjects([[[first children] firstObject] localName], @"order");
	/* The second model's are left alone. */
	XCTAssertNotNil([[self instanceOf:document at:1] attributeForName:@"src"]);
}

- (void)testNoInstanceLeavesTheForm
{
	NSString *merged = WDFormDocumentWithInstance(WDFieldsForm, @"", NULL);
	XCTAssertEqualObjects([[[[self instanceOf:[self parse:merged] at:0] children] firstObject] localName], @"data");
}

- (void)testWhatIsNotAFormIsAnError
{
	NSError *error = nil;
	XCTAssertNil(WDFormDocumentWithInstance(@"<html", @"<data/>", &error));
	XCTAssertNotNil(error);
	error = nil;
	XCTAssertNil(WDFormDocumentWithInstance(@"<html xmlns=\"http://www.w3.org/1999/xhtml\"/>", @"<data/>", &error));
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"model"].location != NSNotFound, @"%@", error);
	error = nil;
	XCTAssertNil(WDFormDocumentWithInstance(WDFieldsForm, @"<data>", &error));
	XCTAssertNotNil(error);
}

@end
