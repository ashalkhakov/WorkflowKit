/*
 * wf-build -- a deployment's directory built into what an application
 * ships: checked as deploying it would be, and written as
 * <name>.wfdeployment (WFBuiltDeployment.h), as momc builds a model.
 *
 *   wf-build Processes/orders                     # ./orders.wfdeployment
 *   wf-build -o build/orders.wfdeployment Processes/orders
 *   wf-build -name Orders -o Orders.wfdeployment Processes/orders
 *
 * Every problem is said on standard error as compilers say them --
 * Processes/orders/order.bpmn:12:5: error: ship: no outgoing flow -- and
 * nothing is written. It exits 0 when it wrote the deployment, 1 when the
 * deployment has problems, 2 when it was asked wrongly.
 */
#import <Foundation/Foundation.h>
#import "WorkflowKit.h"

static int
WFUsage(void)
{
	fprintf(stderr, "usage: wf-build [-name NAME] [-o OUTPUT.wfdeployment] DIRECTORY\n");
	return 2;
}

static void
WFSay(NSString *text)
{
	fprintf(stderr, "%s\n", [text UTF8String]);
}

int
main(int argc, const char *argv[])
{
	@autoreleasepool {
		NSString *name = nil, *output = nil, *directory = nil;
		NSArray *arguments = [[NSProcessInfo processInfo] arguments];
		for (NSUInteger i = 1; i < [arguments count]; i++) {
			NSString *argument = [arguments objectAtIndex:i];
			if (([argument isEqualToString:@"-name"] || [argument isEqualToString:@"-o"]) && i + 1 < [arguments count]) {
				NSString *value = [arguments objectAtIndex:++i];
				if ([argument isEqualToString:@"-name"]) {
					name = value;
				} else {
					output = value;
				}
			} else if ([argument hasPrefix:@"-"] || directory != nil) {
				return WFUsage();
			} else {
				directory = argument;
			}
		}
		if (directory == nil) {
			return WFUsage();
		}
		directory = [directory stringByStandardizingPath];
		name = name ?: [[directory lastPathComponent] stringByDeletingPathExtension];
		output = output ?: [name stringByAppendingPathExtension:WFBuiltDeploymentExtension];

		NSError *error = nil;
		NSDictionary *resources = [WFBuiltDeployment resourcesInDirectory:[NSURL fileURLWithPath:directory] error:&error];
		if (resources == nil) {
			WFSay([NSString stringWithFormat:@"wf-build: %@", [error localizedDescription]]);
			return 1;
		}
		NSArray<WFProblem *> *problems = nil;
		WFBuiltDeployment *deployment = [WFBuiltDeployment deploymentNamed:name resources:resources problems:&problems];
		for (WFProblem *problem in problems) {
			/* Its file by the path it was read from, for editors to open. */
			NSString *said = [problem description];
			if (problem.resourceName != nil) {
				said = [[directory stringByAppendingPathComponent:problem.resourceName]
					stringByAppendingString:[said substringFromIndex:[problem.resourceName length]]];
			}
			WFSay(said);
		}
		if (deployment == nil) {
			WFSay([NSString stringWithFormat:@"wf-build: %lu problem%s in %@; nothing written",
				(unsigned long)[problems count], [problems count] == 1 ? "" : "s", directory]);
			return 1;
		}
		if (![deployment writeToURL:[NSURL fileURLWithPath:output] error:&error]) {
			WFSay([NSString stringWithFormat:@"wf-build: %@ cannot be written: %@", output, [error localizedDescription]]);
			return 1;
		}
	}
	return 0;
}
