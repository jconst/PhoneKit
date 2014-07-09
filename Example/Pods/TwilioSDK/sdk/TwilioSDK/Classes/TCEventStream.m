//
//  TCEventStream.m
//  TwilioSDK
//
//  Created by Brian Tarricone on 1/4/12.
//  Copyright (c) 2012 Twilio, Inc. All rights reserved.
//

#import "TCEventStream.h"
#import "Twilio.h"
#import "TCDevice.h"  // for capabilities dict keys
#import "TCConstants.h"
#import "TCCommandHandler.h"

//#define MATRIX_SUPPORTS_FEATURE_CHANGES

NSString * const TCEventStreamErrorWillRetryKey = @"com.twilio.client.TCEventStreamErrorWillRetryKey";

NSString *const TCEventStreamFeatureIncomingCalls = @"incomingCalls";
NSString *const TCEventStreamFeaturePresenceEvents = @"presenceEvents";
NSString *const TCEventStreamFeaturePublishPresence = @"publishPresence";

@interface TCEventStream (TwilioPrivate)
- (id)initWithCapabilityToken:(NSString *)capabilityToken
                 capabilities:(NSDictionary *)capabilities
                     features:(NSSet *)features;
- (void)connect;
- (NSURL *)urlForSubchannel:(NSString *)subchannel;
- (void)postFeatures:(NSSet *)features;
- (NSURL *)urlForFeatures:(NSSet *)features;
- (void)notifyFeaturesChanged:(NSSet *)newFeatures;
@end


#ifdef MATRIX_SUPPORTS_FEATURE_CHANGES

@interface TCPostFeaturesCommand : TCCommand
{
@private
    TCEventStream *eventStream_;
    NSSet *features_;
}

+ (id)postFeaturesCommandWithEventStream:(TCEventStream *)eventStream
                                features:(NSSet *)features;

- (id)initWithEventStream:(TCEventStream *)eventStream
                 features:(NSSet *)features;

@end

@implementation TCPostFeaturesCommand

+ (id)postFeaturesCommandWithEventStream:(TCEventStream *)eventStream
                                features:(NSSet *)features
{
    return [[[self alloc] initWithEventStream:eventStream features:features] autorelease];
}

- (id)initWithEventStream:(TCEventStream *)eventStream
                 features:(NSSet *)features
{
    if ((self = [super initWithConnection:nil]))
    {
        eventStream_ = [eventStream retain];
        features_ = [features copy];
    }
    
    return self;
}

- (void)dealloc
{
    [eventStream_ release];
    [features_ release];
    [super dealloc];
}

- (void)run
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[eventStream_ urlForFeatures:features_]];
    req.HTTPMethod = @"POST";
    [req setValue:[TCConstants clientString] forHTTPHeaderField:@"X-Twilio-Client"];
    
    NSURLResponse *resp = nil;
    NSError *error = nil;
    NSData *result = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&error];
    
#if DEBUG
    if (!result || error || !resp)
        NSLog(@"Failed to post feature change to matrix: result=%@ error=%@ resp=%@", result, error, resp);
#endif
    
    if (!error && resp && [resp isKindOfClass:[NSHTTPURLResponse class]])
    {
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
        if (httpResp.statusCode >= 200 && httpResp.statusCode < 300)
            [eventStream_ notifyFeaturesChanged:features_];
    }
    
    [pool release];
}

@end

#endif  /* MATRIX_SUPPORTS_FEATURE_CHANGES */


// yeah, this is weird, but i want a dict that doesn't
// take a reference on the values it holds
static CFMutableDictionaryRef eventStreams = NULL;
static dispatch_queue_t eventStreamsQ_ = NULL;
static dispatch_once_t onceToken = NULL;


@implementation TCEventStream

@synthesize delegate = delegate_;
@synthesize features = features_;
@synthesize matrixConn = matrixConn_;
             
+ (void)initialize
{
    dispatch_once(&onceToken, ^(void)
    {
        eventStreams = CFDictionaryCreateMutable(kCFAllocatorDefault, 2, &kCFTypeDictionaryKeyCallBacks, NULL);
        eventStreamsQ_ = dispatch_queue_create("com.twilio.TCEventStream.eventStreamsQ_", NULL);
    });
}

#pragma mark Object Lifecycle

+ (id)eventStreamWithCapabilityToken:(NSString *)capabilityToken
                        capabilities:(NSDictionary *)capabilities
                            features:(NSSet *)features
                            delegate:(id<TCEventStreamDelegate>)delegate
{
    __block TCEventStream *stream = nil;
    
    dispatch_sync(eventStreamsQ_, ^(void) {
        stream = (TCEventStream *)CFDictionaryGetValue(eventStreams, capabilityToken);
        if (!stream) {
            stream = [[[self alloc] initWithCapabilityToken:capabilityToken
                                               capabilities:capabilities
                                                   features:features
												   delegate:delegate] autorelease];
            CFDictionarySetValue(eventStreams, capabilityToken, stream);
        }
    });
    
    return stream;
}

- (id)initWithCapabilityToken:(NSString *)capabilityToken
                 capabilities:(NSDictionary *)capabilities
                     features:(NSSet *)features
					 delegate:(id<TCEventStreamDelegate>)delegate
{
    if ((self = [super init]))
    {
        capabilityToken_ = [capabilityToken retain];
        accountSid_ = [[capabilities objectForKey:TCDeviceCapabilityAccountSIDKey] retain];
        clientName_ = [[capabilities objectForKey:TCDeviceCapabilityClientNameKey] retain];
        hasIncoming_ = [[capabilities objectForKey:TCDeviceCapabilityIncomingKey] boolValue];
        features_ = [features copy];
		delegate_ = delegate;
        [self connect];
    }
    
    return self;
}

- (void)dealloc
{
    dispatch_sync(eventStreamsQ_, ^(void) {
        CFDictionaryRemoveValue(eventStreams, capabilityToken_);
    });
    
    [self disconnect];
    [capabilityToken_ release];
    [accountSid_ release];
    [clientName_ release];
    [features_ release];
    [super dealloc];
}

#pragma mark Public API

- (void)setDelegate:(id<TCEventStreamDelegate>)delegate
{
	if (delegate == delegate_)
		return;

	delegate_ = delegate;
    if (matrixConn_ && matrixConn_.isConnected)
        [delegate eventStreamDidConnect:self];
}

- (void)addFeature:(NSString *)feature
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSSet *newFeatures = [features_ setByAddingObject:feature];
    
    if (![features_ isEqualToSet:newFeatures])
        [self postFeatures:newFeatures];
    
    [pool release];
}

- (void)removeFeature:(NSString *)feature
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSMutableSet *newFeatures = [NSMutableSet set];
    
    for (NSString *curFeature in features_)
    {
        if (![curFeature isEqualToString:feature])
            [newFeatures addObject:curFeature];
    }
    
    if (![features_ isEqualToSet:newFeatures])
        [self postFeatures:newFeatures];
    
    [pool release];
}

- (BOOL)hasFeature:(NSString *)feature
{
    return [features_ containsObject:feature];
}

- (BOOL)postMessage:(NSString *)message
       toSubchannel:(NSString *)subchannel
        contentType:(NSString *)contentType
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[self urlForSubchannel:subchannel]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = [message dataUsingEncoding:NSUTF8StringEncoding];
    
    [req setValue:contentType forHTTPHeaderField:@"Content-Type"];
    [req setValue:[TCConstants clientString] forHTTPHeaderField:@"X-Twilio-Client"];
    
    NSURLResponse *resp = nil;
    NSError *error = nil;
    NSData *result = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&error];
    
    [pool release];
    
    return !result || error || !resp;
}

- (void)disconnect
{
    if (matrixConn_ && hasIncoming_)
    {
        TCHttpJsonLongPollConnection *oldConn = matrixConn_;
        matrixConn_ = nil;
        oldConn.delegate = nil;
        [oldConn disconnect];
        [oldConn release];
    }
}

- (void)setIncomingEnabled:(BOOL)incomingEnabled
{
    if (incomingEnabled == incomingEnabled_)
        return;
    
    incomingEnabled_ = incomingEnabled;
    // FIXME: POST to matrix to disable incomingCalls?
}

- (BOOL)isIncomingEnabled
{
    return incomingEnabled_ && matrixConn_ && matrixConn_.isConnected;
}

#pragma mark Internal API

- (void)connect
{
    if (!matrixConn_ && hasIncoming_)
    {
        NSURL *matrixUrl = [self urlForFeatures:features_];
        NSDictionary *headers = [[NSDictionary alloc] initWithObjectsAndKeys:@"600", @"X-Twilio-Chunked-Keepalive", nil];
        matrixConn_ = [[TCHttpJsonLongPollConnection alloc] initWithURL:matrixUrl
                                                                headers:headers
                                                               delegate:self];
        [headers release];
		matrixConn_.doCertVerification = YES;
		matrixConn_.sslPeerName = [TCConstants matrixSSLPeerName];
        matrixConn_.networkServiceType = kCFStreamNetworkServiceTypeVoIP;
		
        [matrixConn_ connect];
    }
}

- (NSURL *)urlForSubchannel:(NSString *)subchannel
{
    // right now we only POST to matrix...
    return [TCConstants matrixUrlForClientName:clientName_
                                    accountSid:accountSid_
                               capabilityToken:capabilityToken_
                                      features:nil];
}

- (void)postFeatures:(NSSet *)features
{
#ifdef MATRIX_SUPPORTS_FEATURE_CHANGES
    TCCommandHandler *handler = [TCCommandHandler sharedInstance];
    [handler postCommand:[TCPostFeaturesCommand postFeaturesCommandWithEventStream:self
                                                                          features:features]];
#else
    [self notifyFeaturesChanged:features];
#endif
}
             
- (NSURL *)urlForFeatures:(NSSet *)features
{
    return [TCConstants matrixUrlForClientName:clientName_
                                    accountSid:accountSid_
                               capabilityToken:capabilityToken_
                                      features:features];
}
             
- (void)notifyFeaturesChanged:(NSSet *)newFeatures
{
    if (![NSThread isMainThread])
    {
        [self performSelectorOnMainThread:@selector(notifyFeaturesChanged:)
                               withObject:newFeatures
                            waitUntilDone:NO];
    }
    
    [features_ release];
    features_ = [newFeatures copy];

    if (delegate_)
        [delegate_ eventStreamFeaturesUpdated:self];
}

#pragma mark TCHttpJsonLongPollConnectionDelegate

- (void)longPollConnectionDidConnect:(TCHttpJsonLongPollConnection *)connection
{
#if DEBUG
    NSLog(@"stream %@ connected", self);
#endif
    // we don't really care about this...
}

- (void)longPollConnection:(TCHttpJsonLongPollConnection *)connection
         didReceiveHeaders:(NSDictionary *)headers
                statusCode:(NSUInteger)statusCode
             statusMessage:(NSString *)statusMessage
{
#if DEBUG
    NSLog(@"stream %@ got headers", self);
#endif
    if (statusCode == 200)
    {
        if (delegate_) {
            [delegate_ eventStreamDidConnect:self];
			[delegate_ eventStreamFeaturesUpdated:self];
        }
    }
}

- (void)longPollConnection:(TCHttpJsonLongPollConnection *)connection
         didReceiveMessage:(NSDictionary *)messageParams
{
#if DEBUG
    NSLog(@"stream %@ got a message", self);
#endif
    
    [delegate_ eventStream:self didReceiveMessage:messageParams];
}

- (void)longPollConnectionDidDisconnect:(TCHttpJsonLongPollConnection *)connection
{
#if DEBUG
    NSLog(@"stream %@ disconnected", self);
#endif
    if (delegate_)
        [delegate_ eventStreamDidDisconnect:self];
}

- (void)longPollConnection:(TCHttpJsonLongPollConnection *)connection
          didFailWithError:(NSError *)error
                 willRetry:(BOOL)willRetry
{
#if DEBUG
    NSLog(@"stream %@ disconnected, error %@", self, error);
#endif
    if (delegate_)
        [delegate_ eventStream:self didFailWithError:error willRetry:willRetry];
}

@end
