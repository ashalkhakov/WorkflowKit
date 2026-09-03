#ifndef UDTypes_h
#define UDTypes_h

#import <Foundation/Foundation.h>

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
	UDEventTriggerError
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

typedef NS_ENUM(NSInteger, UDComparisonOp) {
	UDComparisonOpEqual = 0,
	UDComparisonOpNotEqual,
	UDComparisonOpGreater,
	UDComparisonOpGreaterOrEqual,
	UDComparisonOpLess,
	UDComparisonOpLessOrEqual
};

typedef NS_ENUM(NSInteger, UDWorkflowErrorCode) {
	UDWorkflowErrorInvalidDefinition = 1,
	UDWorkflowErrorUnknownElement,
	UDWorkflowErrorNoPath,
	UDWorkflowErrorCondition,
	UDWorkflowErrorHandler,
	UDWorkflowErrorInvalidState,
	UDWorkflowErrorInvalidBpmn
};

extern NSString * const UDWorkflowErrorDomain;
extern NSString * const UDWorkflowErrorRefKey;

#endif /* UDTypes_h */
