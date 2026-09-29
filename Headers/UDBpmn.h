#ifndef UDBpmn_h
#define UDBpmn_h

#import "UDProcessDefinition.h"

extern NSString * const UDBpmnNamespace;
extern NSString * const UDBpmnDINamespace;
extern NSString * const UDBpmnDCNamespace;
extern NSString * const UDBpmnDINodesNamespace;
/* Camunda's extension namespace: the attributes BPMN has no place for
 * (assignee, external task topic, async continuations) are read and written
 * here, so files from Camunda Modeler run as they are. */
extern NSString * const UDCamundaNamespace;
/* Our own extensions, only where Camunda has no equivalent. */
extern NSString * const UDBpmnExtensionNamespace;
/* The expressionLanguage URI for FEEL. */
extern NSString * const UDFeelLanguage;

/*
 * Writes standard BPMN 2.0 XML: top-level message and error definitions,
 * ISO-8601 timer durations, FEEL conditions, embedded subprocesses in
 * place, and BPMN DI shapes and edges for nodes that have bounds.
 */
@interface UDBpmnWriter : NSObject
+ (NSString *)XMLStringFromDefinition:(UDProcessDefinition *)definition
                                error:(NSError **)error;
+ (BOOL)writeDefinition:(UDProcessDefinition *)definition
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
@interface UDBpmnReader : NSObject
/* Every executable process in the document, in document order. */
+ (NSArray<UDProcessDefinition *> *)definitionsFromData:(NSData *)data
                                                  error:(NSError **)error;
/* The document's first executable process. */
+ (UDProcessDefinition *)definitionFromXMLString:(NSString *)xml
                                           error:(NSError **)error;
+ (UDProcessDefinition *)definitionFromURL:(NSURL *)url
                                     error:(NSError **)error;
@end

#endif /* UDBpmn_h */
