#import <Foundation/Foundation.h>

/* WorkflowKit's own: exported where it is built for Windows (the GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef WORKFLOWKIT_EXPORT
#define WORKFLOWKIT_EXPORT FOUNDATION_EXPORT
#endif
#import <dispatch/dispatch.h>

/*
 * Dispatch objects are Objective-C objects only where libdispatch was built
 * with OS object support (Apple). On GNUstep they are plain C pointers that
 * ARC does not manage, so properties holding them are `assign` with setters
 * that retain, and whoever owns one releases it.
 */
#if OS_OBJECT_USE_OBJC
#define WF_DISPATCH_PROPERTY strong
#define WFDispatchRetain(object) ((void)(object))
#define WFDispatchRelease(object) do { } while (0)
#else
#define WF_DISPATCH_PROPERTY assign
#define WFDispatchRetain(object) dispatch_retain(object)
#define WFDispatchRelease(object) dispatch_release(object)
#endif

typedef NS_ENUM(NSInteger, WFEventKind) {
	WFEventKindStart = 0,
	WFEventKindEnd,
	WFEventKindIntermediateCatch,
	WFEventKindIntermediateThrow,
	WFEventKindBoundary
};

typedef NS_ENUM(NSInteger, WFEventTrigger) {
	WFEventTriggerNone = 0,
	WFEventTriggerMessage,
	WFEventTriggerTimer,
	WFEventTriggerError,
	/* A broadcast, delivered to every waiting catcher. */
	WFEventTriggerSignal,
	/* A terminate end event: its scope ends at once. */
	WFEventTriggerTerminate,
	/* Like an error, but not critical: uncaught, the thrower goes on. */
	WFEventTriggerEscalation,
	/* Runs the compensation handlers of completed activities. */
	WFEventTriggerCompensation,
	/* A jump: a link throw event goes on at the link catch event of the
	 * same name in its scope. */
	WFEventTriggerLink,
	/* Fires when a condition over the variables holds. */
	WFEventTriggerConditional
};

typedef NS_ENUM(NSInteger, WFTaskKind) {
	WFTaskKindUser = 0,
	/* Service, send and business rule tasks run as external tasks. */
	WFTaskKindService,
	WFTaskKindScript,
	WFTaskKindSend,
	WFTaskKindBusinessRule,
	/* Waits for a message, as a message catch event does. */
	WFTaskKindReceive,
	/* Manual tasks and plain tasks are passed through. */
	WFTaskKindManual,
	WFTaskKindNone
};

typedef NS_ENUM(NSInteger, WFGatewayKind) {
	WFGatewayKindExclusive = 0,
	WFGatewayKindParallel,
	WFGatewayKindInclusive,
	WFGatewayKindEventBased
};

typedef NS_ENUM(NSInteger, WFTokenState) {
	WFTokenStateReady = 0,
	WFTokenStateWaiting,
	WFTokenStateCompleted
};

typedef NS_ENUM(NSInteger, WFErrorCode) {
	WFErrorInvalidDefinition = 1,
	WFErrorUnknownElement,
	WFErrorNoPath,
	WFErrorCondition,
	WFErrorHandler,
	WFErrorInvalidState,
	WFErrorInvalidBpmn,
	/* Another command changed the same instance first; nothing was
	 * committed, and the call can be retried. */
	WFErrorConflict,
	/* The process instance, or its definition, is suspended. */
	WFErrorSuspended,
	/* A DMN resource the engine cannot read. */
	WFErrorInvalidDmn,
	/* A decision could not be evaluated: an input or output that is not
	 * of its type, several rules where one may match. */
	WFErrorDecision,
	/* A query condition the engine cannot evaluate: an operator the value
	 * has no order for, a value of a type variables do not hold. */
	WFErrorInvalidQuery,
	/* Values a form does not take: of another type, missing where
	 * required, outside its constraints. */
	WFErrorInvalidFormData
};

WORKFLOWKIT_EXPORT NSString * const WFErrorDomain;
/* In an error about text -- an expression the engine cannot read --
 * where in the text, as an NSValue holding an NSRange. */
WORKFLOWKIT_EXPORT NSString * const WFErrorRangeKey;
WORKFLOWKIT_EXPORT NSString * const WFErrorRefKey;
