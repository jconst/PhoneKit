
//  TCDeviceInternal.m
//  TwilioSDK
//
//  Created by Ben Lee on 5/17/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import "Twilio.h"
#import "TCDeviceInternal.h"
#import "TCConnectionInternal.h"
#import "SBJsonParser.h"
#import "GTMBase64.h"
#import "TwilioError.h"
#import "TCCommands.h"
#import "TCCommandHandler.h"
#import "TCSoundManager.h"
#import "TCConstants.h"
#import "TCPresenceEventPrivate.h"
#import "TCRosterEntry.h"
#import "ScopeURI.h"
#import "TwilioReachability.h"

// Define for handling decided JSON data that comes from the SBJSON library.  
// (SBJSON will populate a resulting NSDictionary with an NSNull value if a
// JSON field is null, so this shortcut handles that).
#define NOT_NULL(x) (x && (id)x != [NSNull null])

// the following keys are exposed to library users in TCDevice.h
NSString* const TCDeviceCapabilityIncomingKey = @"incoming";
NSString* const TCDeviceCapabilityOutgoingKey = @"outgoing";
NSString* const TCDeviceCapabilityExpirationKey = @"expiration";
NSString* const TCDeviceCapabilityAccountSIDKey = @"accountSID";
NSString* const TCDeviceCapabilityApplicationSIDKey = @"appSID";
NSString* const TCDeviceCapabilityApplicationParametersKey = @"developerParams";
NSString* const TCDeviceCapabilityClientNameKey = @"clientName";

static NSString* twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesLast] = 
{
	@"incoming",		//	TCDeviceCapabilitiesIncoming	
	@"outgoing",		//	TCDeviceCapabilitiesOutgoing	
	@"expiration",		//	TCDeviceCapabilitiesExpiration
	@"accountSID",		//	TCDeviceCapabilitiesAccountSid	
	@"appSID",			//	TCDeviceCapabilitiesAppSid
	@"developerParams",	//	TCDeviceCapabilitiesDeveloperParams
    @"clientName",      //  TCDeviceCapabilitiesClientName
};

typedef enum
{
	JWTSegmentHeader = 0,
	JWTSegmentPayload,
	JWTSegmentSignature,
	JWTSegmentLast
} JWTSegment;

static NSString* jwtSegmentKeyNames[JWTSegmentLast] = 
{
	@"header",		//	JWTSegmentHeader
	@"payload",		//	JWTSegmentPayload
	@"signature",	//	JWTSegmentSignature
};

typedef enum
{
	JWTHeaderAlgorithm = 0,
	JWTHeaderType,
	JWTHeaderLast
} JWTHeader;

static NSString* jwtHeaderKeyNames[JWTHeaderLast] = 
{
	@"alg",	//	JWTHeaderAlgorithm
	@"typ"	//	JWTHeaderType
};

//	TODO: Is it better to have the client name exposed otherwise?
typedef enum
{
	JWTPayloadIssuer = 0,
	JWTPayloadScope,
	JWTPayloadExpirationTime,
	JWTPayloadRequiredLast,
	JWTPayloadAlgorithm = JWTPayloadRequiredLast,
	JWTPayloadLast
} JWTPayload;

static NSString*	jwtPayloadKeyNames[JWTPayloadLast] = 
{
	@"iss",			//	JWTPayloadIssuer
	@"scope",		//	JWTPayloadScope
	@"exp",			//	JWTPayloadExpirationTime
	@"alg",			//	JWTPayloadAlgorithm
};

typedef enum
{
	JWTAlgorithmSHA256 = 0,
	JWTAlgorithmSHA384,
	JWTAlgorithmSHA512,
	JWTAlgorithmLast
} JWTAlgorithm;

static NSString* jwtAlgorithmKeyNames[JWTAlgorithmLast] = 
{
	@"HS256",	//	JWTAlgorithmSHA256
	@"HS384",	//	JWTAlgorithmSHA384
	@"HS512",	//	JWTAlgorithmSHA512
};


static NSArray* jwtValidHeaderValues = nil;
static NSArray* jwtValidPayloadValues = nil;

static NSArray*	jwtValidAlgValues = nil;
static NSArray*	jwtValidTypValues = nil;

static NSArray*	jwtValidValues = nil;

@interface TCDeviceInternal ()
- (void)createHostReachabilityNotifiers;
- (void)destroyHostReachabilityNotifiers;
@end


@implementation TCDeviceInternal

@synthesize allConnections = allConnections_;
@synthesize capabilityToken = capabilityToken_;
@synthesize capabilities = capabilities_;
@synthesize privateCapabilities = privateCapabilities_;
@synthesize delegate = delegate_;
@synthesize internalState = internalState_;
@synthesize userAccount = userAccount_;
@synthesize eventStream = eventStream_;
@synthesize incomingSoundEnabled = incomingSoundEnabled_;
@synthesize outgoingSoundEnabled = outgoingSoundEnabled_;
@synthesize disconnectSoundEnabled = disconnectSoundEnabled_;
@synthesize origSessionType = origSessionType_;
@synthesize backgroundTaskAgent = backgroundTaskAgent_;
@synthesize noNetworkTimer = noNetworkTimer_;

+(NSString*)TCDeviceCapabilityKeyName:(TCDeviceCapabilities)capability
{
	return twDeviceCapabilitiesKeyNames[capability];
}

-(id)init
{
	self = [self initWithCapabilityToken:nil delegate:nil];
	
	return self;
}

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[self destroyHostReachabilityNotifiers];
	
	[internetReachability_ stopNotifier];
	[internetReachability_ release];
    internetReachability_ = nil;
	 
	[self teardownEventStream];
	
	[allConnections_ release];
	
    if( connectionsQ_ )
        dispatch_release(connectionsQ_);
	
	[roster_ release];
	
	[capabilityToken_ release];
	[capabilities_ release];
	[privateCapabilities_ release];
	
	[userAccount_ release];
	[privateParameters release];
		
	[super dealloc];
}

#pragma mark -
#pragma mark Accessors


-(TCDeviceState)state
{
	BOOL hasIncomingCapability = [[capabilities_ objectForKey:TCDeviceCapabilityIncomingKey] boolValue];
	BOOL hasOutgoingCapability = [[capabilities_ objectForKey:TCDeviceCapabilityOutgoingKey] boolValue];
	
	if ( internetReachability_ == nil ||
	 	 [internetReachability_ currentReachabilityStatus] == NotReachable ||
		 (!hasIncomingCapability && !hasOutgoingCapability) )
	{
		return TCDeviceStateOffline;	
	}
	// Note: neither mobile nor JS do verifications against token expiration.
	
	// if there's an active connection, the device is busy.
	if ( [self numberActiveConnections] )
		return TCDeviceStateBusy;
	
	// if we're not connected to matrix, but have incoming capability, then we're offline 
	// (even if the network is available and we could make outgoing calls; 
	//  the READY state is as restrictive as possible.  This might need some work.)
	if ( hasIncomingCapability && self.internalState != TCDeviceInternalIncomingStateReady )
		return TCDeviceStateOffline;	
		
	// Otherwise, we're ready to make calls.
	return TCDeviceStateReady;
}

#pragma mark -
#pragma mark TCDeviceInternal methods

-(void)beginBackgroundUpdateTask
{
    if (backgroundSupported_ && self.backgroundTaskAgent == UIBackgroundTaskInvalid)
    {
        self.backgroundTaskAgent = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
            [self endBackgroundUpdateTask];
        }];
    }
}

-(void)endBackgroundUpdateTask
{
    if (backgroundSupported_ && self.backgroundTaskAgent != UIBackgroundTaskInvalid)
    {
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskAgent];
        self.backgroundTaskAgent = UIBackgroundTaskInvalid;
    }
}

-(void)teardownEventStream
{
    if ( ![NSThread isMainThread] )
	{
		// If we mess with the event mechanisms on a different thread then we
        // could be placed in an incongruous state.
		[self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:YES];
        // we also need to wait in case of event ordering.
		return;
	}
    
	eventStream_.delegate = nil;  // we manually send didStopListeningForIncomingConnections: here
	[eventStream_ disconnect];
	[eventStream_ release];
	eventStream_ = nil;

	if ( self.internalState == TCDeviceInternalIncomingStateReady )
	{
		self.internalState = TCDeviceInternalIncomingStateOffline;
		if (delegate_ && [delegate_ respondsToSelector:@selector(device:didStopListeningForIncomingConnections:)])
			[delegate_ device:(TCDevice*)self didStopListeningForIncomingConnections:nil];
	}
	[self notifyRosterOffline];

	[curFeatures release];
	curFeatures = nil;
}

-(void)setupEventStream
{
	if ( ![NSThread isMainThread] )
	{
		// The event stream connection must be started on the main thread so the
		// AsyncSocket code gets started on the main runloop.
		// Track ticket https://trac.twilio.com/ticket/8912
		[self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:YES]; // wait till done in case
																				  // any code depends on ordering
																				  // of operations here.
		return;
	}

    [self beginBackgroundUpdateTask];
	[self teardownEventStream];
    
    if (delegate_)
    {
        if ( !capabilityToken_ || 
             [capabilityToken_ stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0 )
        {
            return;
        }
        
        // TEMP: only do presence stuff if a delegate that implements the handler method is registered
        // This needs to be done with capability tokens.
        BOOL usePresence = (delegate_ && [delegate_ respondsToSelector:@selector(device:didReceivePresenceUpdate:)]);
        BOOL useIncomingCalls = [[capabilities_ objectForKey:TCDeviceCapabilityIncomingKey] boolValue];
        
        NSMutableSet *newFeatures = [[NSMutableSet alloc] initWithCapacity:2];
        if ( usePresence )
            [newFeatures addObject:TCEventStreamFeaturePresenceEvents];
        if ( useIncomingCalls )
        {
            [newFeatures addObject:TCEventStreamFeatureIncomingCalls];
            [newFeatures addObject:TCEventStreamFeaturePublishPresence];
            self.internalState = TCDeviceInternalIncomingStateInitializing;
        }
        
        eventStream_ = [[TCEventStream eventStreamWithCapabilityToken:capabilityToken_
                                                         capabilities:capabilities_
                                                             features:newFeatures
                                                             delegate:self
                         ] retain];
        
        [newFeatures release];
    }
}

-(void)reachabilityChanged:(NSNotification*)note
{
    TCHttpJsonLongPollConnection *matrixConn = eventStream_.matrixConn;
    TwilioReachability *curReach = [note object];
    
    if ( [curReach isKindOfClass:[TwilioReachability class]] )
	{
		NetworkStatus netStatus = [curReach currentReachabilityStatus];
        
        if(netStatus != NotReachable)
        {
            // We want to immediately shut off the timer if there's even a
            // slim chance that we could connect. Since if the network
            // *really* goes down then we'll still receive another
            // notification
            if (NULL != self.noNetworkTimer)
            {
                dispatch_source_cancel(self.noNetworkTimer);
                dispatch_release(self.noNetworkTimer);
                self.noNetworkTimer = NULL;
            }
            
			// the internet reachability notifier usually fires too early to
			// be useful.  so when we get *that* notification, just recreate
			// the host reachability notifiers and wait for them to notify
			if (curReach == internetReachability_)
			{
#if DEBUG
				NSLog(@"internet is now reachable");
#endif
				[self createHostReachabilityNotifiers];
			}
			else if (curReach == matrixReachability_)
			{
#if DEBUG
				NSLog(@"matrix is now reachable");
#endif
				[matrixConn reconnect];
			}
			else if (curReach == chunderReachability_)
			{
#if DEBUG
				NSLog(@"chunder is now reachable");
#endif
				[self reconnect];
			}
        }
        else
        {
            if (NULL == self.noNetworkTimer)
            {
                self.noNetworkTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
                dispatch_source_set_timer(  self.noNetworkTimer,
                                            dispatch_time(DISPATCH_TIME_NOW,
                                            (int64_t)(TCDeviceNoNetworkTimeoutVal * NSEC_PER_SEC)),
                                            DISPATCH_TIME_FOREVER, 0);
                
                dispatch_source_set_event_handler(self.noNetworkTimer, ^(void) {
                    [self disconnectAll];
                    dispatch_source_cancel(self.noNetworkTimer);
                });
                dispatch_resume(self.noNetworkTimer);
            }
        }
        
#if DEBUG
		BOOL connectionRequired = [curReach connectionRequired];
		NSLog(@"reachability changed netstatus %d, connectionRequired = %d", netStatus, connectionRequired);
#endif
	}
}

-(void)reconnect
{
	Twilio* twImpl = [Twilio sharedInstance];
	[twImpl releaseCallTransports];
	[twImpl recreateDefaultAccount];
	[twImpl recreateMainTransport];

	dispatch_sync(connectionsQ_, ^(void) {
        for (TCConnectionInternal *connection in allConnections_)
        {
            if(connection.state == TCConnectionStateConnected)
            {
                //Reconnect connection;
                [twImpl reinviteConnection:connection];
            }
        }
    });
}

-(NSDictionary*)decodeCapabilityToken:(NSString*)encodedCapabilityToken
{
	NSArray*				tokenParts;
	NSString*				part;
	NSMutableDictionary*	decodedTokenParts = nil;
	NSDictionary*			decodedPartAsJSONDict;
	NSString*				decodedPart = nil;
	NSData*					partData = nil;
	int						segment = 0;
	
	//	TODO: What to do if we have token with too many parts, too few parts, etc
	tokenParts = [encodedCapabilityToken componentsSeparatedByString:@"."];

	if ([tokenParts count] == JWTSegmentLast)
	{
		BOOL	valid = YES;
		
		decodedTokenParts = [[NSMutableDictionary alloc] initWithCapacity:JWTSegmentLast];
		
		for (part in tokenParts)
		{
			partData = [TCGTMBase64 webSafeDecodeString:part];
			
			decodedPart = [[NSString alloc] initWithData:partData encoding:NSASCIIStringEncoding];
			
			//	TODO break out later
			//	TODO handle decodedPart == nil code
			switch (segment)
			{
				case JWTSegmentHeader:
					if (decodedPart)
					{
						decodedPartAsJSONDict = [self extractJWTHeader:decodedPart];
						
						if (decodedPartAsJSONDict)
						{
							[decodedTokenParts setObject:decodedPartAsJSONDict forKey:jwtSegmentKeyNames[segment]];
#if DEBUG
							NSLog(@"Header: %@", [decodedPartAsJSONDict description]);
#endif						
						}
						else
						{
							// This is invalid
							valid = NO;
						}
					}
					else
					{
						// This is invalid
						valid = NO;
					}
					break;
					
				case JWTSegmentPayload:
					if (decodedPart)
					{
						decodedPartAsJSONDict = [self extractJWTPayload:decodedPart];
						
						if (decodedPartAsJSONDict)
						{
							[decodedTokenParts setObject:decodedPartAsJSONDict forKey:jwtSegmentKeyNames[segment]];
#if DEBUG
							NSLog(@"Payload: %@", [decodedPartAsJSONDict description]);
#endif
						}
						else
						{
							// This is invalid
							valid = NO;
						}
					}
					else
					{
						// This is invalid
						valid = NO;
					}
					break;
					
				default:	//	This will be the signature
					assert(segment == JWTSegmentSignature);
					
					if (decodedPart)
					{
						//	Twilio Web Services will validate the signature
						[decodedTokenParts setObject:decodedPart forKey:jwtSegmentKeyNames[segment]];							
					}
					else
					{
						// This is invalid
						valid = NO;
					}
					break;
			}
			
			[decodedPart release];
			
			segment++;

			if (valid == NO)
				break;
		}		
	}

	if ([decodedTokenParts count] != JWTSegmentLast)
	{
		[decodedTokenParts release];
		decodedTokenParts = nil;
	}
	
	return [decodedTokenParts autorelease];
}

-(NSDictionary*)extractJWTHeader:(NSString*)header
{
	NSMutableDictionary*	dict = nil;
	TCSBJsonParser*			jsonParser = [TCSBJsonParser new];
	
	if (header && jwtValidValues)
	{
		dict = [jsonParser objectWithString:header];
	
		if ([dict isKindOfClass:[NSDictionary class]])
		{
			size_t      i;
			BOOL		valid = YES;
			NSArray*	keyValidValues;
			NSString*	value;

			for (i = 0; i < (sizeof(jwtHeaderKeyNames)/(sizeof(jwtHeaderKeyNames[0]))) && i < JWTHeaderLast; i++)
			{
				value = [dict objectForKey:jwtHeaderKeyNames[i]];
				keyValidValues = [jwtValidValues objectAtIndex:i];
				
				if (value)
				{
					if ([keyValidValues containsObject:value] == NO)
						valid = NO;
				}
				else
					valid = NO;
				
				if (valid == NO)
					break;
			}
			
			if (valid == NO)
				dict = nil;
		}
		else
			dict = nil;
	}

	[jsonParser release];
	
	return dict;
}

-(NSDictionary *)extractJWTPayload:(NSString *)payload
{
	NSMutableDictionary *dict = nil;
	TCSBJsonParser *jsonParser = [[TCSBJsonParser alloc] init];
	
	if (payload && jwtValidAlgValues)
	{
		dict = [jsonParser objectWithString:payload];

		if (dict && [dict isKindOfClass:[NSDictionary class]])
		{
			size_t			i;
			NSString*	value;
			BOOL		valid = YES;
			
			//	Check for the existence of all the valid items
			for (i=0;i<=JWTPayloadRequiredLast;i++)
			{
				value = [dict objectForKey:jwtPayloadKeyNames[i]];
				
				if (value)
				{
					//	Do validation code here if appropriate
					if (i == JWTPayloadAlgorithm)
					{
						if ([jwtValidAlgValues containsObject:value] == NO)
							valid = NO;
					}
#ifdef NOT_YET	//	Need to determine if we should trivially reject this early on
					else if (i == JWTPayloadExpirationTime)
					{
						long long	now = (long long) [[NSDate date] timeIntervalSince1970];
						long long	expiration = [value longLongValue];
						
						if (now > expiration)
							valid = NO;
					}
#endif
					
					//	else Twilio Web Services will do the reset to validate JWTPayloadIssuer and JWTPayloadScope
				}
				
				if (valid == NO)
					break;
			}

			//	Check the unrequired items
			for (i = JWTPayloadRequiredLast + 1; i < (sizeof(jwtPayloadKeyNames)/(sizeof(jwtPayloadKeyNames[0]))) && i < JWTPayloadLast; i++)
			{
				value = [dict objectForKey:jwtPayloadKeyNames[i]];
				
				if (value)
				{
					// Do validation code here if appropriate
				}
			}
			
			if (valid == NO)
				dict = nil;
		}
		else
			dict = nil;
	}
	
	[jsonParser release];
	
	return dict;
}

-(void)setCapabilitiesWithCapabilityToken:(NSString*)capabilityToken
								 parameters:(NSDictionary*)parameters	
{
	if (capabilities_ == nil)
		capabilities_ = [[NSMutableDictionary alloc] initWithCapacity:1];
	else
		[capabilities_ removeAllObjects];
	
	if (privateCapabilities_ == nil)
		privateCapabilities_ = [[NSMutableDictionary alloc] initWithCapacity:1];
	else
		[privateCapabilities_ removeAllObjects];
	
	[decodedToken_ release];
	decodedToken_ = nil;
	
	[capabilityToken_ release];
	capabilityToken_ = nil;
	
	[privateParameters release];
	privateParameters = nil;
	
	// TODO: this parsing section and error-handling needs much more work.
	// When parsing fails, there's only a couple of cases where we make a callback
	// to the TCDeviceDelegate, and we don't dump the token out except in debug builds.
	// Probably need to have logging levels for Twilio-specific log messages that may be
	// useful to developers (but keep the PJSIP stuff hidden).
	if (capabilityToken)
	{
		NSDictionary*	payload = nil;
		
		//	split up the token into the core parts

		// (In case the JWT token carries extra whitespace (which it should
		// not have as a base-64 encoded set of text), trim it.  This can happen
		// from ill-behaved web pages.)
		NSString* trimmedToken = [capabilityToken stringByTrimmingCharactersInSet:
													[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		decodedToken_ = [[self decodeCapabilityToken:trimmedToken] retain];
		
		//	decodedToken_ non-nil only if decoding was successful
		if (decodedToken_)
		{
			capabilityToken_ = [[NSString alloc] initWithString:trimmedToken];
			
			//	Now pull out all needed items into our token
			payload = [decodedToken_ objectForKey:@"payload"];
			
			if (payload != nil)
			{
				// save off the private parameters.  these may provide additional
				// options for Twilio's developers to use, such as new host names
				// for chunder/matrix/stream.  Not intended for use by third parties.
                // TODO: remove this at some point and have devs just use TCConstants directly
				privateParameters = [parameters retain];
                
                // slurp params into TCConstants for now
                NSString* matrixHost = [parameters valueForKey:@"matrix"];
                if (matrixHost && [matrixHost length] > 0)
                    [TCConstants setValue:matrixHost forKey:TC_PARAM_MATRIX_HOST];
                
                NSString* chunderHost = [parameters valueForKey:@"chunder"];
                if (chunderHost && [chunderHost length] > 0) {
                    NSArray* parts = [chunderHost componentsSeparatedByString:@":"];
                    [TCConstants setValue:[parts objectAtIndex:0] forKey:TC_PARAM_CHUNDER_HOST];
                    if ([parts count] == 2) {
                        unsigned short port = [(NSString *)[parts objectAtIndex:1] intValue];
                        [TCConstants setValue:[NSNumber numberWithUnsignedShort:port] forKey:TC_PARAM_CHUNDER_PORT];
                    }
                }
                
				NSString* scope = [payload objectForKey:@"scope"];
				if ( NOT_NULL(scope) )
				{
					NSArray* scopes = [scope componentsSeparatedByString:@" "];
					
					// TODO: partition these by service -- should have "client" and "stream" services,
					// each of which has privileges.
					ScopeURI* incoming = nil;
					ScopeURI* outgoing = nil;
#if LATER
					ScopeURI* stream = nil;
#endif
					
					for ( NSString* theScope in scopes )
					{
						ScopeURI* si = [[[ScopeURI alloc] initWithString: theScope] autorelease];
#if DEBUG
						NSLog(@"Scope URI: %@", [si toString]);
#endif
						if ( [si.privilege isEqualToString:@"incoming"] )
							incoming = si;
						else if ( [si.privilege isEqualToString:@"outgoing"] )
							outgoing = si;
#if LATER
						else if ( [si.service isEqualToString:@"stream"] )
							stream = si;
#endif
					}
					
					NSString*	value = nil;
					
					//	Public capabilities
					//		incoming
					//		outgoing
					//		expiration
					//		accountSid
					//		appSid
					//		developerParams
					
					//	incoming
					if ( incoming != nil )
						[capabilities_ setObject:[NSNumber numberWithBool:YES] forKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesIncoming]];
                    else
                        [capabilities_ setObject:[NSNumber numberWithBool:NO] forKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesIncoming]];

					//	outgoing
					if ( outgoing != nil )
					{
						[capabilities_ setObject:[NSNumber numberWithBool:YES] forKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesOutgoing]];
						
						// appSid -- only needed for outgoing
						NSString* appSid = [outgoing.params objectForKey:@"appSid"];
                        if ( appSid )
                        {
                            appSid = [appSid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                            [capabilities_ setObject:appSid forKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesAppSid]];							
						}
                        
                        // developer params -- only needed for outgoing
						if ( outgoing.params )
						{
							NSString* devParamsString = [outgoing.params objectForKey:@"appParams"];
                            devParamsString = [devParamsString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                            
							// URL encoded string, break up into a key/value pair set and make a dictionary from it,
							// adding to the capabilities dictionary.
							NSString* decodedString = [devParamsString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
							if ( decodedString )
							{
								NSMutableDictionary* devParameters = [NSMutableDictionary dictionaryWithCapacity:1]; // autoreleased
								for (NSString* queryPart in [decodedString componentsSeparatedByString:@"&"])
								{
									// break up in to key=value pairs and insert into dictionary
									NSArray* keyValue = [queryPart componentsSeparatedByString:@"="];
									if ( [keyValue count] >= 2 )
										[devParameters setObject:[keyValue objectAtIndex:1] forKey:[keyValue objectAtIndex:0]];
								}
								[capabilities_ setObject:devParameters forKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesDeveloperParams]];
							}
						}
					}
                    else
                        [capabilities_ setObject:[NSNumber numberWithBool:NO] forKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesOutgoing]];
                    
					//	expiration
					value = [payload objectForKey:jwtPayloadKeyNames[JWTPayloadExpirationTime]];
					if ( NOT_NULL(value) )
					{
						NSNumber* expiration = [NSNumber numberWithLongLong:[value longLongValue]];
						
						[capabilities_ setObject:expiration forKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesExpiration]];
					}

					//	accountSid
					value = [payload objectForKey:jwtPayloadKeyNames[JWTPayloadIssuer]];
					if ( NOT_NULL(value) )
					{
                        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        [capabilities_ setObject:value forKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesAccountSid]];
                    }
					
					
					//	Private capbilities
					//		register
					//		chunder
					
					//	matrix ~ register ~ incoming (e.g. matrix is what you register with to receive incoming calls and indicate presence)
					if ( incoming )
					{
						NSString* clientName = [incoming.params objectForKey:@"clientName"];
                        [capabilities_ setValue:clientName forKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesClientName]];
                        
						NSString* accountSid = [capabilities_ objectForKey:twDeviceCapabilitiesKeyNames[TCDeviceCapabilitiesAccountSid]];
						
						if ( !clientName || !accountSid )
						{
							NSString* errorString = nil;
							if ( !clientName )
							{
								errorString = @"Missing client name"; 
							}
							else if ( !accountSid )
							{
								errorString = @"Missing account SID"; 
							}
							
							TwilioError* twError = [[[TwilioError alloc] initWithTwilioError:eTwilioError_NotAValidJWTToken description:errorString] autorelease];

							if (delegate_ && [delegate_ respondsToSelector:@selector(device:didStopListeningForIncomingConnections:)])
								[delegate_ device:(TCDevice*)self didStopListeningForIncomingConnections:[twError error]];
							else // there's an error, but no delegate to handle it.  poop something to the log.
							{
								NSError* error = [twError error];
								NSLog(@"Failed to set up an incoming listener due to an error: %@ domain: %@ code: %d", [error localizedDescription], [error domain], [error code]);
							}
							[self notifyRosterOffline];
						}
					}
				}
			}
		}
	}
    
    [self setupEventStream];
}

-(void)setAudioSessionCategory:(NSString *)category
{
    if ([self numberActiveConnections] == 0)
    {
        NSError *setCategoryError = nil;
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        
        [audioSession setCategory:category error:&setCategoryError];
    }
}

-(void)connectionDisconnected:(TCConnectionInternal*)connection
{
	[connection retain];
    dispatch_sync(connectionsQ_, ^(void) {
        [allConnections_ removeObject:connection];
	});
    
    if (([self numberActiveConnections] == 0) && origSessionType_)
        [self setAudioSessionCategory:origSessionType_];
	
	// NOTE: if any code after this point needs to access the connection,
	// it should do so before the release; once that code runs, the connection
	// may have been dealloc'ed.
	
	
	[connection release];
}

-(void)acceptingConnection:(TCConnectionInternal*)connection
{
	// current policy is that there is only one active connection in flight
	// at any time.  on accept, we reject all other pending connections
#ifdef DEBUG
	NSLog(@"Accepting connection for %@", [connection.parameters objectForKey:@"From"]);
#endif
	
	[self rejectAllConnectionsExceptFor:connection];
}

-(void)rejectAllConnectionsExceptFor:(TCConnectionInternal*)connection
{
	__block NSArray* tempArray = nil;
	// copy the current connections list into a temporary working list
	// so we don't create a potential deadlock
	dispatch_sync(connectionsQ_, ^(void) {
        tempArray = [NSArray arrayWithArray:allConnections_];
    });

	for (TCConnectionInternal* conn in tempArray)
	{
		if ( conn != connection && conn.state == TCConnectionStatePending )
		{
			[conn reject];
		}
	}
}

-(NSUInteger)numberActiveConnections
{
	__block NSUInteger numActiveConns = 0;
    
	dispatch_sync(connectionsQ_, ^(void) {
        for ( TCConnectionInternal* conn in allConnections_ )
        {
            TCConnectionInternalState state = conn.internalState;
         
            if ( state == TCConnectionInternalStateOpening ||
                 state == TCConnectionInternalStateOpen ||
                
                // TODO: this may not be relevant anymore.
                // a connection that's disconnecting isn't really active, or it's in the middle
                // of being torn down.  If any other connection is accept()ed or created
                // in the meantime, it will only do so by going through the command queue,
                // which means that the first connection must hangup before the second connection
                // can possibly be created.
                 state == TCConnectionInternalStateClosing || // TODO: this returns as TCConnectionStateOpen...should this be here?  I think so, since the PJSIP stack is still alive in that case.
            
                
                state == TCConnectionInternalStateUninitialized ) // as a special case,
                                                                  // consider a connection that is uninitialized
                                                                  // to be active -- uninitialized is for outgoing connections
                                                                  // that are in the process of connecting.  skip pending
                                                                  // since incoming connections start at the pending state
                                                                  // and may be ignored or rejected
            {
                numActiveConns++;
            }
        }
	});
	
	return numActiveConns;
}

#pragma mark -
#pragma mark TCDevice interface

// deprecated; remove for the final release of ios
-(id)initWithCapabilitiesToken:(NSString *)capabilityToken delegate:(id <TCDeviceDelegate>)delegate
{
	return [self initWithCapabilityToken:capabilityToken delegate:delegate];
}

-(void)updateCapabilitiesToken:(NSString *)capabilityToken
{
	[self updateCapabilityToken:capabilityToken];
}

-(id)initWithCapabilityToken:(NSString*)capabilityToken delegate:(id<TCDeviceDelegate>)delegate
{
	return [self initWithCapabilityToken:capabilityToken delegate:delegate parameters:nil];
}

-(id)initWithCapabilityToken:(NSString*)capabilityToken delegate:(id<TCDeviceDelegate>)delegate 
					parameters:(NSDictionary*)parameters
{    
	if (!(self = [super init]))
    {
        return self;
    }
    
	UIDevice *currentDevice = [UIDevice currentDevice];
	if ([currentDevice respondsToSelector:@selector(isMultitaskingSupported)])
	{
		backgroundSupported_ = currentDevice.multitaskingSupported;
	}
    
    self.backgroundTaskAgent = UIBackgroundTaskInvalid;
	
	if (self)
	{
		//	Init the statics
		if (jwtValidHeaderValues == nil)
			jwtValidHeaderValues = [[NSArray alloc] initWithObjects:jwtHeaderKeyNames count:JWTHeaderLast];
		
		if (jwtValidPayloadValues == nil)
			jwtValidPayloadValues = [[NSArray alloc] initWithObjects:jwtPayloadKeyNames count:JWTPayloadLast];
		
		if (jwtValidAlgValues == nil)
			jwtValidAlgValues = [[NSArray alloc] initWithObjects:jwtAlgorithmKeyNames count:JWTAlgorithmLast];
		
		if (jwtValidTypValues == nil)
			jwtValidTypValues = [[NSArray alloc] initWithObjects:@"JWT", nil];
		
		if (jwtValidValues == nil && jwtValidAlgValues != nil && jwtValidTypValues != nil)
			jwtValidValues = [[NSArray alloc] initWithObjects:jwtValidAlgValues, jwtValidTypValues, nil];
				
		allConnections_ = [[NSMutableArray alloc] initWithCapacity:1];
		
		connectionsQ_ = dispatch_queue_create("com.twilio.TCDeviceInternal.connectionsQ", NULL);
		
		roster_ = [[NSMutableSet alloc] init];
        
        origSessionType_ = nil;
		
		self.delegate = delegate; // set the delegate immediately in case there's an error parsing the token,
									// which gets reported to the delegate.
        
        // By default enable all sound events
		self.incomingSoundEnabled = YES;
		self.outgoingSoundEnabled = YES;
		self.disconnectSoundEnabled = YES;
        
        [Twilio sharedInstance];

		[self setCapabilitiesWithCapabilityToken:capabilityToken parameters:parameters];
		
		// Set up the reachability changed notification.
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(reachabilityChanged:)
													 name:kReachabilityChangedNotification
												   object:nil];

		[self createHostReachabilityNotifiers];
		internetReachability_ = [[TwilioReachability reachabilityForInternetConnection] retain];
        [internetReachability_ startNotifier];
    }
	
	return self;
}

- (void)createHostReachabilityNotifiers
{
	[self destroyHostReachabilityNotifiers];
	
	matrixReachability_ = [[TwilioReachability reachabilityWithHostName:[TCConstants registerHost]] retain];
	[matrixReachability_ startNotifier];
	
	chunderReachability_ = [[TwilioReachability reachabilityWithHostName:[TCConstants callControlHost]] retain];
	[chunderReachability_ startNotifier];
}

- (void)destroyHostReachabilityNotifiers
{
	[matrixReachability_ stopNotifier];
	[matrixReachability_ release];
	matrixReachability_ = nil;
	
	[chunderReachability_ stopNotifier];
	[chunderReachability_ release];
	chunderReachability_ = nil;
}

-(void)listen
{
	if ( eventStream_ && ![eventStream_.features containsObject:TCEventStreamFeatureIncomingCalls] )
	{
		self.internalState = TCDeviceInternalIncomingStateRegistering;
		[eventStream_ addFeature:TCEventStreamFeatureIncomingCalls];
	}
}

-(void)unlisten
{
	[eventStream_ removeFeature:TCEventStreamFeatureIncomingCalls];
}

-(void)setDelegate:(id<TCDeviceDelegate>)delegate
{
	// we don't retain the delegate, so don't release it.
	if ( delegate != delegate_ )
	{
		delegate_ = delegate;
		
		[self setupEventStream]; // TODO: this will tear things down, including firing the "device offline" and "presence offline"
								 // callbacks on the new delegate and then rebuild the connection to matrix.  it's a little wonky
								 // right now because we don't have the ability to dynamically update matrix's feature set
	}
}


//	TODO: What happens to current connections if we updateCapabilities that are now different from currently running connections?
//	TODO: What happens if they change the user name?
-(void)updateCapabilityToken:(NSString*)capabilityToken
{
	[self updateCapabilityToken:(NSString*)capabilityToken parameters:nil];
}

-(void)updateCapabilityToken:(NSString*)capabilityToken parameters:(NSDictionary*)parameters
{
	[self setCapabilitiesWithCapabilityToken:capabilityToken parameters:parameters];
}

// Make an outgoing connection with the specified parameters
-(TCConnection*)connect:(NSDictionary*)parameters delegate:(id<TCConnectionDelegate>)delegate
{
	// Can only create an outgoing connection if no active connections are present
	if ( [self numberActiveConnections] == 1 )
	{
		NSLog(@"TCDevice: Only one connection can be active at a time");
		return nil;
	}
	else
	{
        if ([self numberActiveConnections] == 0) // When there can be multiple active connections we only want to reset origSessionType if there are no other connections
            origSessionType_ = [[AVAudioSession sharedInstance]category];
        
		TCConnectionInternal*	connection = [[TCConnectionInternal alloc] initWithParameters:parameters device:self token:capabilityToken_ delegate:delegate];
		
		if (connection)
		{
			//	Add to our allConnections_ list
			dispatch_sync(connectionsQ_, ^(void) {
                [allConnections_ addObject:connection];
			});
			
			// Now connect to twilio
			if ( self.outgoingSoundEnabled )
			{
				// Note that we do a completion block and don't connect
				// the outgoing call until the sound finishes playing.
				// The reason we do this is that setting up the PJSIP
				// audio stack can end up monkeying with CoreAudio in 
				// a way that either causes failures to initialize
				// or poor performance (stuttering/clicks/pops)
				[[TCSoundManager sharedInstance] playSound:eTCSound_Outgoing 
											throughSpeaker:NO
													  loop:NO 
											maxNumberLoops:0 
												completion:^
				 {
					 [connection connect];					 
				 }
				 ];
			}
			else
				[connection connect];
			
			[self rejectAllConnectionsExceptFor:connection];
		}
		
		return (TCConnection*)[connection autorelease]; // casted to prevent compiler warnings
	}
}

-(void)disconnectAll
{
    __block NSArray *connectionsTempArray = nil;
	// Remove all connections.
	// Because disconnecting a connection removes it from the
	// list of connections (potentially on another thread)
	// we make a copy of that list here while under the lock,
	// then release the lock so it can be removed from the list safely.
	// (if we just held the lock, the code would deadlock.)
	dispatch_sync(connectionsQ_, ^(void) {
        connectionsTempArray = [NSArray arrayWithArray:allConnections_]; // will be autoreleased
	});

	for (TCConnectionInternal* connection in connectionsTempArray)
	{
		if ( connection.state == TCConnectionStatePending )
			[connection ignore];
		else
			[connection disconnect];
	}
}

#if ENABLE_ADVANCED_PRESENCE
-(void)setPresenceStatus:(NSString *)status statusText:(NSString *)statusText
{
    TCSetPresenceCommand *command = [[TCSetPresenceCommand alloc] initWithEventStream:eventStream_
                                                                               status:status
                                                                           statusText:statusText];
    [[TCCommandHandler sharedInstance] postCommand:command];
    [command release];
}
#endif

#pragma mark -
#pragma mark Internal Roster Handling

- (void)addToRoster:(TCPresenceEvent*)event
{
	TCRosterEntry* entry = [roster_ member:event];
	if ( entry )
	{
#if ENABLE_ADVANCED_PRESENCE
		entry.status = event.status;
		entry.statusText = event.statusText;
#endif
	}
	else
	{
		entry = [TCRosterEntry rosterEntryWithName:event.name
#if ENABLE_ADVANCED_PRESENCE
											status:event.status
										statusText:event.statusText
#endif
				 ];
		[roster_ addObject:entry];
	}
}

- (void)removeFromRoster:(TCPresenceEvent*)event
{
	TCRosterEntry* entry = [roster_ member:event];
	if ( entry )
		[roster_ removeObject:entry];
}

- (void)notifyRosterOffline
{
	if (delegate_ && [delegate_ respondsToSelector:@selector(device:didReceivePresenceUpdate:)])
	{
		for (TCRosterEntry* entry in roster_)
		{
			TCPresenceEvent* event = [[TCPresenceEvent alloc] initWithName:entry.name
																 available:NO
#if ENABLE_ADVANCED_PRESENCE
																	status:entry.status
																statusText:entry.statusText
#endif
									  ];
			[delegate_ device:(TCDevice*)self didReceivePresenceUpdate:event];
			[event release];
		}
	}
	
	[roster_ removeAllObjects];
}

#pragma mark -
#pragma mark EventStream Message Handlers

- (void)handleEventInvite:(NSDictionary *)messageParams
{
	if ( ![curFeatures containsObject:TCEventStreamFeatureIncomingCalls] )
		return;

    NSString* callSid = [messageParams objectForKey:@"CallSid"];
    NSString* token = [messageParams objectForKey:@"Token"];
    NSString* rejectChannel = [messageParams objectForKey:@"RejectChannel"];
    NSDictionary* parameters = [messageParams objectForKey:@"Parameters"];
    if ( !parameters )
        parameters = [NSDictionary dictionary];
    
    if ( !callSid || !token )
        return;

    // TODO: should this be autoreleased just like the Connection created via [Device connect:params:]?
    TCConnectionInternal *connection = [[TCConnectionInternal alloc] initWithParameters:parameters
                                                                                 device:self 
                                                                                  token:token 
                                                                        incomingCallSid:callSid 
                                                                          rejectChannel:rejectChannel];
    // send a message to the delegate that a new connection has come in.
    // if there's already an active connection, that connection will
    // have to be disconnected first before it can be accepted
    
    // Grab some stats about all the connections while we have the lock
    __block int numActiveConnections = 0;
    __block int numPendingConnections = 0;
    
    dispatch_sync(connectionsQ_, ^(void) {
        [allConnections_ addObject:connection];
        for ( TCConnection* tmpConn in allConnections_ )
        {
            switch ( tmpConn.state )
            {
                case TCConnectionStateConnected:
                case TCConnectionStateConnecting:
                    numActiveConnections++; // should only ever be at most one in current impl.
                    break;
                case TCConnectionStatePending:
                    numPendingConnections++;
                    break;
                default:
                    //intentionally blank
                    break;
            }
        }
    });
    
    // TODO: it seems kind of stupid to do anything with the connection if there's no
    // delegate that repsonds to this selector, since the app using this lib can't ever get the connection...
    if (delegate_ && [delegate_ respondsToSelector:@selector(device:didReceiveIncomingConnection:)])
    {
        [delegate_ device:(TCDevice*)self didReceiveIncomingConnection:(TCConnection*)connection];
        
        // TODO: if active connection, only play through speaker if the audio
        // route is overridden (i.e. user has enabled speaker phone).  
        // Loop only if not an existing connection,
        
        // Note: we check the internal state of the connection immediately after didReceiveIncomingConnection
        // and only play if the connection is still pending
        if ( connection.internalState == TCConnectionInternalStatePending &&
            self.incomingSoundEnabled &&
            numPendingConnections == 1 ) // we only play the sound once for all pending connections
        {
            BOOL loop = (numActiveConnections == 0); // loop only if no active connection,
													// since we don't want the user to keep hearing it
													// when they're on a call.
            BOOL useSpeaker = (numActiveConnections == 0);
            TCSoundToken soundToken = [[TCSoundManager sharedInstance] playSound:eTCSound_Incoming throughSpeaker:useSpeaker loop:loop maxNumberLoops:15];
            if ( loop )
                connection.incomingSoundToken = soundToken; // only record this if we're looping so the
            // connection can shut it off.
        }
    }
    
    [connection release];
}

- (void)handleEventCancel:(NSDictionary *)messageParams
{
	if ( ![curFeatures containsObject:TCEventStreamFeatureIncomingCalls] )
		return;

    NSString* callSid = [messageParams objectForKey:@"CallSid"];
    if ( !callSid )
        return;

    // Note that a cancel message is received by all possible clients that are registered
    // under the same name for the application (e.g. multiple "Tommy"s could be connected)
    // once the connection is accepted.  This is to halt the ringing of other "Tommy"s.
    __block TCConnectionInternal *connection = nil;
    dispatch_sync(connectionsQ_, ^(void) {
        for ( TCConnectionInternal *conn in allConnections_ )
        {
            if ( callSid && [conn.incomingCallSid isEqualToString:callSid] )
            {
                connection = conn;
                break;
            }
        }
        [connection retain]; // retain to be sure other threads can't kill this accidentally
    });
    
    if ( connection ) 
    {
        [connection ignore];
        [connection release];
    }
}

- (void)handleEventPresenceInternal:(NSDictionary *)messageParams
{
    NSString* from = [messageParams objectForKey:@"From"];
    if ( from == nil )
        return;
    NSNumber* available = [messageParams objectForKey:@"Available"];
#if ENABLE_ADVANCED_PRESENCE
    NSDictionary* meta = [messageParams objectForKey:@"Meta"];
    NSString* status = [meta objectForKey:@"Status"];
    NSString* statusText = [meta objectForKey:@"StatusText"];
#endif
	
    TCPresenceEvent *event = [[TCPresenceEvent alloc] initWithName:from
                                                         available:[available boolValue]
#if ENABLE_ADVANCED_PRESENCE
															status:status
                                                        statusText:statusText
#endif
							  ];
	
	if ( [available boolValue] )
		[self addToRoster:event];
	else
		[self removeFromRoster:event];
	
    [delegate_ device:(TCDevice*)self didReceivePresenceUpdate:event];
    [event release];
}

- (void)handleEventPresence:(NSDictionary *)messageParams
{
    if (delegate_ && [delegate_ respondsToSelector:@selector(device:didReceivePresenceUpdate:)])
        [self handleEventPresenceInternal:messageParams];
}

- (void)handleEventRoster:(NSDictionary *)messageParams
{
    if (delegate_ && [delegate_ respondsToSelector:@selector(device:didReceivePresenceUpdate:)])
    {
        NSArray *roster = [messageParams objectForKey:@"Roster_v2"];
        for ( NSDictionary *rosterItem in roster )
        {
            [self handleEventPresenceInternal:rosterItem];
        }
    }
}

#pragma mark -
#pragma mark TCEventStreamDelegate

- (void)eventStreamDidConnect:(TCEventStream *)eventStream
{
	// we don't do anything here anymore; eventStreamDidUpdateFeatures: handles incoming notification
}

- (void)eventStreamDidDisconnect:(TCEventStream *)eventStream
{
	[curFeatures release];
	curFeatures = nil;

	if ( self.internalState != TCDeviceInternalIncomingStateOffline )
	{
		self.internalState = TCDeviceInternalIncomingStateOffline;

		//	TODO: Propagate with proper error indicating that we are shutting down
		if (delegate_ && [delegate_ respondsToSelector:@selector(device:didStopListeningForIncomingConnections:)])
			[delegate_ device:(TCDevice*)self didStopListeningForIncomingConnections:nil];
		[self notifyRosterOffline];
	}
}

- (void)eventStream:(TCEventStream *)eventStream didFailWithError:(NSError *)error willRetry:(BOOL)willRetry
{
	[curFeatures release];
	curFeatures = nil;

	if ( self.internalState == TCDeviceInternalIncomingStateReady ||
	     self.internalState == TCDeviceInternalIncomingStateRegistering )
	{
		// only notify for first error.  subsequent auto-reconnect errors should be silent.
		// we also want to notify if the long poller is giving up and won't retry.
		BOOL notifyError = !willRetry || self.internalState == TCDeviceInternalIncomingStateReady;
		
		if ( willRetry )
			self.internalState = TCDeviceInternalIncomingStateRegistering;
		else
			self.internalState = TCDeviceInternalIncomingStateOffline;
		
		if ( notifyError )
		{
			if (delegate_ && [delegate_ respondsToSelector:@selector(device:didStopListeningForIncomingConnections:)])
				[delegate_ device:(TCDevice*)self didStopListeningForIncomingConnections:error];	
			else // there's an error, but no delegate to handle it.  poop something to the log.
				NSLog(@"Failed to set up an incoming listener due to an error: %@ domain: %@ code: %d", [error localizedDescription], [error domain], [error code]);
			[self notifyRosterOffline];
		}
	}
}

- (BOOL)eventStream:(TCEventStream *)eventStream
  didReceiveMessage:(NSDictionary *)messageParams
{
	NSString *request = [messageParams objectForKey:@"Request"];
	NSString *eventType = [messageParams objectForKey:@"EventType"];

	if ( eventType )
	{
		if ( [eventType isEqualToString:@"invite"] )
			[self handleEventInvite:messageParams];
		else if ( [eventType isEqualToString:@"cancel"] )
			[self handleEventCancel:messageParams];
		else if ( [eventType isEqualToString:@"presence"] )
			[self handleEventPresence:messageParams];
		else if ( [eventType isEqualToString:@"roster"] )
			[self handleEventRoster:messageParams];
		else
			return NO;
	}
	// TODO: remove the 'request' stuff after chunderbridge EventType changes deployed
	else if ( request )
	{
		if ( [request isEqualToString:@"invite"] )
			[self handleEventInvite:messageParams];
		else if ( [request isEqualToString:@"cancel"] )
			[self handleEventCancel:messageParams];
		else
			return NO;
	}
	else
		return NO;

	return YES;
}

- (void)eventStreamFeaturesUpdated:(TCEventStream *)eventStream
{
	NSSet *oldFeatures = curFeatures;
	curFeatures = [eventStream.features copy];

    if ( [oldFeatures containsObject:TCEventStreamFeatureIncomingCalls] &&
		 ![curFeatures containsObject:TCEventStreamFeatureIncomingCalls])
	{
		// no longer have incoming calls feature, so drop all pending connections,
		// since we'll never get 'cancel' messages for them

		__block NSArray *allConnectionsCopy = nil;
        
		dispatch_sync(connectionsQ_, ^(void) {
			allConnectionsCopy = [allConnections_ copy];
		});
		
		for ( TCConnectionInternal* conn in allConnectionsCopy )
		{
			if ( conn.internalState == TCConnectionInternalStatePending )
			{
				[conn ignore];
				// handler will remove it from allConnections_
			}
		}
		
		[allConnectionsCopy release];
		
		self.internalState = TCDeviceInternalIncomingStateOffline;
		
		if ( delegate_ && [delegate_ respondsToSelector:@selector(device:didStopListeningForIncomingConnections:)] )
			[delegate_ device:(TCDevice*)self didStopListeningForIncomingConnections:nil];
		[self notifyRosterOffline];
	}
	else if ( ![oldFeatures containsObject:TCEventStreamFeatureIncomingCalls] &&
	          [curFeatures containsObject:TCEventStreamFeatureIncomingCalls])
	{
		// gained the incoming calls features, notify
		self.internalState = TCDeviceInternalIncomingStateReady;

		if ( delegate_ && [delegate_ respondsToSelector:@selector(deviceDidStartListeningForIncomingConnections:)] )
			[delegate_ deviceDidStartListeningForIncomingConnections:(TCDevice*)self];
	}
	
	[oldFeatures release];
    
    [self endBackgroundUpdateTask];
}

@end
