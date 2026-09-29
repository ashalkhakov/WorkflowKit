#import "UDWorkflowTestCase.h"

@interface UDDeploymentTests : UDWorkflowTestCase
@end

@implementation UDDeploymentTests

- (void)testDeploymentsAreVersioned
{
	NSError *error = nil;
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"booked": @YES } forKey:@"book"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	UDRepositoryService *repository = engine.repositoryService;
	UDDeployment *first = [repository deployDefinition:[self approvalDefinition] error:&error];
	XCTAssertEqual([[first.definitions lastObject] version], (NSInteger)1);
	NSString *running = [engine.runtimeService startProcessInstanceByKey:@"approval"
	                                                           variables:nil error:&error].processInstanceId;
	UDDeployment *again = [repository deployDefinition:[self approvalDefinition] error:&error];
	XCTAssertEqualObjects(again.deploymentId, first.deploymentId);

	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"approval"];
	[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:@"boss"] addEnd:@"end"];
	[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"end"];
	UDDeployment *second = [repository deployDefinition:[b build:&error] error:&error];
	XCTAssertEqual([[second.definitions lastObject] version], (NSInteger)2);

	/* The instance started on version 1 finishes on version 1: it still
	 * reaches the booking service, which version 2 no longer has. */
	[self complete:@"approve" of:running engine:engine variables:nil];
	XCTAssertTrue([self ended:running engine:engine]);
	XCTAssertEqualObjects([[self variables:running engine:engine] objectForKey:@"booked"], @YES);
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:running] definitionId],
		[[first.definitions lastObject] definitionId]);
}

- (void)testBrokenDeploymentStoresNothing
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *xml =
		@"<definitions xmlns=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" id=\"d\">"
		 @"<process id=\"calls\" isExecutable=\"true\">"
		 @"<startEvent id=\"s\"/><complexGateway id=\"other\"/><endEvent id=\"e\"/>"
		 @"<sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"other\"/>"
		 @"<sequenceFlow id=\"f2\" sourceRef=\"other\" targetRef=\"e\"/>"
		 @"</process></definitions>";
	XCTAssertNil([engine.repositoryService
		deployResources:@{ @"calls.bpmn": [xml dataUsingEncoding:NSUTF8StringEncoding] }
		           name:@"calls"
		filterDuplicates:YES
		          error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"complexGateway"].location
		!= NSNotFound, @"%@", error);
	XCTAssertNil([engine.repositoryService latestDefinitionForKey:@"calls" error:NULL]);
}

@end
