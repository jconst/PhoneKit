//
//  Twilio.h
//  TwilioSDK
//
//  Created by Ben Lee on 5/17/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <pjsua.h>
#import "twilio_config.h"

#define SRV_RECORD_SUPPORT 1
#define ENABLE_ADVANCED_PRESENCE 0

@class TCDeviceInternal;
@class TCConnectionInternal;
@class PJSIPAccountInfo;

#define TRANSPORT_TYPE_UDP 0
#define TRANSPORT_TYPE_TCP 1
#define TRANSPORT_TYPE_TLS 2

@interface Twilio : NSObject 
{
	NSMutableDictionary*	userAccounts_;

	PJSIPAccountInfo*		defaultUserAccount_;
	
	int						accountId_;
	
	BOOL					needsPJSUDestroy;
    
	NSMutableArray*			transports_; // SIP transport references.  we hold on to these during a call 
										 // (by incrementing their ref counts) to ensure they aren't terminated
										 // after 10 minutes (which is the timeout period), and we can still receive
										 // SIP traffic.  Basically a wrapper around a giant hack.
										 // once a connection is terminated we decrement the ref counts and destroy the
										 // transport(s) -- which works around a second issue where the transports
										 // may be destroyed by PJSIP at its will, not give us a "transport disconnected"
										 // event, and we then try to reuse a stale transport later.
    
    dispatch_queue_t        transportsQ_;
    
    pjsua_transport_id      mainTransportId_;
    
@public // TEMP
	twilio_config			config_;
}

@property (readonly) NSMutableDictionary*	userAccounts;
@property (readonly) twilio_config config; // return a copy of the config_ struct.
											// making any changes to the configuration
											// requires tearing down and rebuilding 
											// the Twilio object.

+(Twilio*)setupSharedInstanceWithConfig:(twilio_config*)config;
+(Twilio*)sharedInstance;

// Methods used for reinvite  
-(void)reinviteConnection:(TCConnectionInternal*)connection;
-(BOOL)recreateDefaultAccount;
-(pj_status_t)recreateMainTransport;
-(void)releaseCallTransports;

-(PJSIPAccountInfo*)addUserAccount:(NSString*)user host:(NSString*)host;
-(PJSIPAccountInfo*)addUserAccount:(NSString*)user password:(NSString*)password host:(NSString*)host;
-(BOOL)removeUserAccount:(PJSIPAccountInfo*)user;

@end
