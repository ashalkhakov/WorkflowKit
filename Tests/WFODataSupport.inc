/* Requests to an engine's OData service, for the classes that test it:
 * included by each OData area's .inc (see WFTestCase.h). */

/* The status and the JSON of a request to the service. */
- (NSDictionary *)send:(NSString *)method
                  path:(NSString *)path
                  body:(id)body
               service:(ODataService *)service
{
	return [self send:method path:path body:body headers:nil service:service];
}

- (NSDictionary *)send:(NSString *)method
                  path:(NSString *)path
                  body:(id)body
               headers:(NSDictionary *)headers
               service:(ODataService *)service
{
	NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:
		[NSCharacterSet URLQueryAllowedCharacterSet]];
	NSURL *url = [NSURL URLWithString:[@"http://example.test/api/" stringByAppendingString:encoded]];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setHTTPMethod:method];
	for (NSString *name in headers) {
		[request setValue:[headers objectForKey:name] forHTTPHeaderField:name];
	}
	if (body != nil) {
		[request setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL]];
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	}
	ODataExchange *exchange = [[ODataExchange alloc] initWithRequest:request target:nil action:NULL];
	[service startExchange:exchange];
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
	while (![exchange isFinished] && [deadline timeIntervalSinceNow] > 0) {
		[NSThread sleepForTimeInterval:0.005];
	}
	XCTAssertTrue([exchange isFinished], @"%@ %@ did not finish", method, path);
	NSInteger status = [(NSHTTPURLResponse *)exchange.URLResponse statusCode];
	id json = [exchange.data length] > 0
		? [NSJSONSerialization JSONObjectWithData:exchange.data options:NSJSONReadingAllowFragments error:NULL]
		: nil;
	return @{ @"status": [NSNumber numberWithInteger:status], @"json": json ?: [NSNull null],
	          @"text": [[NSString alloc] initWithData:exchange.data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"" };
}

- (NSDictionary *)get:(NSString *)path service:(ODataService *)service
{
	return [self send:@"GET" path:path body:nil service:service];
}

- (NSInteger)statusOf:(NSDictionary *)response
{
	return [[response objectForKey:@"status"] integerValue];
}

- (id)jsonOf:(NSDictionary *)response
{
	return [response objectForKey:@"json"];
}

/* The service, signed into as a tester with every scope unless a request
 * says otherwise (WFHeaderAuthenticator). */
- (ODataService *)serviceFor:(WFProcessEngine *)engine
{
	ODataService *service = [WFODataService serviceForEngine:engine
	                                             serviceRoot:[NSURL URLWithString:@"http://example.test/api/"]];
	service.authenticator = [[WFHeaderAuthenticator alloc] init];
	return service;
}
