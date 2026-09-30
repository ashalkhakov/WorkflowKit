/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Forms

- (WFFormField *)field:(NSString *)fieldId type:(WFFormFieldType)type constraints:(NSArray *)constraints
{
	return [WFFormField fieldWithId:fieldId label:[fieldId capitalizedString] type:type defaultValue:nil
	                         values:nil constraints:constraints properties:nil];
}

/* start -> review (a user task with a form) -> end; the start event's form
 * takes the order's id as its business key. */
- (WFProcessDefinition *)reviewedOrder
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"reviewedOrder"];
	[[[b addStart:@"start"] addUserTask:@"review" name:@"Review" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"start" to:@"review"] connect:@"review" to:@"end"];
	NSArray *startFields = @[
		[self field:@"orderId" type:WFFormFieldTypeString constraints:@[ [WFFormConstraint constraint:@"required" configuration:nil] ]],
		[self field:@"amount" type:WFFormFieldTypeLong constraints:nil],
	];
	[b setForm:[WFFormDefinition formWithKey:nil fields:startFields businessKeyFieldId:@"orderId"] forElement:@"start"];
	NSArray *fields = @[
		[self field:@"amount" type:WFFormFieldTypeLong constraints:(@[
			[WFFormConstraint constraint:@"required" configuration:nil],
			[WFFormConstraint constraint:@"min" configuration:@"1"],
			[WFFormConstraint constraint:@"max" configuration:@"10000"] ])],
		[self field:@"approved" type:WFFormFieldTypeBoolean constraints:nil],
		[self field:@"comment" type:WFFormFieldTypeString constraints:@[ [WFFormConstraint constraint:@"maxlength" configuration:@"10"] ]],
		[self field:@"due" type:WFFormFieldTypeDate constraints:@[ [WFFormConstraint constraint:@"min" configuration:@"2020-01-01"] ]],
		[WFFormField fieldWithId:@"category" label:@"Category" type:WFFormFieldTypeEnum defaultValue:nil
		                  values:(@[ [WFFormFieldValue valueWithId:@"a" name:@"First"],
		                             [WFFormFieldValue valueWithId:@"b" name:@"Second"] ])
		             constraints:nil properties:@{ @"widget": @"radio" }],
		[WFFormField fieldWithId:@"reviewer" label:@"Reviewer" type:WFFormFieldTypeString
		            defaultValue:[WFFeelExpression expressionWithCamunda7String:@"owner" error:NULL]
		                  values:nil constraints:nil properties:nil],
		[self field:@"orderId" type:WFFormFieldTypeString constraints:@[ [WFFormConstraint constraint:@"readonly" configuration:nil] ]],
	];
	[b setForm:[WFFormDefinition formWithKey:@"app:review" fields:fields businessKeyFieldId:nil] forElement:@"review"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

/* An instance <data> with an element per value, as a form submits it. */
- (NSXMLDocument *)instance:(NSDictionary *)values
{
	NSXMLElement *data = [[NSXMLElement alloc] initWithName:@"data"];
	for (NSString *name in values) {
		NSXMLElement *element = [[NSXMLElement alloc] initWithName:name];
		[element setStringValue:[[values objectForKey:name] description]];
		[data addChild:element];
	}
	return [[NSXMLDocument alloc] initWithRootElement:data];
}

- (NSString *)textOf:(NSString *)name in:(NSXMLDocument *)instance
{
	return [[[[instance rootElement] elementsForName:name] firstObject] stringValue];
}

- (void)testFieldFormsAreGeneratedXForms
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self reviewedOrder] engine:engine
	                variables:@{ @"amount": @50, @"orderId": @"o-1", @"owner": @"ann" }];
	NSString *taskId = [self task:@"review" of:pid engine:engine].taskId;

	WFFormData *data = [engine.formService formDataForTask:taskId error:&error];
	XCTAssertNotNil(data, @"%@", error);
	XCTAssertEqualObjects(data.formKey, @"app:review");
	/* The document: a model with <data>, a bind per field, a control per field. */
	NSString *xml = [data.document XMLString];
	for (NSString *part in @[ @"http://www.w3.org/2002/xforms", @"<data xmlns=\"\">", @"ref=\"amount\"", @"xsd:long",
	                          @"required=\"true()\"", @"readonly=\"true()\"", @"number(.) &gt;= 1",
	                          @"string-length(.) &lt;= 10", @"seconds-from-dateTime", @"xf:select1",
	                          @"<xf:value>b</xf:value>", @"xsd:dateTime", @"xsd:boolean" ]) {
		XCTAssertTrue([xml rangeOfString:part].location != NSNotFound, @"%@ in %@", part, xml);
	}
	/* The instance: each field's variable, else its default. */
	XCTAssertEqualObjects([[data.instance rootElement] name], @"data");
	XCTAssertEqualObjects([self textOf:@"amount" in:data.instance], @"50");
	XCTAssertEqualObjects([self textOf:@"reviewer" in:data.instance], @"ann", @"the default, over the variables");
	XCTAssertEqualObjects([self textOf:@"orderId" in:data.instance], @"o-1");
	XCTAssertEqualObjects([self textOf:@"approved" in:data.instance], @"");

	/* Instances the fields do not take: nothing changes. */
	NSDictionary *wrong = @{
		@"not a whole number": @{ @"amount": @"x" },
		@"less than 1": @{ @"amount": @0 },
		@"more than 10000": @{ @"amount": @"20000" },
		@"is required": @{ @"amount": @"" },
		@"not true or false": @{ @"amount": @5, @"approved": @"maybe" },
		@"longer than 10": @{ @"amount": @5, @"comment": @"far too long a comment" },
		@"not a date": @{ @"amount": @5, @"due": @"soon" },
		@"less than 2020-01-01": @{ @"amount": @5, @"due": @"2019-06-01" },
		@"not one of a, b": @{ @"amount": @5, @"category": @"c" },
	};
	for (NSString *reason in wrong) {
		error = nil;
		XCTAssertFalse([engine.formService submitTaskForm:taskId instance:[self instance:[wrong objectForKey:reason]]
		                                             error:&error], @"%@", reason);
		XCTAssertEqual([error code], (NSInteger)WFErrorInvalidFormData, @"%@: %@", reason, error);
		XCTAssertTrue([[error localizedDescription] rangeOfString:reason].location != NSNotFound, @"%@: %@", reason, error);
	}
	XCTAssertNotNil([self task:@"review" of:pid engine:engine]);

	/* Text converted to each field's type; a read-only field, and what is no
	 * field, left as they are. */
	XCTAssertTrue([engine.formService submitTaskForm:taskId
	                                        instance:[self instance:(@{ @"amount": @"120", @"approved": @"true",
	                                                                    @"due": @"2030-01-02", @"category": @"b",
	                                                                    @"orderId": @"o-2", @"extra": @1 })]
	                                           error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	NSDictionary *variables = [self variables:pid engine:engine];
	XCTAssertEqualObjects([variables objectForKey:@"amount"], @120);
	XCTAssertEqualObjects([variables objectForKey:@"approved"], @YES);
	XCTAssertEqualObjects([variables objectForKey:@"due"], [NSDate dateWithTimeIntervalSince1970:1893542400]);
	XCTAssertEqualObjects([variables objectForKey:@"category"], @"b");
	XCTAssertEqualObjects([variables objectForKey:@"orderId"], @"o-1");
	XCTAssertNil([variables objectForKey:@"extra"]);
	XCTAssertFalse([engine.formService submitTaskForm:taskId instance:[self instance:@{}] error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorUnknownElement);
}

- (void)testStartFormsTakeTheBusinessKey
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self reviewedOrder] engine:engine];
	WFFormData *data = [engine.formService startFormDataForKey:@"reviewedOrder" error:&error];
	XCTAssertNotNil(data, @"%@", error);
	XCTAssertNil(data.context.taskId);
	XCTAssertEqualObjects([[[data.instance rootElement] children] valueForKey:@"name"], (@[ @"orderId", @"amount" ]));

	XCTAssertNil([engine.formService submitStartFormForKey:@"reviewedOrder" businessKey:nil
	                                              instance:[self instance:@{ @"amount": @3 }] error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorInvalidFormData);
	WFProcessInstance *instance = [engine.formService submitStartFormForKey:@"reviewedOrder" businessKey:nil
	                                                               instance:[self instance:(@{ @"orderId": @"o-9",
	                                                                                           @"amount": @"7" })]
	                                                                  error:&error];
	XCTAssertNotNil(instance, @"%@", error);
	XCTAssertEqualObjects(instance.businessKey, @"o-9");
	XCTAssertEqualObjects([[engine.runtimeService variablesForProcessInstance:instance.processInstanceId error:NULL]
		objectForKey:@"amount"], @7);
}

/* start (a form of its own, deployed with it, and its handler) -> pick
 * (the same form) -> end */
- (NSDictionary *)orderFormResources
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"handled"];
	[[[b addStart:@"start"] addUserTask:@"pick" name:@"Pick" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"start" to:@"pick"] connect:@"pick" to:@"end"];
	WFFormDefinition *form = [WFFormDefinition formWithKey:@"embedded:deployment:forms/order.xhtml" fields:nil
	                                    businessKeyFieldId:nil handler:@"orders"];
	[b setForm:form forElement:@"start"];
	[b setForm:form forElement:@"pick"];
	NSString *bpmn = [WFBpmnWriter XMLStringFromDefinition:[b build:&error] error:&error];
	XCTAssertNotNil(bpmn, @"%@", error);
	NSString *xforms = @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
		@"<head><xf:model><xf:instance><order xmlns=\"\"><lines/><total/></order></xf:instance></xf:model></head>"
		@"<body><xf:repeat nodeset=\"lines/line\"><xf:output ref=\"@item\"/></xf:repeat>"
		@"<xf:input ref=\"total\"><xf:label>Total</xf:label></xf:input></body></html>";
	return @{ @"handled.bpmn": [bpmn dataUsingEncoding:NSUTF8StringEncoding],
	          @"forms/order.xhtml": [xforms dataUsingEncoding:NSUTF8StringEncoding] };
}

- (void)testFormHandlersDecideWhatAFormDoes
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[engine registerDelegateClass:[WFOrderFormHandler class] forName:@"orders"];
	XCTAssertNotNil([engine.repositoryService deployResources:[self orderFormResources] name:@"handled"
	                                         filterDuplicates:NO error:&error], @"%@", error);

	/* Started through the form: the handler's variables and business key. */
	WFFormData *start = [engine.formService startFormDataForKey:@"handled" error:&error];
	XCTAssertNotNil(start, @"%@", error);
	XCTAssertTrue([[start.document XMLString] rangeOfString:@"xf:repeat"].location != NSNotFound, @"deployed with it");
	XCTAssertEqualObjects([[start.instance rootElement] name], @"order");
	NSXMLDocument *order = [[NSXMLDocument alloc] initWithXMLString:
		@"<order><lines><line item=\"tea\"/><line item=\"cups\"/></lines><total>12</total></order>" options:0 error:NULL];
	WFProcessInstance *instance = [engine.formService submitStartFormForKey:@"handled" businessKey:nil
	                                                               instance:order error:&error];
	XCTAssertNotNil(instance, @"%@", error);
	XCTAssertEqualObjects(instance.businessKey, @"order-12");
	XCTAssertEqualObjects([engine.runtimeService variablesForProcessInstance:instance.processInstanceId error:NULL],
		(@{ @"total": @12, @"lineCount": @2 }));

	/* The task's: the handler's instance, from the variables; its refusal. */
	NSString *taskId = [self task:@"pick" of:instance.processInstanceId engine:engine].taskId;
	WFFormData *pick = [engine.formService formDataForTask:taskId error:&error];
	XCTAssertEqualObjects([self textOf:@"total" in:pick.instance], @"12");
	NSXMLDocument *empty = [[NSXMLDocument alloc] initWithXMLString:@"<order><lines/></order>" options:0 error:NULL];
	XCTAssertFalse([engine.formService submitTaskForm:taskId instance:empty error:&error]);
	XCTAssertEqualObjects([error localizedDescription], @"an order needs its total");
	XCTAssertTrue([engine.formService submitTaskForm:taskId instance:order error:&error], @"%@", error);
	XCTAssertTrue([self ended:instance.processInstanceId engine:engine]);

	/* A form's document must be in its deployment. */
	NSMutableDictionary *missing = [[self orderFormResources] mutableCopy];
	[missing removeObjectForKey:@"forms/order.xhtml"];
	XCTAssertNil([engine.repositoryService deployResources:missing name:@"missing" filterDuplicates:NO error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"forms/order.xhtml is not in the deployment"].location
		!= NSNotFound, @"%@", error);
}

/* A form whose key the application resolves: the engine's default handler
 * takes it, and without one its submissions are refused. */
- (void)testTheDefaultFormHandler
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"keyed"];
	[[[b addStart:@"start"] addUserTask:@"sign" name:@"Sign" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"start" to:@"sign"] connect:@"sign" to:@"end"];
	[b setForm:[WFFormDefinition formWithKey:@"app:signature" fields:nil businessKeyFieldId:nil] forElement:@"sign"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"total": @4 }];
	NSString *taskId = [self task:@"sign" of:pid engine:engine].taskId;
	WFFormData *data = [engine.formService formDataForTask:taskId error:&error];
	XCTAssertNotNil(data, @"%@", error);
	XCTAssertEqualObjects(data.formKey, @"app:signature");
	XCTAssertNil(data.document, @"the application's");
	XCTAssertNil(data.instance, @"no handler");
	NSXMLDocument *order = [[NSXMLDocument alloc] initWithXMLString:@"<order><total>9</total></order>" options:0 error:NULL];
	XCTAssertFalse([engine.formService submitTaskForm:taskId instance:order error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorHandler);

	engine.defaultFormHandler = [[WFOrderFormHandler alloc] init];
	XCTAssertEqualObjects([self textOf:@"total" in:[engine.formService formDataForTask:taskId error:NULL].instance], @"4");
	XCTAssertTrue([engine.formService submitTaskForm:taskId instance:order error:&error], @"%@", error);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"total"], @9);
}

- (void)testFormsInBpmn
{
	NSError *error = nil;
	NSString *xml =
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" id=\"d\">"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\">"
		 @"<bpmn:startEvent id=\"s\" camunda:formKey=\"app:start\"><bpmn:extensionElements>"
		 @"<camunda:formData businessKey=\"ref\"><camunda:formField id=\"ref\" label=\"Reference\" type=\"string\"/>"
		 @"</camunda:formData></bpmn:extensionElements></bpmn:startEvent>"
		 @"<bpmn:userTask id=\"t\" name=\"Check\" camunda:formHandlerClass=\"com.example.CheckForm\">"
		 @"<bpmn:extensionElements><camunda:formData>"
		 @"<camunda:formField id=\"size\" label=\"Size\" type=\"enum\" defaultValue=\"m\">"
		 @"<camunda:properties><camunda:property id=\"hint\" value=\"pick one\"/></camunda:properties>"
		 @"<camunda:value id=\"s\" name=\"Small\"/><camunda:value id=\"m\" name=\"Medium\"/></camunda:formField>"
		 @"<camunda:formField id=\"count\" type=\"long\" defaultValue=\"${seed}\"><camunda:validation>"
		 @"<camunda:constraint name=\"required\"/><camunda:constraint name=\"max\" config=\"9\"/>"
		 @"</camunda:validation></camunda:formField>"
		 @"<camunda:formField id=\"when\" type=\"date\" defaultValue=\"2030-01-01\"/>"
		 @"</camunda:formData></bpmn:extensionElements></bpmn:userTask><bpmn:endEvent id=\"e\"/>"
		 @"<bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"t\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"t\" targetRef=\"e\"/>"
		 @"</bpmn:process></bpmn:definitions>";
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	WFFormDefinition *start = [[definition nodeWithId:@"s"] form];
	XCTAssertEqualObjects(start.formKey, @"app:start");
	XCTAssertEqualObjects(start.businessKeyFieldId, @"ref");
	WFFormDefinition *task = [[definition nodeWithId:@"t"] form];
	XCTAssertNil(task.formKey);
	XCTAssertEqualObjects(task.formHandlerName, @"com.example.CheckForm");
	XCTAssertEqualObjects([task.fields valueForKey:@"fieldId"], (@[ @"size", @"count", @"when" ]));
	WFFormField *size = [task fieldWithId:@"size"];
	XCTAssertEqual(size.type, WFFormFieldTypeEnum);
	XCTAssertEqualObjects([size.values valueForKey:@"name"], (@[ @"Small", @"Medium" ]));
	XCTAssertEqualObjects([size.properties objectForKey:@"hint"], @"pick one");
	XCTAssertEqualObjects([size.defaultValue valueWithVariables:@{}], @"m");
	XCTAssertEqualObjects(([[task fieldWithId:@"count"].constraints valueForKey:@"name"]), (@[ @"required", @"max" ]));

	NSString *written = [WFBpmnWriter XMLStringFromDefinition:definition error:&error];
	WFProcessDefinition *again = [WFBpmnReader definitionFromXMLString:written error:&error];
	XCTAssertNotNil(again, @"%@\n%@", error, written);
	WFFormDefinition *reread = [[again nodeWithId:@"t"] form];
	XCTAssertEqualObjects([reread.fields valueForKey:@"fieldId"], (@[ @"size", @"count", @"when" ]));
	XCTAssertEqualObjects(([[reread fieldWithId:@"count"] defaultValue].expressionString),
		([[task fieldWithId:@"count"] defaultValue].expressionString));
	XCTAssertEqualObjects(([[[reread fieldWithId:@"when"] defaultValue] valueWithVariables:@{}]),
		([[[task fieldWithId:@"when"] defaultValue] valueWithVariables:@{}]));
	XCTAssertEqualObjects([[again nodeWithId:@"s"] form].formKey, @"app:start");
	XCTAssertEqualObjects(reread.formHandlerName, @"com.example.CheckForm");
	XCTAssertEqualObjects([[[again nodeWithId:@"s"] form] businessKeyFieldId], @"ref");

	/* What the engine does not take. */
	NSDictionary *refused = @{
		@"formRef": [xml stringByReplacingOccurrencesOfString:@"camunda:formKey=\"app:start\""
		                                           withString:@"camunda:formRef=\"x\""],
		@"type \"custom\"": [xml stringByReplacingOccurrencesOfString:@"type=\"date\"" withString:@"type=\"custom\""],
		@"constraint validator": [xml stringByReplacingOccurrencesOfString:@"name=\"required\""
		                                                        withString:@"name=\"validator\""],
		@"datePattern": [xml stringByReplacingOccurrencesOfString:@"type=\"date\""
		                                               withString:@"type=\"date\" datePattern=\"dd/MM/yyyy\""],
		@"an enum needs its values": [xml stringByReplacingOccurrencesOfString:@"<camunda:value id=\"s\" name=\"Small\"/><camunda:value id=\"m\" name=\"Medium\"/>"
		                                                            withString:@""],
		@"only a start form sets the business key": [xml stringByReplacingOccurrencesOfString:@"<bpmn:extensionElements><camunda:formData>"
		                                                                           withString:@"<bpmn:extensionElements><camunda:formData businessKey=\"size\">"],
		@"not an XML name": [xml stringByReplacingOccurrencesOfString:@"id=\"when\"" withString:@"id=\"2when\""],
		@"needs a whole number": [xml stringByReplacingOccurrencesOfString:@"config=\"9\"" withString:@"config=\"nine\""],
	};
	for (NSString *reason in refused) {
		error = nil;
		XCTAssertNil([WFBpmnReader definitionFromXMLString:[refused objectForKey:reason] error:&error], @"%@", reason);
		XCTAssertTrue([[error localizedDescription] rangeOfString:reason].location != NSNotFound, @"%@: %@", reason, error);
	}
	/* Only on a user task or a start event. */
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"elsewhere"];
	[[[b addStart:@"start"] addEnd:@"end"] connect:@"start" to:@"end"];
	[b setForm:[WFFormDefinition formWithKey:@"x" fields:nil businessKeyFieldId:nil] forElement:@"end"];
	XCTAssertNil([b build:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"only a user task or a start event"].location != NSNotFound);
}
