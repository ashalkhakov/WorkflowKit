#import "WFProcessDefinition.h"
#import "WFBpmn.h"

/* What deploying and checking a deployment share: which resources are
 * what, every problem the reader finds, and what a deployment is refused
 * for once its processes are read. */

BOOL WFIsBpmnResource(NSString *name);
BOOL WFIsDmnResource(NSString *name);

/* The forms of a definition's nodes, and of the nodes of the subprocesses
 * in it, by activity id. */
NSDictionary<NSString *, WFFormDefinition *> *WFFormsOf(WFProcessDefinition *definition);

/* Why a deployment of the resources is refused for the definition read
 * from them: a form it names that is not there, or not XML; a timer start
 * that cannot be scheduled. Empty when it is not. */
NSArray<NSError *> *WFDeploymentRefusals(WFProcessDefinition *definition, NSDictionary<NSString *, NSData *> *resources);

/* The element an error is about, by the engine's way of saying it -- "id:
 * what is wrong" -- when its userInfo does not name one already. */
NSString *WFElementIdOfMessage(NSString *message);
NSError *WFErrorNamingElement(NSError *error);

@interface WFDefinitionBuilder (WFCollecting)
/* The definition, or nil with every problem found added to problems: what
 * was added wrongly, and every node's first problem, the unread elements
 * and what follows from their absence aside. */
- (WFProcessDefinition *)buildCollecting:(NSMutableArray<NSError *> *)problems unread:(NSSet<NSString *> *)unread;
@end

@interface WFBpmnReader (WFCollecting)
/* The executable processes read without a problem, and every problem
 * found in the document, each naming its element where it has one. */
+ (NSArray<WFProcessDefinition *> *)definitionsFromData:(NSData *)data problems:(NSMutableArray<NSError *> *)problems;
@end
