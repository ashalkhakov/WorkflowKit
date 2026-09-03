#ifndef UDBpmn_h
#define UDBpmn_h

#import "UDProcessDefinition.h"

extern NSString * const UDBpmnNamespace;
extern NSString * const UDBpmnExtensionNamespace;

@interface UDBpmnWriter : NSObject
+ (NSString *)XMLStringFromDefinition:(UDProcessDefinition *)definition
                                error:(NSError **)error;
+ (BOOL)writeDefinition:(UDProcessDefinition *)definition
                  toURL:(NSURL *)url
                  error:(NSError **)error;
@end

@interface UDBpmnReader : NSObject
+ (UDProcessDefinition *)definitionFromXMLString:(NSString *)xml
                                           error:(NSError **)error;
+ (UDProcessDefinition *)definitionFromURL:(NSURL *)url
                                     error:(NSError **)error;
@end

#endif /* UDBpmn_h */
