#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

/*
 * Dispatch objects are Objective-C objects only where libdispatch was built
 * with OS object support (Apple). On GNUstep they are plain C pointers that
 * ARC does not manage, so properties holding them are `assign` with setters
 * that retain, and whoever owns one releases it.
 */
#if OS_OBJECT_USE_OBJC
#define UD_DISPATCH_PROPERTY strong
#define UDDispatchRetain(object) ((void)(object))
#define UDDispatchRelease(object) do { } while (0)
#else
#define UD_DISPATCH_PROPERTY assign
#define UDDispatchRetain(object) dispatch_retain(object)
#define UDDispatchRelease(object) dispatch_release(object)
#endif

typedef NS_ENUM(NSInteger, UDEventKind) {
	UDEventKindStart = 0,
	UDEventKindEnd,
	UDEventKindIntermediateCatch,
	UDEventKindIntermediateThrow,
	UDEventKindBoundary
};

typedef NS_ENUM(NSInteger, UDEventTrigger) {
	UDEventTriggerNone = 0,
	UDEventTriggerMessage,
	UDEventTriggerTimer,
	UDEventTriggerError,
	/* A broadcast, delivered to every waiting catcher. */
	UDEventTriggerSignal,
	/* A terminate end event: its scope ends at once. */
	UDEventTriggerTerminate
};

typedef NS_ENUM(NSInteger, UDTaskKind) {
	UDTaskKindUser = 0,
	UDTaskKindService,
	UDTaskKindScript
};

typedef NS_ENUM(NSInteger, UDGatewayKind) {
	UDGatewayKindExclusive = 0,
	UDGatewayKindParallel,
	UDGatewayKindInclusive,
	UDGatewayKindEventBased
};

typedef NS_ENUM(NSInteger, UDTokenState) {
	UDTokenStateReady = 0,
	UDTokenStateWaiting,
	UDTokenStateCompleted
};

typedef NS_ENUM(NSInteger, UDWorkflowErrorCode) {
	UDWorkflowErrorInvalidDefinition = 1,
	UDWorkflowErrorUnknownElement,
	UDWorkflowErrorNoPath,
	UDWorkflowErrorCondition,
	UDWorkflowErrorHandler,
	UDWorkflowErrorInvalidState,
	UDWorkflowErrorInvalidBpmn,
	/* Another command changed the same instance first; nothing was
	 * committed, and the call can be retried. */
	UDWorkflowErrorConflict
};

extern NSString * const UDWorkflowErrorDomain;
extern NSString * const UDWorkflowErrorRefKey;
