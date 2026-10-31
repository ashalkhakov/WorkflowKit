#import <AppKit/AppKit.h>
#import <DiagramKitUI/DKCanvasView.h>

@class WKDDiagram;

/*
 * A process's diagram as the operations window shows it: drawn as the
 * designer draws it (WKDRenderer), read only, with where instances are on
 * it laid over -- as Camunda's Cockpit shows a process, from the engine's
 * own history:
 *
 *  - an activity being run now is outlined in blue, with how many tokens
 *    are on it when there are more than one;
 *  - one that was run and finished is shaded green, and so are the flows
 *    between finished activities: the way the instance came;
 *  - one with an incident has a red badge with how many it has.
 *
 * It fits itself to its area when given a new diagram. A click on an
 * activity names it, through the clicked block.
 *
 * A DiagramKit canvas, its own data source and delegate: it zooms
 * (Command-scroll), pans (Space-drag, the middle button), exports (PDF, PNG)
 * and prints as DKCanvasView does; a click names what is under it rather
 * than selecting it.
 */
@interface WDDiagramView : DKCanvasView <DKCanvasDataSource, DKCanvasDelegate>

@property (nonatomic, strong) WKDDiagram *diagram;
/* Tokens on each activity now, by its id. */
@property (nonatomic, copy) NSCountedSet<NSString *> *active;
/* The activities run and finished. */
@property (nonatomic, copy) NSSet<NSString *> *finished;
/* Incidents on each activity, by its id. */
@property (nonatomic, copy) NSCountedSet<NSString *> *incidents;
/* What is shown when there is no diagram: why. */
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, copy) void (^clicked)(NSString *activityId);

/* The marks laid over, all at once. */
- (void)setActive:(NSCountedSet<NSString *> *)active
         finished:(NSSet<NSString *> *)finished
        incidents:(NSCountedSet<NSString *> *)incidents;
/* The whole diagram in the visible area, at actual size at most. */
- (void)zoomToFit;

@end
