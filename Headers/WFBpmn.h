#import "WFProcessDefinition.h"

extern NSString * const WFBpmnNamespace;
extern NSString * const WFBpmnDINamespace;
extern NSString * const WFBpmnDCNamespace;
extern NSString * const WFBpmnDINodesNamespace;
/* Camunda's extension namespace: the attributes BPMN has no place for
 * (assignee, external task topic, async continuations) are read and written
 * here, so files from Camunda Modeler run as they are. */
extern NSString * const WFCamundaNamespace;
/* Our own extensions, only where Camunda has no equivalent. */
extern NSString * const WFBpmnExtensionNamespace;
/* The expressionLanguage URI for FEEL. */
extern NSString * const WFFeelLanguage;

/*
 * Writes standard BPMN 2.0 XML: top-level message and error definitions,
 * ISO-8601 timer durations, FEEL conditions, embedded subprocesses in
 * place, and BPMN DI shapes and edges for nodes that have bounds.
 */
@interface WFBpmnWriter : NSObject
+ (NSString *)XMLStringFromDefinition:(WFProcessDefinition *)definition
                                error:(NSError **)error;
+ (BOOL)writeDefinition:(WFProcessDefinition *)definition
                  toURL:(NSURL *)url
                  error:(NSError **)error;
@end

/*
 * Reads BPMN 2.0 XML into definitions. Elements the engine does not run --
 * multi-instance, event subprocesses and the rest of the subset's
 * out-of-scope list -- fail the read with an error naming them,
 * rather than being dropped. Documentation, extension elements, lanes,
 * annotations and data objects are ignored.
 */
@interface WFBpmnReader : NSObject
/* Every executable process in the document, in document order. */
+ (NSArray<WFProcessDefinition *> *)definitionsFromData:(NSData *)data
                                                  error:(NSError **)error;
/* The document's first executable process. */
+ (WFProcessDefinition *)definitionFromXMLString:(NSString *)xml
                                           error:(NSError **)error;
+ (WFProcessDefinition *)definitionFromURL:(NSURL *)url
                                     error:(NSError **)error;
@end
