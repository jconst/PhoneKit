//
//  TCConnectionInternal.h
//  TwilioSDK
//
//  Created by Ben Lee on 5/21/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TCConnection.h"
#import "TCConnectionDelegate.h"

#import <pjsua-lib/pjsua.h>
#import "TCSoundManager.h"

typedef enum
{
	TCConnectionInternalStateUninitialized = 0,
	TCConnectionInternalStatePending,
	TCConnectionInternalStateOpening,
	TCConnectionInternalStateOpen,
	TCConnectionInternalStateClosing,
	TCConnectionInternalStateClosed,
} TCConnectionInternalState;

@class TCDeviceInternal;
@class TwilioError;
@class TCCall;

@interface TCConnectionInternal : NSObject
{
	TCConnectionInternalState	state_;
	
	id<TCConnectionDelegate>	delegate_;
	
	BOOL						incoming_;
	
	NSMutableDictionary*		parameters_;
	
	NSString*					token_;
	NSString*					incomingCallSid_;
    NSString*                   rejectChannel_;
	
	NSString*					name_;	
	
	TCDeviceInternal*			device_;
    TCCall*                     callHandle_;
	
	pjsua_call_id				callId_;
	pjsua_player_id				audioPlayerId_;
	
	BOOL						muted_;
	TCSoundToken				incomingSoundToken_; // token to use when incoming sound is played
}

@property (assign) pjsua_call_id callId;
@property (readonly) NSString* token;
@property (readonly) NSString* incomingCallSid;
@property (readonly) NSString* rejectChannel;
@property (readonly) NSString* name;
@property (readonly) TCDeviceInternal* device;
@property (assign) TCSoundToken incomingSoundToken;
@property (readonly) TCConnectionInternalState internalState;
@property (nonatomic, retain) TCCall *callHandle;

// outgoing call
-(id)initWithParameters:(NSDictionary*)parameters device:(TCDeviceInternal*)device token:(NSString*)token delegate:(id<TCConnectionDelegate>)delegate;
// incoming call
-(id)initWithParameters:(NSDictionary *)parameters device:(TCDeviceInternal *)device token:(NSString*)token incomingCallSid:(NSString*)incomingCallSid rejectChannel:(NSString *)rejectChannel;

-(void)connect;
-(void)accept;
-(void)ignore;
-(void)reject;
-(void)disconnect;
-(void)sendDigits:(NSString*)digits;

-(void)handlePJSIPInviteStateCalling:(TwilioError*)error;
-(void)handlePJSIPInviteStateIncoming:(TwilioError*)error;
-(void)handlePJSIPInviteStateEarly:(TwilioError*)error;
-(void)handlePJSIPInviteStateConnecting:(TwilioError*)error;
-(void)handlePJSIPInviteStateConfirmed:(TwilioError*)error;
-(void)handlePJSIPInviteStateDisconnected:(TwilioError*)error;

#pragma mark TCConnection interface

@property (readonly) TCConnectionState state;
@property (readonly, getter=isIncoming) BOOL incoming;
/*
 TODO: Define all available keys. Also determine how to expose, if desired, the developer's	key/value pairs.
 
 TODO. Need to determine how a conference call works. If the conference call uses a singular TCConnection, then some adjustments will be needed
 */
@property (readonly) NSDictionary* parameters;
@property (assign) id<TCConnectionDelegate> delegate;
@property (nonatomic, getter=isMuted) BOOL muted;


@end
