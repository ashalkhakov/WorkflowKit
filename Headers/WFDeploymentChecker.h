#import <Foundation/Foundation.h>

/* WorkflowKit's own: exported where it is built for Windows (the GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef WORKFLOWKIT_EXPORT
#define WORKFLOWKIT_EXPORT FOUNDATION_EXPORT
#endif

/* Something the engine would refuse a deployment for: in which resource,
 * about which element, where in the file it is. */
@interface WFProblem : NSObject
/* The resource it is in; nil for the deployment as a whole (a process
 * defined twice). */
@property (nonatomic, readonly, copy) NSString *resourceName;
/* The element it is about; nil for the resource as a whole. */
@property (nonatomic, readonly, copy) NSString *elementId;
/* What the engine says, as deploying would. */
@property (nonatomic, readonly, copy) NSString *message;
/* Where the element's start tag is in the resource, from 1; 0 when the
 * problem is not an element's or the element is not found. */
@property (nonatomic, readonly) NSUInteger line;
@property (nonatomic, readonly) NSUInteger column;
/* As compilers say it: "order.bpmn:12:5: error: ship: no outgoing flow". */
@property (nonatomic, readonly, copy) NSString *description;
@end

/*
 * What deploying the resources would find wrong, all of it, without a
 * store: each BPMN resource's processes read and checked, each DMN
 * resource's decisions, the forms the processes name, keys defined twice.
 * An empty list is a deployment the repository takes. For the designer's
 * problems and for building processes with an application (wf-build).
 */
@interface WFDeploymentChecker : NSObject
+ (NSArray<WFProblem *> *)problemsInResources:(NSDictionary<NSString *, NSData *> *)resources;
@end
