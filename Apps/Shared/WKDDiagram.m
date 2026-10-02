#import "WKDDiagram.h"
#import "WKDXML.h"

WKDShapeKind
WKDKindOfType(NSString *type, BOOL *isFlowNode)
{
	static NSDictionary *kinds;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableDictionary *table = [NSMutableDictionary dictionary];
		for (NSString *name in @[ @"startEvent", @"endEvent", @"intermediateCatchEvent", @"intermediateThrowEvent",
		                          @"boundaryEvent" ]) {
			[table setObject:@(WKDShapeEvent) forKey:name];
		}
		for (NSString *name in @[ @"task", @"userTask", @"serviceTask", @"scriptTask", @"sendTask", @"receiveTask",
		                          @"manualTask", @"businessRuleTask", @"callActivity", @"subProcess",
		                          @"transaction", @"adHocSubProcess" ]) {
			[table setObject:@(WKDShapeActivity) forKey:name];
		}
		for (NSString *name in @[ @"exclusiveGateway", @"parallelGateway", @"inclusiveGateway",
		                          @"eventBasedGateway", @"complexGateway" ]) {
			[table setObject:@(WKDShapeGateway) forKey:name];
		}
		for (NSString *name in @[ @"textAnnotation", @"dataObjectReference", @"dataStoreReference" ]) {
			[table setObject:@(WKDShapeArtifact) forKey:name];
		}
		kinds = table;
	});
	NSNumber *kind = [kinds objectForKey:type];
	if (isFlowNode != NULL) {
		*isFlowNode = kind != nil;
	}
	return kind != nil ? (WKDShapeKind)[kind integerValue] : WKDShapeArtifact;
}

BOOL
WKDIsContainerType(NSString *type)
{
	return [type isEqualToString:@"subProcess"] || [type isEqualToString:@"transaction"]
		|| [type isEqualToString:@"adHocSubProcess"];
}

NSRect
WKDNodeLabelRect(NSString *type, NSRect rect)
{
	WKDShapeKind kind = WKDKindOfType(type, NULL);
	if (kind != WKDShapeEvent && kind != WKDShapeGateway) {
		return NSZeroRect;
	}
	return NSMakeRect(NSMidX(rect) - 50, NSMaxY(rect) + 2, 100, 30);
}

NSRect
WKDFlowLabelRect(NSArray<NSValue *> *points)
{
	if ([points count] < 2) {
		return NSZeroRect;
	}
	NSUInteger middle = ([points count] - 1) / 2;
	NSPoint a = [[points objectAtIndex:middle] pointValue], b = [[points objectAtIndex:middle + 1] pointValue];
	return NSMakeRect((a.x + b.x) / 2 - 50, (a.y + b.y) / 2 - 20, 100, 18);
}

@interface WKDShape ()
@property (nonatomic, readwrite, strong) NSXMLElement *element;
@property (nonatomic, readwrite, copy) NSString *elementId;
@property (nonatomic, readwrite, copy) NSString *type;
@property (nonatomic, readwrite) WKDShapeKind kind;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite) NSRect bounds;
@property (nonatomic, readwrite) BOOL hasBounds;
@property (nonatomic, readwrite, weak) WKDShape *parent;
@property (nonatomic, readwrite, weak) WKDShape *host;
@property (nonatomic, readwrite, copy) NSString *eventDefinition;
@property (nonatomic, readwrite) BOOL interrupting;
@property (nonatomic, readwrite) BOOL eventSubProcess;
@property (nonatomic, readwrite, copy) NSString *loop;
@property (nonatomic, readwrite) NSRect labelBounds;
@end

@implementation WKDShape

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %@ %@>", self.type, self.elementId, NSStringFromRect(self.bounds)];
}

@end

@interface WKDConnection ()
@property (nonatomic, readwrite, strong) NSXMLElement *element;
@property (nonatomic, readwrite, copy) NSString *elementId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, weak) WKDShape *source;
@property (nonatomic, readwrite, weak) WKDShape *target;
@property (nonatomic, readwrite, copy) NSArray<NSValue *> *waypoints;
@property (nonatomic, readwrite) BOOL isDefault;
@property (nonatomic, readwrite) BOOL hasCondition;
@property (nonatomic, readwrite) BOOL isAssociation;
@property (nonatomic, readwrite) NSRect labelBounds;
@end

@implementation WKDConnection
@end

@interface WKDDiagram ()
@property (nonatomic, readwrite, strong) NSXMLElement *process;
@property (nonatomic, readwrite, strong) NSXMLElement *plane;
@property (nonatomic, readwrite, copy) NSArray<WKDShape *> *shapes;
@property (nonatomic, readwrite, copy) NSArray<WKDConnection *> *connections;
@end

/* A BPMNShape's or BPMNEdge's label's bounds, as NSValue; nil for none. */
static NSValue *
WKDLabelBoundsOf(NSXMLElement *diagramElement)
{
	NSXMLElement *label = WKDChild(diagramElement, WKDBpmnDINamespace, @"BPMNLabel");
	NSXMLElement *box = label != nil ? WKDChild(label, WKDDCNamespace, @"Bounds") : nil;
	if (box == nil) {
		return nil;
	}
	return [NSValue valueWithRect:NSMakeRect(WKDNumber(box, @"x"), WKDNumber(box, @"y"),
	                                         WKDNumber(box, @"width"), WKDNumber(box, @"height"))];
}

/* A point as NSValue: the two platforms box it differently. */
static NSValue *
WKDPointValue(double x, double y)
{
	return [NSValue valueWithPoint:NSMakePoint(x, y)];
}

@implementation WKDDiagram
{
	NSMutableDictionary<NSString *, WKDShape *> *_shapesById;
	NSMutableDictionary<NSString *, WKDConnection *> *_connectionsById;
}

+ (instancetype)diagramOfDocument:(NSXMLDocument *)document
{
	WKDDiagram *diagram = [[self alloc] init];
	[diagram read:document];
	return diagram;
}

- (void)read:(NSXMLDocument *)document
{
	NSXMLElement *root = [document rootElement];
	NSArray *processes = WKDChildren(root, WKDBpmnNamespace, @"process");
	for (NSXMLElement *process in processes) {
		if ([WKDAttribute(process, @"isExecutable") isEqualToString:@"true"]) {
			_process = process;
			break;
		}
	}
	if (_process == nil) {
		_process = [processes firstObject];
	}
	/* The diagram: the plane that shows the process, else the first one
	 * (a collaboration's, whose shapes name the process's elements). */
	NSString *processId = WKDAttribute(_process, @"id");
	NSArray *planes = WKDDescendants(root, WKDBpmnDINamespace, @"BPMNPlane");
	for (NSXMLElement *plane in planes) {
		if ([WKDAttribute(plane, @"bpmnElement") isEqualToString:processId]) {
			_plane = plane;
		}
	}
	if (_plane == nil) {
		_plane = [planes firstObject];
	}
	NSMutableDictionary *bounds = [NSMutableDictionary dictionary];
	NSMutableDictionary *edges = [NSMutableDictionary dictionary];
	NSMutableDictionary *labels = [NSMutableDictionary dictionary];
	for (NSXMLElement *plane in planes) {
		for (NSXMLElement *shape in WKDChildren(plane, WKDBpmnDINamespace, @"BPMNShape")) {
			NSXMLElement *box = WKDChild(shape, WKDDCNamespace, @"Bounds");
			NSString *ref = WKDAttribute(shape, @"bpmnElement");
			if (ref != nil && WKDLabelBoundsOf(shape) != nil) {
				[labels setObject:WKDLabelBoundsOf(shape) forKey:ref];
			}
			if (box != nil && ref != nil) {
				[bounds setObject:[NSValue valueWithRect:NSMakeRect(WKDNumber(box, @"x"), WKDNumber(box, @"y"),
					WKDNumber(box, @"width"), WKDNumber(box, @"height"))] forKey:ref];
			}
		}
		for (NSXMLElement *edge in WKDChildren(plane, WKDBpmnDINamespace, @"BPMNEdge")) {
			NSString *ref = WKDAttribute(edge, @"bpmnElement");
			NSMutableArray *points = [NSMutableArray array];
			for (NSXMLElement *waypoint in WKDChildren(edge, WKDDINamespace, @"waypoint")) {
				[points addObject:WKDPointValue(WKDNumber(waypoint, @"x"), WKDNumber(waypoint, @"y"))];
			}
			if (ref != nil && [points count] >= 2) {
				[edges setObject:points forKey:ref];
			}
			if (ref != nil && WKDLabelBoundsOf(edge) != nil) {
				[labels setObject:WKDLabelBoundsOf(edge) forKey:ref];
			}
		}
	}

	_shapesById = [NSMutableDictionary dictionary];
	_connectionsById = [NSMutableDictionary dictionary];
	NSMutableArray *shapes = [NSMutableArray array];
	NSMutableArray *flows = [NSMutableArray array];
	[self readContainer:_process parent:nil bounds:bounds shapes:shapes flows:flows];
	for (WKDShape *shape in shapes) {
		NSValue *label = [labels objectForKey:shape.elementId];
		shape.labelBounds = label != nil ? [label rectValue] : NSZeroRect;
	}
	/* Boundary events once every activity is known. */
	for (WKDShape *shape in shapes) {
		NSString *host = WKDAttribute(shape.element, @"attachedToRef");
		if (host != nil) {
			shape.host = [_shapesById objectForKey:host];
		}
	}
	_shapes = shapes;

	NSMutableArray *connections = [NSMutableArray array];
	for (NSXMLElement *flow in flows) {
		WKDConnection *connection = [[WKDConnection alloc] init];
		connection.element = flow;
		connection.elementId = WKDAttribute(flow, @"id");
		connection.name = WKDAttribute(flow, @"name");
		connection.source = [_shapesById objectForKey:WKDAttribute(flow, @"sourceRef") ?: @""];
		connection.target = [_shapesById objectForKey:WKDAttribute(flow, @"targetRef") ?: @""];
		if (connection.elementId == nil || connection.source == nil || connection.target == nil) {
			continue;
		}
		connection.isAssociation = [[flow localName] isEqualToString:@"association"];
		connection.hasCondition = WKDChild(flow, WKDBpmnNamespace, @"conditionExpression") != nil;
		connection.isDefault = [WKDAttribute(connection.source.element, @"default") isEqualToString:connection.elementId];
		NSArray *points = [edges objectForKey:connection.elementId];
		if (points == nil && connection.source.hasBounds && connection.target.hasBounds) {
			NSRect from = connection.source.bounds, to = connection.target.bounds;
			points = @[ WKDPointValue(NSMidX(from), NSMidY(from)), WKDPointValue(NSMidX(to), NSMidY(to)) ];
		}
		connection.waypoints = points ?: @[];
		NSValue *label = [labels objectForKey:connection.elementId];
		connection.labelBounds = label != nil ? [label rectValue] : NSZeroRect;
		[connections addObject:connection];
		[_connectionsById setObject:connection forKey:connection.elementId];
	}
	_connections = connections;
}

- (void)readContainer:(NSXMLElement *)container
               parent:(WKDShape *)parent
               bounds:(NSDictionary *)bounds
               shapes:(NSMutableArray *)shapes
                flows:(NSMutableArray *)flows
{
	for (NSXMLNode *node in [container children]) {
		if (!WKDIs(node, WKDBpmnNamespace, nil)) {
			continue;
		}
		NSXMLElement *element = (NSXMLElement *)node;
		NSString *type = [element localName];
		if ([type isEqualToString:@"sequenceFlow"] || [type isEqualToString:@"association"]) {
			[flows addObject:element];
			continue;
		}
		BOOL flowNode = NO;
		WKDShapeKind kind = WKDKindOfType(type, &flowNode);
		NSString *elementId = WKDAttribute(element, @"id");
		if (!flowNode || elementId == nil) {
			continue;
		}
		WKDShape *shape = [[WKDShape alloc] init];
		shape.element = element;
		shape.elementId = elementId;
		shape.type = type;
		shape.kind = kind;
		shape.name = WKDAttribute(element, @"name");
		if ([type isEqualToString:@"textAnnotation"]) {
			shape.name = [WKDChild(element, WKDBpmnNamespace, @"text") stringValue];
		}
		shape.parent = parent;
		NSValue *box = [bounds objectForKey:elementId];
		shape.hasBounds = box != nil;
		shape.bounds = box != nil ? [box rectValue] : NSZeroRect;
		for (NSXMLElement *child in WKDChildren(element, WKDBpmnNamespace, nil)) {
			if ([[child localName] hasSuffix:@"EventDefinition"]) {
				shape.eventDefinition = [child localName];
				break;
			}
		}
		NSString *interrupting = WKDAttribute(element, @"cancelActivity") ?: WKDAttribute(element, @"isInterrupting");
		shape.interrupting = ![interrupting isEqualToString:@"false"];
		shape.eventSubProcess = [WKDAttribute(element, @"triggeredByEvent") isEqualToString:@"true"];
		NSXMLElement *loop = WKDChild(element, WKDBpmnNamespace, @"multiInstanceLoopCharacteristics");
		if (loop != nil) {
			shape.loop = [WKDAttribute(loop, @"isSequential") isEqualToString:@"true"] ? @"sequential" : @"parallel";
		} else if (WKDChild(element, WKDBpmnNamespace, @"standardLoopCharacteristics") != nil) {
			shape.loop = @"standard";
		}
		[shapes addObject:shape];
		[_shapesById setObject:shape forKey:elementId];
		if (WKDIsContainerType(type)) {
			[self readContainer:element parent:shape bounds:bounds shapes:shapes flows:flows];
		}
	}
}

- (WKDShape *)shapeWithId:(NSString *)elementId
{
	return elementId != nil ? [_shapesById objectForKey:elementId] : nil;
}

- (WKDConnection *)connectionWithId:(NSString *)elementId
{
	return elementId != nil ? [_connectionsById objectForKey:elementId] : nil;
}

- (NSArray<WKDConnection *> *)connectionsOf:(WKDShape *)shape
{
	NSMutableArray *found = [NSMutableArray array];
	for (WKDConnection *connection in _connections) {
		if (connection.source == shape || connection.target == shape) {
			[found addObject:connection];
		}
	}
	return found;
}

- (NSArray<WKDShape *> *)shapesIn:(WKDShape *)container
{
	NSMutableArray *found = [NSMutableArray array];
	for (WKDShape *shape in _shapes) {
		if (shape.parent == container && shape.host == nil) {
			[found addObject:shape];
		}
	}
	return found;
}

- (BOOL)needsLayout
{
	for (WKDShape *shape in _shapes) {
		if (!shape.hasBounds && shape.kind != WKDShapeArtifact) {
			return YES;
		}
	}
	return NO;
}

- (NSRect)contentBounds
{
	NSRect all = NSZeroRect;
	for (WKDShape *shape in _shapes) {
		if (shape.hasBounds) {
			all = NSIsEmptyRect(all) ? shape.bounds : NSUnionRect(all, shape.bounds);
		}
	}
	for (WKDConnection *connection in _connections) {
		for (NSValue *point in connection.waypoints) {
			NSPoint p = [point pointValue];
			NSRect dot = NSMakeRect(p.x, p.y, 1, 1);
			all = NSIsEmptyRect(all) ? dot : NSUnionRect(all, dot);
		}
	}
	return all;
}

@end
