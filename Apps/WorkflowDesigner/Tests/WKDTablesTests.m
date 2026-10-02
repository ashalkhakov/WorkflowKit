#import <XCTest/XCTest.h>
#import "WKDEditor.h"
#import "WKDProperties.h"
#import "WKDXML.h"
#import "WKDFixtures.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

/* The inspector's tables -- parameters, listeners and their fields, a call
 * activity's variables, a delegate's fields: what they read, what they
 * write, and that the engine reads that. */
@interface WKDTablesTests : XCTestCase
@end

@implementation WKDTablesTests

- (WKDProperty *)table:(NSString *)label of:(NSString *)elementId in:(WKDEditor *)editor
{
	for (WKDSection *section in WKDSectionsFor(editor, elementId)) {
		for (WKDProperty *property in section.properties) {
			if ([property.label isEqualToString:label]) {
				XCTAssertEqual(property.kind, WKDPropertyTable);
				return property;
			}
		}
	}
	XCTFail(@"%@ has no %@", elementId, label);
	return nil;
}

- (NSArray *)values:(NSString *)label of:(NSString *)elementId in:(WKDEditor *)editor master:(NSUInteger)master
{
	WKDProperty *table = [self table:label of:elementId in:editor];
	if (master != NSNotFound) {
		table = [table.details firstObject];
	}
	return [[table rowsIn:editor of:elementId master:master] valueForKey:@"values"];
}

/* The rows as they are, with these added at the end. */
- (void)add:(NSArray *)rows to:(NSString *)label of:(NSString *)elementId in:(WKDEditor *)editor master:(NSUInteger)master
{
	WKDProperty *table = [self table:label of:elementId in:editor];
	if (master != NSNotFound) {
		table = [table.details firstObject];
	}
	NSMutableArray *all = [[table rowsIn:editor of:elementId master:master] mutableCopy];
	for (NSArray *values in rows) {
		[all addObject:[WKDRow rowWithValues:values]];
	}
	NSString *reason = nil;
	XCTAssertTrue([table setRows:all in:editor of:elementId master:master error:&reason], @"%@", reason);
}

- (WFProcessDefinition *)engineRead:(WKDEditor *)editor
{
	NSError *error = nil;
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:[editor.document XMLString] error:&error];
	XCTAssertNotNil(definition, @"%@\n%@", error, [editor.document XMLString]);
	return definition;
}

- (void)testParametersAreWhatTheEngineMaps
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:nil];
	[self add:@[ @[ @"limit", @"500" ], @[ @"owner", @"=initiator" ] ] to:@"Inputs" of:@"review" in:editor master:NSNotFound];
	[self add:@[ @[ @"approved", @"${ok}" ] ] to:@"Outputs" of:@"review" in:editor master:NSNotFound];
	/* After the one the file has. */
	XCTAssertEqualObjects([self values:@"Inputs" of:@"review" in:editor master:NSNotFound],
	                      (@[ @[ @"x", @"1" ], @[ @"limit", @"500" ], @[ @"owner", @"=initiator" ] ]), @"%@",
	                      [[editor elementWithId:@"review"] XMLString]);
	WFFlowNode *review = [[self engineRead:editor] flowNodeWithId:@"review"];
	XCTAssertEqualObjects([review.inputParameters valueForKey:@"name"], (@[ @"x", @"limit", @"owner" ]));
	XCTAssertEqualObjects([[review.outputParameters firstObject] name], @"approved");
	NSXMLElement *holder = WKDChild(WKDChild([editor elementWithId:@"review"], WKDBpmnNamespace, @"extensionElements"),
	                                WKDCamundaNamespace, @"inputOutput");
	XCTAssertEqualObjects([[WKDChildren(holder, WKDCamundaNamespace, nil) valueForKey:@"localName"] componentsJoinedByString:@" "],
	                      @"inputParameter inputParameter inputParameter outputParameter", @"inputs before outputs");

	/* Every row gone: nothing left behind. */
	WKDProperty *inputs = [self table:@"Inputs" of:@"review" in:editor];
	XCTAssertTrue([inputs setRows:@[] in:editor of:@"review" master:NSNotFound error:NULL]);
	XCTAssertTrue([[self table:@"Outputs" of:@"review" in:editor] setRows:@[] in:editor of:@"review" master:NSNotFound
	                                                              error:NULL]);
	XCTAssertNil(WKDChild([editor elementWithId:@"review"], WKDBpmnNamespace, @"extensionElements"));
}

/* A list written as Camunda Modeler writes one is shown as FEEL, and left
 * as it is while another row changes. */
- (void)testARowNotEditedIsKeptAsItWasWritten
{
	NSString *xml = [WKDModellerFile stringByReplacingOccurrencesOfString:@"<bpmn:userTask id=\"review\""
		withString:@"<bpmn:userTask id=\"review\"><bpmn:extensionElements><camunda:inputOutput>"
		           @"<camunda:inputParameter name=\"reviewers\"><camunda:list><camunda:value>ann</camunda:value>"
		           @"<camunda:value>${boss}</camunda:value></camunda:list></camunda:inputParameter>"
		           @"<camunda:inputParameter name=\"limit\">5</camunda:inputParameter>"
		           @"</camunda:inputOutput></bpmn:extensionElements></bpmn:userTask><bpmn:userTask id=\"unused\""];
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(xml) undoManager:nil];
	WKDProperty *inputs = [self table:@"Inputs" of:@"review" in:editor];
	NSArray<WKDRow *> *rows = [inputs rowsIn:editor of:@"review" master:NSNotFound];
	XCTAssertEqualObjects(rows[0].values, (@[ @"reviewers", @"=[\"ann\", boss]" ]));
	rows[1].values = @[ @"limit", @"10" ];
	XCTAssertTrue([inputs setRows:rows in:editor of:@"review" master:NSNotFound error:NULL]);
	NSXMLElement *holder = WKDChild(WKDChild([editor elementWithId:@"review"], WKDBpmnNamespace, @"extensionElements"),
	                                WKDCamundaNamespace, @"inputOutput");
	XCTAssertNotNil(WKDChild([WKDChildren(holder, WKDCamundaNamespace, nil) firstObject], WKDCamundaNamespace, @"list"));
	XCTAssertEqualObjects([[WKDChildren(holder, WKDCamundaNamespace, nil) lastObject] stringValue], @"10");
}

/* A listener by name, with a field of its own; a task listener beside. */
- (void)testListenersAndTheirFields
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:nil];
	[self add:@[ @[ @"end", @"delegateExpression", @"${recorder}" ] ] to:@"Execution listeners" of:@"review"
	       in:editor master:NSNotFound];
	[self add:@[ @[ @"assignee", @"string", @"ann" ], @[ @"due", @"expression", @"=now()" ] ] to:@"Execution listeners"
	       of:@"review" in:editor master:0];
	[self add:@[ @[ @"create", @"class", @"com.example.Notify" ] ] to:@"Task listeners" of:@"review" in:editor
	   master:NSNotFound];
	XCTAssertEqualObjects([self values:@"Execution listeners" of:@"review" in:editor master:0],
	                      (@[ @[ @"assignee", @"string", @"ann" ], @[ @"due", @"expression", @"=now()" ] ]));
	WFTask *review = (WFTask *)[[self engineRead:editor] flowNodeWithId:@"review"];
	WFListener *listener = [review.executionListeners firstObject];
	XCTAssertEqualObjects([WFListener nameOfEvent:listener.event], @"end");
	XCTAssertEqualObjects(listener.delegate.delegateName, @"recorder");
	XCTAssertEqualObjects([listener.delegate.fields valueForKey:@"name"], (@[ @"assignee", @"due" ]));
	XCTAssertEqualObjects([[review.taskListeners firstObject] delegate].className, @"com.example.Notify");

	/* A listener added and not yet filled in is still one by name. */
	WKDProperty *listeners = [self table:@"Execution listeners" of:@"review" in:editor];
	NSMutableArray *rows = [[listeners rowsIn:editor of:@"review" master:NSNotFound] mutableCopy];
	[rows addObject:[WKDRow rowWithValues:listeners.blankRow]];
	XCTAssertTrue([listeners setRows:rows in:editor of:@"review" master:NSNotFound error:NULL]);
	XCTAssertEqualObjects([[[listeners rowsIn:editor of:@"review" master:NSNotFound] lastObject] values][1],
	                      @"delegateExpression");
}

/* Form fields with what is checked of them, their values and the hints
 * the form is given; what the engine reads. */
- (void)testAFormsFields
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:nil];
	[self add:@[ @[ @"amount", @"Amount", @"long", @"", @"true", @"false" ],
	             @[ @"kind", @"Kind", @"enum", @"standard", @"false", @"false" ] ]
	       to:@"Fields" of:@"review" in:editor master:NSNotFound];
	WKDProperty *fields = [self table:@"Fields" of:@"review" in:editor];
	XCTAssertEqual([fields.details count], (NSUInteger)3);
	NSUInteger amount = [[fields rowsIn:editor of:@"review" master:NSNotFound] count] - 2;
	NSString *reason = nil;
	NSArray *constraints = @[ [WKDRow rowWithValues:@[ @"min", @"1" ]] ];
	NSArray *values = @[ [WKDRow rowWithValues:@[ @"standard", @"Standard" ]], [WKDRow rowWithValues:@[ @"rush", @"Rush" ]] ];
	NSArray *hints = @[ [WKDRow rowWithValues:@[ @"placeholder", @"How many" ]] ];
	BOOL written = [fields.details[0] setRows:constraints in:editor of:@"review" master:amount error:&reason];
	XCTAssertTrue(written, @"%@", reason);
	written = [fields.details[1] setRows:values in:editor of:@"review" master:amount + 1 error:&reason];
	XCTAssertTrue(written, @"%@", reason);
	written = [fields.details[2] setRows:hints in:editor of:@"review" master:amount error:&reason];
	XCTAssertTrue(written, @"%@", reason);
	WFFormDefinition *form = [[[self engineRead:editor] flowNodeWithId:@"review"] form];
	WFFormField *amountField = [form.fields objectAtIndex:amount], *kind = [form.fields objectAtIndex:amount + 1];
	XCTAssertEqualObjects(amountField.fieldId, @"amount");
	XCTAssertEqual(amountField.type, WFFormFieldTypeLong);
	XCTAssertTrue(amountField.required);
	XCTAssertEqualObjects([amountField.constraints valueForKey:@"name"], (@[ @"required", @"min" ]));
	XCTAssertEqualObjects([amountField.properties objectForKey:@"placeholder"], @"How many");
	XCTAssertEqualObjects([kind.values valueForKey:@"valueId"], (@[ @"standard", @"rush" ]));
	XCTAssertNotNil(kind.defaultValue);

	/* Not required any more, and nothing else checked: no validation left. */
	NSMutableArray *rows = [[fields rowsIn:editor of:@"review" master:NSNotFound] mutableCopy];
	WKDRow *kindRow = rows[amount + 1];
	XCTAssertTrue([fields.details[1] setRows:@[] in:editor of:@"review" master:amount + 1 error:NULL]);
	WKDRow *amountRow = rows[amount];
	amountRow.values = @[ @"amount", @"Amount", @"long", @"", @"false", @"true" ];
	XCTAssertTrue([fields setRows:rows in:editor of:@"review" master:NSNotFound error:NULL]);
	XCTAssertEqualObjects([[fields rowsIn:editor of:@"review" master:NSNotFound][amount] values][5], @"true");
	XCTAssertTrue([fields.details[0] setRows:@[] in:editor of:@"review" master:amount error:NULL]);
	(void)kindRow;
	NSXMLElement *field = nil;
	for (NSXMLElement *candidate in WKDDescendants([editor elementWithId:@"review"], WKDCamundaNamespace, @"formField")) {
		if ([WKDAttribute(candidate, @"id") isEqualToString:@"kind"]) {
			field = candidate;
		}
	}
	XCTAssertNil(WKDChild(field, WKDCamundaNamespace, @"validation"));
	XCTAssertNil(WKDChild(field, WKDCamundaNamespace, @"value"));
}

/* A start form's business key field. */
- (void)testAStartFormsBusinessKey
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:nil];
	[self add:@[ @[ @"reference", @"Reference", @"string", @"", @"true", @"false" ] ] to:@"Fields" of:@"start"
	       in:editor master:NSNotFound];
	WKDProperty *businessKey = nil;
	for (WKDSection *section in WKDSectionsFor(editor, @"start")) {
		for (WKDProperty *property in section.properties) {
			if ([property.label isEqualToString:@"Business key"]) {
				businessKey = property;
			}
		}
	}
	XCTAssertTrue([businessKey setValue:@"reference" in:editor of:@"start" error:NULL]);
	XCTAssertEqualObjects([[[[self engineRead:editor] flowNodeWithId:@"start"] form] businessKeyFieldId], @"reference");
}

- (void)testACallActivitysVariables
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:[WKDEditor newProcessDocument] undoManager:nil];
	NSString *call = [editor insertNodeOfType:@"callActivity" eventDefinition:nil at:NSMakePoint(400, 200) error:NULL];
	NSString *end = [editor insertNodeOfType:@"endEvent" eventDefinition:nil at:NSMakePoint(600, 200) error:NULL];
	[editor connect:@"StartEvent_1" to:call error:NULL];
	[editor connect:call to:end error:NULL];
	XCTAssertTrue([[self table:@"Inputs" of:call in:editor].columns count] == 2, @"a call activity maps parameters too");
	WKDProperty *calledProcess = nil;
	for (WKDSection *section in WKDSectionsFor(editor, call)) {
		for (WKDProperty *property in section.properties) {
			if ([property.label isEqualToString:@"Called process"]) {
				calledProcess = property;
			}
		}
	}
	XCTAssertTrue([calledProcess setValue:@"pack" in:editor of:call error:NULL]);
	[self add:@[ @[ @"variable", @"items", @"parcels" ], @[ @"businessKey", @"", @"" ], @[ @"all", @"", @"" ] ]
	       to:@"Passed in" of:call in:editor master:NSNotFound];
	[self add:@[ @[ @"variable", @"tracking", @"trackingNumber" ] ] to:@"Passed back" of:call in:editor master:NSNotFound];
	WFCallActivity *node = (WFCallActivity *)[[self engineRead:editor] flowNodeWithId:call];
	XCTAssertEqual([node.inputs count], (NSUInteger)3);
	XCTAssertEqualObjects(node.inputs[0].source, @"items");
	XCTAssertEqualObjects(node.inputs[0].target, @"parcels");
	XCTAssertTrue(node.inputs[1].businessKey);
	XCTAssertTrue(node.inputs[2].allVariables);
	XCTAssertEqualObjects(node.outputs[0].target, @"trackingNumber");
}

- (void)testADelegatesFields
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:[WKDEditor newProcessDocument] undoManager:nil];
	NSString *task = [editor insertNodeOfType:@"serviceTask" eventDefinition:nil at:NSMakePoint(400, 200) error:NULL];
	NSString *end = [editor insertNodeOfType:@"endEvent" eventDefinition:nil at:NSMakePoint(600, 200) error:NULL];
	[editor connect:@"StartEvent_1" to:task error:NULL];
	[editor connect:task to:end error:NULL];
	WKDProperty *implementation = nil, *className = nil;
	for (WKDSection *section in WKDSectionsFor(editor, task)) {
		for (WKDProperty *property in section.properties) {
			if ([property.label isEqualToString:@"Implementation"]) {
				implementation = property;
			} else if ([property.label isEqualToString:@"Delegate class"]) {
				className = property;
			}
		}
	}
	XCTAssertTrue([implementation setValue:@"class" in:editor of:task error:NULL]);
	XCTAssertTrue([className setValue:@"Approver" in:editor of:task error:NULL]);
	[self add:@[ @[ @"limit", @"string", @"500" ] ] to:@"Fields" of:task in:editor master:NSNotFound];
	WFTask *node = (WFTask *)[[self engineRead:editor] flowNodeWithId:task];
	XCTAssertEqualObjects([[node.delegate.fields firstObject] name], @"limit");
}

@end
