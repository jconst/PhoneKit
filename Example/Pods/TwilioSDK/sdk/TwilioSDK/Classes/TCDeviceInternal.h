//
//  TCDeviceInternal.h
//  TwilioSDK
//
//  Created by Ben Lee on 5/17/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "Twilio.h"
#import "TCDevice.h"
#import "TCDeviceDelegate.h"
#import "TCConnectionDelegate.h"
#import "TCEventStream.h"
#import "TwilioReachability.h"

#include <dispatch/dispatch.h>

#define TCDeviceNoNetworkTimeoutVal     (30)

typedef enum
{
	TCDeviceCapabilitiesIncoming = 0,
	TCDeviceCapabilitiesOutgoing,
	TCDeviceCapabilitiesExpiration,
	TCDeviceCapabilitiesAccountSid,
	TCDeviceCapabilitiesAppSid,
	TCDeviceCapabilitiesDeveloperParams,
	TCDeviceCapabilitiesClientName,
    TCDeviceCapabilitiesLast
} TCDeviceCapabilities;

typedef enum
{
	TCDeviceInternalIncomingStateUninitialized = 0,
	TCDeviceInternalIncomingStateInitializing,
	TCDeviceInternalIncomingStateOffline,
	TCDeviceInternalIncomingStateRegistering,
	TCDeviceInternalIncomingStateReady,
} TCDeviceInternalIncomingState;

@class PJSIPAccountInfo;
@class TCConnectionInternal;

@interface TCDeviceInternal : NSObject<TCEventStreamDelegate>
{
	TCDeviceInternalIncomingState	internalState_;
	
	id<TCDeviceDelegate>			delegate_;
	
	PJSIPAccountInfo*				userAccount_;
	
	TCEventStream*                  eventStream_;
	NSMutableSet*					roster_;

	NSMutableArray*					allConnections_;
	
	NSDictionary*					decodedToken_;
	
	NSString*						capabilityToken_;
	NSMutableDictionary*			capabilities_;
    
    NSString*                       origSessionType_;
	
	// Items we want to treat as private, although since the capability token 
	// is transparent, devs will be able to figure them out
	NSMutableDictionary*			privateCapabilities_;
	
	dispatch_queue_t				connectionsQ_;

	// Private parameters when initializing the TCDevice,
	// such as different hosts for chunder/matrix/etc.
	// Not intended for 3rd parties to use.
	NSDictionary*					privateParameters;
	
	BOOL							incomingSoundEnabled_;
	BOOL							outgoingSoundEnabled_;
	BOOL							disconnectSoundEnabled_;
    BOOL                            backgroundSupported_;
    
	NSMutableSet*					curFeatures;
	
	TwilioReachability*				matrixReachability_;
	TwilioReachability*				chunderReachability_;
	TwilioReachability*				internetReachability_;
    
    UIBackgroundTaskIdentifier      backgroundTaskAgent_;
    
    dispatch_source_t               noNetworkTimer_;
}


@property (readonly) NSMutableDictionary* capabilities;
@property (nonatomic, assign) id<TCDeviceDelegate> delegate;
@property (readonly) NSString *origSessionType;
@property (readonly) NSMutableArray* allConnections;
@property (readonly) NSString* capabilityToken;
@property (readonly) NSMutableDictionary* privateCapabilities;
@property (assign) TCDeviceInternalIncomingState internalState;
@property (retain) PJSIPAccountInfo* userAccount;
@property (readonly) TCEventStream* eventStream;
@property (assign) UIBackgroundTaskIdentifier backgroundTaskAgent;
@property (assign) dispatch_source_t noNetworkTimer;

+(NSString*)TCDeviceCapabilityKeyName:(TCDeviceCapabilities)capability;

-(NSDictionary*)decodeCapabilityToken:(NSString*)encodedCapabilityToken;
-(NSDictionary*)extractJWTHeader:(NSString*)header;
-(NSDictionary*)extractJWTPayload:(NSString*)payload;

-(void)setCapabilitiesWithCapabilityToken:(NSString*)capabilityToken parameters:(NSDictionary*)parameters;
-(void)setAudioSessionCategory:(NSString *)category;

// callback for a connection to notify the device that it has finished the disconnecting process
// The connection may be deallocated as a result of calling this method,
// so senders should retain the connection if they need to operate on the 
// connection after this point.
-(void)connectionDisconnected:(TCConnectionInternal*)connection;

// callback for an incoming connection to notify the device that it is starting the accepting process
-(void)acceptingConnection:(TCConnectionInternal*)connection;

-(void)reachabilityChanged:(NSNotification*)note;

-(NSUInteger)numberActiveConnections;

#pragma mark  TCDevice interface
@property (nonatomic, readonly) TCDeviceState state;
@property (nonatomic) BOOL incomingSoundEnabled;
@property (nonatomic) BOOL outgoingSoundEnabled;
@property (nonatomic) BOOL disconnectSoundEnabled;

-(id)initWithCapabilityToken:(NSString*)capabilityToken delegate:(id<TCDeviceDelegate>)delegate;
-(void)listen;
-(void)unlisten;
-(void)updateCapabilityToken:(NSString*)capabilityToken;
-(TCConnection*)connect:(NSDictionary*)parameters delegate:(id<TCConnectionDelegate>)delegate;
-(void)disconnectAll;
#if 0 // enhanced presence
-(void)setPresenceStatus:(NSString *)status statusText:(NSString *)statusText;
#endif
@end
