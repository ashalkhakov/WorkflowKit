#import <Foundation/Foundation.h>
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
	WFEventTriggerCompensation
};

typedef NS_ENUM(NSInteger, WFTaskKind) {
	WFTaskKindUser = 0,
	WFTaskKindService,
	WFTaskKindScript
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
	WFErrorConflict
};

extern NSString * const WFErrorDomain;
extern NSString * const WFErrorRefKey;
