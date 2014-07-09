//
//  TCHttpJsonLongPollConnection.m
//  TwilioSDK
//
//  Created by Brian Tarricone on 1/4/12.
//  Copyright (c) 2012 Twilio, Inc. All rights reserved.
//

#import "TCHttpJsonLongPollConnection.h"
#import "SBJsonIncludes.h"
#import "Twilio.h"
#import "TCConstants.h"

#define INITIAL_RECONNECT_WAIT    10.0  /* seconds */
#define MAX_RECONNECT_WAIT       120.0  /* seconds */

enum DataTags
{
    kDataTagHeaders = 0,
    kDataTagChunkSize,
    kDataTagData,
    kDataTagChunkTerminator,
};

NSString * const TCHttpErrorDomain = @"com.twilio.client.TCHttpErrorDomain";
NSString * const TCHttpStatusCodeKey = @"com.twilio.client.TCHttpStatusCodeKey";

@implementation TCHttpJsonLongPollConnection

@synthesize delegate = delegate_;
@synthesize url = url_;
@synthesize connected = connected_;
@synthesize doCertVerification = doCertVerification_;
@synthesize sslPeerName = sslPeerName_;

#pragma mark Object lifecycle

- (id)initWithURL:(NSURL *)url
          headers:(NSDictionary *)headers
         delegate:(id<TCHttpJsonLongPollConnectionDelegate>)delegate
{
    if ((self = [super init]))
    {
        url_ = [url retain];
        headers_ = [headers retain];
        delegate_ = delegate;
        transferEncoding_ = kTCTransferEncodingNone;
        curReconnectWait_ = INITIAL_RECONNECT_WAIT;
    }

    return self;
}

- (void)dealloc
{
    [self disconnect];
    [url_ release];
    [finalUrl_ release];
    [headers_ release];
    delegate_ = nil;
    [super dealloc];
}

#pragma mark Internal API

- (void)reconnect
{
    [self disconnect];
    [self connect];
}

- (void)handleError:(NSError *)error
{
    BOOL shouldReconnect = YES;
    if (error.code == kTCHttpErrorStatus)
    {
        // don't retry for 3xx errors (which we should handle separately)
        // or 4xx errors (because the client did something wrong)
        NSNumber *statusCodeNum = [error.userInfo objectForKey:TCHttpStatusCodeKey];
        if ([statusCodeNum intValue] >= 300 && [statusCodeNum intValue] < 500)
            shouldReconnect = NO;
    }
    
    if (shouldReconnect)
    {
        [self disconnect];
        reconnectTimer_ = [[NSTimer scheduledTimerWithTimeInterval:curReconnectWait_
                                                            target:self
                                                          selector:@selector(connect)
                                                          userInfo:nil
                                                           repeats:NO] retain];
        if (curReconnectWait_ < MAX_RECONNECT_WAIT)
            curReconnectWait_ *= 2;
    } else
        [self disconnect];
    
    if (delegate_)
        [delegate_ longPollConnection:self didFailWithError:error willRetry:shouldReconnect];
}

#pragma mark Public API

- (void)connect
{
    if (sock_ != nil)
        return;
    
    if (reconnectTimer_)
    {
        [reconnectTimer_ invalidate];
        [reconnectTimer_ release];
        reconnectTimer_ = nil;
    }
    
    NSURL *connectUrl = finalUrl_ ? finalUrl_ : url_;
    
    NSString *scheme = [connectUrl scheme];
    if ([scheme isEqualToString:@"https"])
        isHTTPS_ = YES;
    else if ([scheme isEqualToString:@"http"])
        isHTTPS_ = NO;
    else {
        if (delegate_) {
            NSDictionary *userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
                @"Invalid HTTP scheme; only http and https are supported", NSLocalizedDescriptionKey,
                nil];
            NSError *error = [[NSError alloc] initWithDomain:TCHttpErrorDomain
                                                        code:kTCHttpErrorBadUrlScheme
                                                    userInfo:userInfo];
            [delegate_ longPollConnection:self didFailWithError:error willRetry:NO];
            [error release];
            [userInfo release];
        }
        
        return;
    }
    
    NSString *host = [connectUrl host];
    NSNumber *portNum = [connectUrl port];
    short port = portNum ? [portNum unsignedShortValue] : 0;
    if (port == 0) {
        if (isHTTPS_)
            port = 443;
        else
            port = 80;
    }

    transferEncoding_ = kTCTransferEncodingNone;
    sock_ = [[TCAsyncSocket alloc] initWithDelegate:self];
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    @try
    {
        NSError *error = nil;
#if DEBUG
        NSLog(@"gonna connect to host %@, port %d", host, port);
#endif
        if (![sock_ connectToHost:host onPort:port withTimeout:2 error:&error])
        {
#if DEBUG
            NSLog(@"failed to connect: %@", error);
#endif
            [self handleError:error];
        }
    }
    @catch (NSException *e)
    {
#if DEBUG
        NSLog(@"failed to connect: %@", e);
#endif
        NSString *desc = [NSString stringWithFormat:@"HTTP connection failed with exception: %@", e];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  desc, NSLocalizedDescriptionKey,
                                  nil];
        NSError *error = [NSError errorWithDomain:TCHttpErrorDomain
                                             code:kTCHttpErrorConnectFailed
                                         userInfo:userInfo];
        [self handleError:error];
    }

    [pool release];
}

- (void)disconnect
{
    if (sock_ == nil)
        return;
	
    [reconnectTimer_ invalidate];
    [reconnectTimer_ release];
    reconnectTimer_ = nil;
    sock_.delegate = nil;
    [sock_ disconnect];
    [sock_ release];
    sock_ = nil;
    connected_ = NO;
}

- (CFStringRef)networkServiceType
{
    return networkServiceType_;
}

- (void)setNetworkServiceType:(CFStringRef)networkServiceType
{
    if ([(NSString *)networkServiceType isEqualToString:(NSString *)networkServiceType_])
        return;
    
    networkServiceType_ = networkServiceType;
    
    if (sock_ && sock_.isConnected)
    {
        CFReadStreamRef readStream = [sock_ getCFReadStream];
        if (readStream)
            CFReadStreamSetProperty(readStream, kCFStreamNetworkServiceType, networkServiceType);
    }
}

#pragma mark TCAsyncSocketDelegate

-          (void)onSocket:(TCAsyncSocket *)sock
  willDisconnectWithError:(NSError *)err
{
#if DEBUG
	NSLog(@"onSocket:willDisconnectWithError:%@", err);
#endif

    [self handleError:err];
}

- (void)onSocketDidDisconnect:(TCAsyncSocket *)sock
{
#if DEBUG
	NSLog(@"onSocketDidDisconnect");
#endif
	
	connected_ = NO;
    
    if (delegate_)
        [delegate_ longPollConnectionDidDisconnect:self];
}

- (void)onSocket:(TCAsyncSocket *)sock didAcceptNewSocket:(TCAsyncSocket *)newSocket
{
#if DEBUG
	NSLog(@"onSocket:didAcceptNewSocket");
#endif
}

- (BOOL)onSocketWillConnect:(TCAsyncSocket *)sock
{
#if DEBUG
	NSLog(@"onSocketWillConnect %@ %@", sock, self);
#endif
    
    if (isHTTPS_)
    {
        CFReadStreamSetProperty([sock getCFReadStream],
                                kCFStreamPropertySocketSecurityLevel,
                                kCFStreamSocketSecurityLevelNegotiatedSSL);
        CFWriteStreamSetProperty([sock getCFWriteStream],
                                 kCFStreamPropertySocketSecurityLevel,
                                 kCFStreamSocketSecurityLevelNegotiatedSSL);
    }
	
	return YES;
}

-   (void)onSocket:(TCAsyncSocket *)sock
  didConnectToHost:(NSString *)host
              port:(UInt16)port
{
#if DEBUG
	NSLog(@"onSocket:didConnectToHost");
#endif

	if ( doCertVerification_ )
	{
		NSDictionary *settings = nil;
		if ( sslPeerName_ )
		{
			// Set up cert validation for our SSL connection,
			// and start TLS up for encrypted traffic.
			settings = [NSDictionary dictionaryWithObjectsAndKeys:
							sslPeerName_, (NSString *)kCFStreamSSLPeerName,
						[NSNumber numberWithBool:YES], (NSString *)kCFStreamSSLValidatesCertificateChain,
						(NSString*)kCFStreamPropertySocketSecurityLevel, (NSString*)kCFStreamSocketSecurityLevelNegotiatedSSL
						, nil];
		}
		
	#if DEBUG
	   NSLog(@"Starting TLS with settings:\n%@", settings);
	#endif
		[sock startTLS:settings];
	}

    if (networkServiceType_)
    {
        CFReadStreamRef readStream = [sock_ getCFReadStream];
        if (readStream)
            CFReadStreamSetProperty(readStream, kCFStreamNetworkServiceType, networkServiceType_);
    }
	
    if (delegate_)
        [delegate_ longPollConnectionDidConnect:self];
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
    NSURL *connectUrl = finalUrl_ ? finalUrl_ : url_;

	NSString *hostname = [connectUrl host];
	NSString *path = [connectUrl path];
    NSString *query = [connectUrl query];
    NSString *resource;
    if (path && query)  // FIXME: need to urlencode?
        resource = [NSString stringWithFormat:@"%@?%@", path, query];
    else
        resource = path;
	
    NSMutableString *headers = [NSMutableString stringWithFormat:@"GET %@ HTTP/1.1\r\n"
                                                                  "Host: %@\r\n"
                                                                  "User-Agent: TCAsyncSocket/1.0\r\n"
                                                                  "X-Twilio-Client: %@\r\n"
                                                                  "Accept: application/json\r\n",
                         resource, hostname, [TCConstants clientString]];
    for (NSString *headerName in headers_)
    {
        NSString *headerValue = [headers_ objectForKey:headerName];
        [headers appendFormat:@"%@: %@\r\n", headerName, headerValue];
    }
    [headers appendString:@"\r\n"];

	NSData *request = [headers dataUsingEncoding:NSASCIIStringEncoding];
#if DEBUG
	NSLog(@"REQUEST: URL: %@\t%@", [connectUrl absoluteString], headers);
#endif
	
	[sock writeData:request withTimeout:-1 tag:kDataTagHeaders];
	
	NSData *data = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
	[sock readDataToData:data withTimeout:-1 tag:kDataTagHeaders];
    
    [pool release];
}

- (void)onSocket:(TCAsyncSocket *)sock
     didReadData:(NSData *)data
         withTag:(long)tag
{
#if DEBUG
	NSLog(@"onSocket:didReadData");
#endif
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSString *serverReply = [[[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding] autorelease];
    
#if DEBUG
	NSLog(@"received \n%@", serverReply); 
#endif
    
    NSError *error = nil;
	
	if (tag == kDataTagHeaders) 
	{	// reading header
        NSArray *headerLines = [serverReply componentsSeparatedByString:@"\r\n"];
        
        int statusCode = -1;
        NSString *statusMessage = nil;
        NSMutableDictionary *headers = [NSMutableDictionary dictionary];
        
        for (NSString *headerLine in headerLines)
        {
            if ([headerLine length] == 0 || [headerLine isEqualToString:@"\r\n"])
                break;
            
            if (statusCode == -1) {
                const char *statusLine = [headerLine UTF8String];
                
                char *space1 = strchr(statusLine, ' ');
                if (!space1)
                    break;
                while (isspace(*space1) && *space1 != '\0')
                    ++space1;
                if (!*space1)
                    break;
                
                char *space2 = strchr(space1 + 1, ' ');
                if (!space2)
                    break;
                while (isspace(*space2) && *space2 != '\0')
                    ++space2;
                if (!*space2)
                    break;
                
                statusCode = atoi(space1);
                if (statusCode <= 0)
                    break;
                
                statusMessage = [NSString stringWithCString:space2 encoding:NSUTF8StringEncoding];
            } else {
                const char *header = [headerLine UTF8String];
                char *colon = strchr(header, ':');
                if (!colon) {
 #if DEBUG
                    NSLog(@"Warning: got invalid HTTP header: %@", headerLine);
#endif
                    continue;
                }
                
                NSString *headerName = [[[[NSString alloc] initWithBytes:header
                                                                  length:colon-header
                                                                encoding:NSASCIIStringEncoding]
                                         autorelease]
                                        lowercaseString];
                
                while (!isspace(*colon) && *colon != '\0')
                    ++colon;
                while (isspace(*colon) && *colon != '\0')
                    ++colon;
                if (!*colon) {
#if DEBUG
                    NSLog(@"Warning: got invalid HTTP header");
#endif
                    continue;
                }
                
                NSString *headerValue = [NSString stringWithCString:colon
                                                           encoding:NSASCIIStringEncoding];
                
                [headers setObject:headerValue forKey:headerName];
                
                if ([headerName isEqualToString:@"transfer-encoding"] &&
                    [headerValue isEqualToString:@"chunked"])
                {
                    transferEncoding_ = kTCTransferEncodingChunked;
                }
            }
        }
        
        if (statusCode <= 0 && !error)
        {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                @"HTTP status line was invalid", NSLocalizedDescriptionKey,
                nil];
            error = [NSError errorWithDomain:TCHttpErrorDomain
                                        code:kTCHttpErrorBadResponseHeders
                                    userInfo:userInfo];
        }
        
        if (!error)
        {
            if (statusCode >= 200 && statusCode < 300)
                connected_ = YES;

            if (delegate_) {
                [delegate_ longPollConnection:self
                            didReceiveHeaders:headers
                                   statusCode:statusCode
                                statusMessage:statusMessage];
            }

            if (statusCode == 301 ||
                statusCode == 302 ||
                statusCode == 303 ||
                statusCode == 307)
            {
                NSString *location = [headers objectForKey:@"location"];
                if (!location)
                {
                    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                        [NSNumber numberWithInt:statusCode], TCHttpStatusCodeKey,
                        @"HTTP server returned non-success status", NSLocalizedDescriptionKey,
                        nil];
                    error = [NSError errorWithDomain:TCHttpErrorDomain
                                                code:kTCHttpErrorStatus
                                            userInfo:userInfo];
                }
                else
                {
                    [finalUrl_ release];
                    finalUrl_ = [[NSURL alloc] initWithString:location];
                    [self reconnect];
                }
            }
            else if (statusCode >= 300) 
            {
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithInt:statusCode], TCHttpStatusCodeKey,
                    @"HTTP server returned non-success status", NSLocalizedDescriptionKey,
                    nil];
                error = [NSError errorWithDomain:TCHttpErrorDomain
                                            code:kTCHttpErrorStatus
                                        userInfo:userInfo];
            } 
            else if (statusCode >= 200) 
            {
                curReconnectWait_ = INITIAL_RECONNECT_WAIT;
                
                NSData *moreData;
                long nextTag;
                if (transferEncoding_ == kTCTransferEncodingChunked) {
                    moreData = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
                    nextTag = kDataTagChunkSize;
                } else {
                    moreData = [@"\n" dataUsingEncoding:NSASCIIStringEncoding];
                    nextTag = kDataTagData;
                }
                [sock readDataToData:moreData withTimeout:-1 tag:nextTag];
            }
        }
	}
    else if (tag == kDataTagChunkSize)
    {
        const char *chunkSizeStr = [serverReply UTF8String];
        char *endPtr = NULL;
        errno = 0;
        long long int chunkSize = strtoll(chunkSizeStr, &endPtr, 16);
        
        if (errno != 0 || endPtr == chunkSizeStr)
        {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                @"HTTP chunk size was invalid", NSLocalizedDescriptionKey,
                nil];
            error = [NSError errorWithDomain:TCHttpErrorDomain
                                        code:kTCHttpErrorBadChunkSize
                                    userInfo:userInfo];
        }
        else if (chunkSize == 0)
        {
            // last chunk; end of data.  it actually could be sending
            // us trailers and another terminator, but we don't care
            // about that.
            [self disconnect];
            if (delegate_)
                [delegate_ longPollConnectionDidDisconnect:self];
        }
        else
        {
            [sock readDataToLength:chunkSize withTimeout:-1 tag:kDataTagData];
        }
    }
	else if (tag == kDataTagData)
	{
#if DEBUG
        NSLog(@"got data piece");
#endif
		//NSLog(@"received line=%@", serverReply);
        
		if ([serverReply characterAtIndex:0] == '{') 
		{
			//NSLog(@"received line=%@", serverReply);
			NSString *line = [serverReply stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			
			if (line.length > 0 && delegate_) 
			{
				NSDictionary *message = [line TCJSONValue];
                [delegate_ longPollConnection:self didReceiveMessage:message];
			}
		}
		
        NSData *moreData;
        long nextTag;
        if (transferEncoding_ == kTCTransferEncodingChunked) {
            moreData = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
            nextTag = kDataTagChunkTerminator;
        } else {
            moreData = [@"\n" dataUsingEncoding:NSASCIIStringEncoding];
            nextTag = kDataTagData;
        }
		[sock readDataToData:moreData withTimeout:-1 tag:nextTag];
	}
    else if (tag == kDataTagChunkTerminator)
    {
#if DEBUG
        NSLog(@"got chunk terminator");
#endif
        NSData *moreData = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        [sock readDataToData:moreData withTimeout:-1 tag:kDataTagChunkSize];
    }
    
    if (error)
        [self handleError:error];

    [pool release];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p url=%@ connected=%d https=%d>", [[self class] description], self, url_, connected_, isHTTPS_];
}

@end
