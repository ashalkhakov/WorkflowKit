#import "WFModelForms.h"
#import "WFDeploymentChecker.h"
#import "WFDeployment+Internal.h"
#import "WFDecision.h"
#import "WFFlowElements.h"
#import "WFTimers.h"

BOOL
WFIsBpmnResource(NSString *name)
{
	return [name hasSuffix:@".bpmn"] || [name hasSuffix:@".bpmn20.xml"];
}

BOOL
WFIsDmnResource(NSString *name)
{
	return [name hasSuffix:@".dmn"] || [name hasSuffix:@".dmn11.xml"];
}

NSDictionary<NSString *, WFFormDefinition *> *
WFFormsOf(WFProcessDefinition *definition)
{
	NSMutableDictionary *forms = [NSMutableDictionary dictionary];
	for (WFFlowNode *node in [definition.nodes allValues]) {
		if (node.form != nil) {
			[forms setObject:node.form forKey:node.elementId];
		}
		if ([node isKindOfClass:[WFSubProcess class]]) {
			[forms addEntriesFromDictionary:WFFormsOf([(WFSubProcess *)node innerDefinition])];
		}
	}
	return forms;
}

static NSError *
WFDeploymentError(NSString *elementId, NSString *message)
{
	NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
	if (elementId != nil) {
		[info setObject:elementId forKey:WFErrorElementIdKey];
	}
	return [NSError errorWithDomain:WFErrorDomain code:WFErrorInvalidDefinition userInfo:info];
}

NSArray<NSError *> *
WFDeploymentRefusals(WFProcessDefinition *definition, NSDictionary<NSString *, NSData *> *resources)
{
	NSMutableArray *refusals = [NSMutableArray array];
	NSDictionary *forms = WFFormsOf(definition);
	for (NSString *activityId in [[forms allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSString *resource = [[forms objectForKey:activityId] deploymentResourceName];
		if (resource == nil) {
			continue;
		}
		NSData *bytes = [resources objectForKey:resource];
		NSXMLDocument *document = bytes != nil ? [[NSXMLDocument alloc] initWithData:bytes options:0 error:NULL] : nil;
		if (document == nil) {
			[refusals addObject:WFDeploymentError(activityId, [NSString stringWithFormat:@"%@: form %@ is %@ the deployment",
				activityId, resource, bytes == nil ? @"not in" : @"not an XML document in"])];
		}
	}
	WFEvent *start = [definition startEvent];
	if (start.trigger == WFEventTriggerTimer) {
		/* Evaluated at deployment, where there are no variables. */
		NSDate *due = nil;
		NSString *repeat = nil;
		NSError *timerError = nil;
		if (!WFTimerSchedule(start.timer, @{}, [NSDate date], &due, &repeat, &timerError)) {
			[refusals addObject:WFDeploymentError(start.elementId, [NSString stringWithFormat:@"%@: %@", start.elementId,
				[timerError localizedDescription]])];
		}
	}
	return refusals;
}

NSString *
WFElementIdOfMessage(NSString *message)
{
	NSRange colon = [message rangeOfString:@": "];
	if (colon.location == NSNotFound || colon.location == 0) {
		return nil;
	}
	NSString *head = [message substringToIndex:colon.location];
	return [head rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound
		? head : nil;
}

NSError *
WFErrorNamingElement(NSError *error)
{
	if (error == nil || [[error userInfo] objectForKey:WFErrorElementIdKey] != nil) {
		return error;
	}
	NSString *elementId = WFElementIdOfMessage([error localizedDescription]);
	if (elementId == nil) {
		return error;
	}
	NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:[error userInfo] ?: @{}];
	[info setObject:elementId forKey:WFErrorElementIdKey];
	return [NSError errorWithDomain:[error domain] code:[error code] userInfo:info];
}

@interface WFProblem ()
@property (nonatomic, readwrite, copy) NSString *resourceName;
@property (nonatomic, readwrite, copy) NSString *elementId;
@property (nonatomic, readwrite, copy) NSString *message;
@property (nonatomic, readwrite) NSUInteger line;
@property (nonatomic, readwrite) NSUInteger column;
@end

@implementation WFProblem

+ (instancetype)problemWithMessage:(NSString *)message
{
	WFProblem *problem = [[self alloc] init];
	problem.message = message;
	return problem;
}

- (NSString *)description
{
	NSMutableString *text = [NSMutableString stringWithString:self.resourceName ?: @"deployment"];
	if (self.line > 0) {
		[text appendFormat:@":%lu:%lu", (unsigned long)self.line, (unsigned long)self.column];
	}
	[text appendFormat:@": error: %@", self.message];
	return text;
}

@end

/* Where the element of the id starts in the text: the "<" of the tag
 * that has it as its id. */
static void
WFLocate(NSString *text, NSString *elementId, NSUInteger *line, NSUInteger *column)
{
	*line = 0;
	*column = 0;
	if (text == nil || elementId == nil) {
		return;
	}
	NSString *pattern = [NSString stringWithFormat:@"\\sid\\s*=\\s*[\"']%@[\"']",
		[NSRegularExpression escapedPatternForString:elementId]];
	NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
	NSTextCheckingResult *match = [expression firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
	if (match == nil) {
		return;
	}
	NSRange tag = [text rangeOfString:@"<" options:NSBackwardsSearch range:NSMakeRange(0, [match range].location)];
	NSUInteger at = tag.location != NSNotFound ? tag.location : [match range].location;
	NSUInteger lines = 1, start = 0;
	for (NSUInteger i = 0; i < at; i++) {
		if ([text characterAtIndex:i] == '\n') {
			lines++;
			start = i + 1;
		}
	}
	*line = lines;
	*column = at - start + 1;
}

static NSString *
WFTextOf(NSData *data)
{
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
		?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

/* By where they are in the file, those not found last. */
static NSInteger
WFByPlace(id a, id b, void *context)
{
	WFProblem *p = a, *q = b;
	NSUInteger lp = p.line == 0 ? NSUIntegerMax : p.line, lq = q.line == 0 ? NSUIntegerMax : q.line;
	if (lp != lq) {
		return lp < lq ? NSOrderedAscending : NSOrderedDescending;
	}
	return p.column < q.column ? NSOrderedAscending : p.column > q.column ? NSOrderedDescending : NSOrderedSame;
}

@implementation WFDeploymentChecker

+ (void)add:(NSError *)error resource:(NSString *)name text:(NSString *)text to:(NSMutableArray *)problems
{
	error = WFErrorNamingElement(error);
	WFProblem *problem = [[WFProblem alloc] init];
	problem.resourceName = name;
	problem.elementId = [[error userInfo] objectForKey:WFErrorElementIdKey];
	problem.message = [error localizedDescription] ?: @"cannot be deployed";
	NSUInteger line = 0, column = 0;
	WFLocate(text, problem.elementId, &line, &column);
	problem.line = line;
	problem.column = column;
	[problems addObject:problem];
}

+ (NSArray<WFProblem *> *)problemsInResources:(NSDictionary<NSString *, NSData *> *)resources
{
	NSMutableArray *problems = [NSMutableArray array];
	NSMutableSet *processKeys = [NSMutableSet set], *decisionKeys = [NSMutableSet set];
	for (NSString *name in [[resources allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSData *data = [resources objectForKey:name];
		if (WFIsBpmnResource(name)) {
			NSString *text = WFTextOf(data);
			NSMutableArray *found = [NSMutableArray array];
			NSArray *definitions = [WFBpmnReader definitionsFromData:data problems:found];
			/* The model's forms and flows its tasks are done with: imported,
			 * and beside it. */
			[found addObjectsFromArray:[WFModelForms problemsOfProcess:data resources:resources]];
			for (WFProcessDefinition *definition in definitions) {
				[found addObjectsFromArray:WFDeploymentRefusals(definition, resources)];
				if ([processKeys containsObject:definition.processId]) {
					[found addObject:WFDeploymentError(definition.processId, [NSString stringWithFormat:
						@"process %@ is defined twice in one deployment", definition.processId])];
				}
				[processKeys addObject:definition.processId];
			}
			/* In the file's order. */
			NSMutableArray *located = [NSMutableArray array];
			for (NSError *error in found) {
				[self add:error resource:name text:text to:located];
			}
			[located sortUsingFunction:WFByPlace context:NULL];
			[problems addObjectsFromArray:located];
		} else if (WFIsDmnResource(name)) {
			NSError *error = nil;
			NSArray *decisions = [WFDmnReader decisionsFromData:data error:&error];
			if (decisions == nil) {
				[self add:error resource:name text:WFTextOf(data) to:problems];
				continue;
			}
			for (WFDecisionDefinition *decision in decisions) {
				if ([decisionKeys containsObject:decision.key]) {
					[self add:WFDeploymentError(decision.key, [NSString stringWithFormat:
						@"decision %@ is defined twice in one deployment", decision.key])
					 resource:name text:WFTextOf(data) to:problems];
				}
				[decisionKeys addObject:decision.key];
			}
		}
	}
	return problems;
}

@end
