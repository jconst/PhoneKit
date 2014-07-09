//
//  TCConnectionInternal.m
//  TwilioSDK
//
//  Created by Ben Lee on 5/21/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import "Twilio.h"
#import "TCConnectionInternal.h"
#import "TCDeviceInternal.h"
#import "NSString+pj_str.h"
#import "TCCommands.h"
#import "TCCommandHandler.h"

NSString* const TCConnectionIncomingParameterFromKey = @"From";
NSString* const TCConnectionIncomingParameterToKey = @"To";
NSString* const TCConnectionIncomingParameterAccountSIDKey = @"AccountSid";
NSString* const TCConnectionIncomingParameterAPIVersionKey = @"ApiVersion";
NSString* const TCConnectionIncomingParameterCallSIDKey = @"CallSid";


@implementation TCConnectionInternal

@synthesize incoming = incoming_;
@synthesize name = name_;
@synthesize token = token_;
@synthesize incomingCallSid = incomingCallSid_;
@synthesize rejectChannel = rejectChannel_;
@synthesize parameters = parameters_;
@synthesize delegate = delegate_;
@synthesize device = device_;
@synthesize callId = callId_;
@synthesize incomingSoundToken = incomingSoundToken_;
@synthesize callHandle = callHandle_;

-(id)init
{
	self = [self initWithParameters:nil device:nil token:nil delegate:nil];

	return self;
}

-(id)initWithParameters:(NSDictionary *)parameters device:(TCDeviceInternal*)device token:(NSString*)token delegate:(id<TCConnectionDelegate>)delegate
{
	self = [super init];
	
	if (self)
	{
		if (parameters != nil)
			parameters_ = [[NSMutableDictionary alloc] initWithDictionary:parameters];
		else
			parameters_ = [[NSMutableDictionary alloc] initWithCapacity:1];
        
		self.delegate = delegate;
		device_ = [device retain];
		
		if (token != nil)
			token_ = [[NSString alloc] initWithString:token];

		incoming_ = NO;
		muted_ = NO;
		
		state_ = TCConnectionInternalStateUninitialized;
		
		callId_ = PJSUA_INVALID_ID;
		audioPlayerId_ = PJSUA_INVALID_ID;
		
		incomingSoundToken_ = TC_INVALID_SOUND_TOKEN;
		
#ifdef NOT_YET
		//	Check for errors. If they exist, return nil
		if (device == nil)
		{
			[self release];
			self = nil;
		}
#endif
	}
	
	return self;
}

-(id)initWithParameters:(NSDictionary *)parameters device:(TCDeviceInternal *)device token:(NSString*)token incomingCallSid:(NSString*)incomingCallSid rejectChannel:(NSString *)rejectChannel;
{
	self = [super init];
	
	if (self)
	{
        if (parameters != nil)
            parameters_ = [[NSMutableDictionary alloc] initWithDictionary:parameters];
        else
            parameters_ = [[NSMutableDictionary alloc] init];
        
		device_ = [device retain];
		
        // Checks to make sure strings are not nil before allocating a new string out of them
        // so that we don't get a NSPlaceholderString error (used a lot for testing)
        if (token != nil)
            token_ = [[NSString alloc] initWithString:token];
		
        if (incomingCallSid != nil)
            incomingCallSid_ = [[NSString alloc] initWithString:incomingCallSid];
        
        if (rejectChannel != nil)
            rejectChannel_ = [[NSString alloc] initWithString:rejectChannel];
        
		incoming_ = YES;
		muted_ = NO;
		
		state_ = TCConnectionInternalStatePending;
		
		callId_ = PJSUA_INVALID_ID;
		audioPlayerId_ = PJSUA_INVALID_ID;
		
		incomingSoundToken_ = TC_INVALID_SOUND_TOKEN;
		
#ifdef NOT_YET
		//	Check for errors. If they exist, return nil
		if (device == nil)
		{
			[self release];
			self = nil;
		}
#endif
	}
	
	return self;	
}

-(void)dealloc
{
    delegate_ = nil;
    
	// make sure we remove the connection as the call's user data 
	// so we don't leave dangling pointers around.
	
	// TODO: this should probably assert in debug builds
	// if the call in still in-progress when the TCConnectionInternal is being dealloced,
	// which means dangling calls could happen.
	if ( callId_ != PJSUA_INVALID_ID )
		pjsua_call_set_user_data(callId_, NULL);
	
	if ( audioPlayerId_ != PJSUA_INVALID_ID )
		pjsua_player_destroy(audioPlayerId_);

	[token_ release];
	[device_ release];
	[incomingCallSid_ release];
    [rejectChannel_ release];
	[parameters_ release];
	[name_ release];
	
	[super dealloc];
}

-(void)connect
{
	if ( state_ == TCConnectionInternalStateUninitialized ||  // outgoing
		 state_ == TCConnectionInternalStatePending ) // incoming
	{
		state_ = TCConnectionInternalStateOpening;
		
		TCMakeCallCommand* command = [TCMakeCallCommand makeCallCommandWithConnection:self
																		   parameters:parameters_
																			   device:self.device
																	  capabilityToken:self.token
																   connectionDelegate:delegate_];
		
		[[TCCommandHandler sharedInstance] postCommand:command];
	}
}

-(void)handlePJSIPInviteStateCalling:(TwilioError*)error
{
	if (delegate_ && [delegate_ respondsToSelector:@selector(connectionDidStartConnecting:)])
		[delegate_ connectionDidStartConnecting:(TCConnection*)self];
}

-(void)handlePJSIPInviteStateIncoming:(TwilioError*)error
{
	
}

-(void)handlePJSIPInviteStateEarly:(TwilioError*)error
{
	
}

-(void)handlePJSIPInviteStateConnecting:(TwilioError*)error
{
	
}

-(void)handlePJSIPInviteStateConfirmed:(TwilioError*)error
{
	state_ = TCConnectionInternalStateOpen;

	if (delegate_ && [delegate_ respondsToSelector:@selector(connectionDidConnect:)])
		[delegate_ connectionDidConnect:(TCConnection*)self];
}

-(void)handlePJSIPInviteStateDisconnected:(TwilioError*)error
{
	if ( state_ != TCConnectionInternalStateClosed )
	{
		state_ = TCConnectionInternalStateClosed;

		// Stop playing the incoming sound if it's going.
		TCSoundToken tmpToken = self.incomingSoundToken;
		if ( incoming_ && tmpToken != TC_INVALID_SOUND_TOKEN )
		{
			self.incomingSoundToken = TC_INVALID_SOUND_TOKEN; // nil this out so multiple calls don't try to 
			// stop a sound, which may block.
			[[TCSoundManager sharedInstance] stopPlaying:tmpToken];	
		}
		
		// Play the disconnect sound if necessary
		// Only play the disconnect sound if this connection was ever 
		// active, meaning we had a valid call ID; 
		// don't want to play the sound for auto-rejected or ignored calls.
		BOOL doPlayDisconnect = callId_ != PJSUA_INVALID_ID;
		if ( doPlayDisconnect )
		{
			if ( device_.disconnectSoundEnabled )
				[[TCSoundManager sharedInstance] playSound:eTCSound_Disconnected];
		}		

		if (error)
		{
			if (delegate_ && [delegate_ respondsToSelector:@selector(connection:didFailWithError:)])
				[delegate_ connection:(TCConnection*)self didFailWithError:[error error]];
			else // there's an error, but no delegate to handle it.  poop something to the log.
			{
				NSError* nsError = [error error]; 
				NSLog(@"Error establishing connection due to error: %@ domain: %@ code: %d", [nsError localizedDescription], [nsError domain], [nsError code]);
			}
		}
		else
		{
			if (delegate_ && [delegate_ respondsToSelector:@selector(connectionDidDisconnect:)])
				[delegate_ connectionDidDisconnect:(TCConnection*)self];		
		}
		
        // Like in the Android SDK, when the connection state turns to disconnected, we want to get
        // rid of the current call handle, should I be releasing this? Or just nilling it out?
        // Memory for it is only allocated when a make call command is created
        [callHandle_ release];
        callHandle_ = nil;
        
		// Let the device know that the connection is disconnecting so it can do 
		// internal clean-up.  
		// Note that the delegate or other parts of the code may choose to retain
		// the connection for later use, but the device won't know about it anymore.	
		[device_ connectionDisconnected:self];
		// do not reference anything after this line -- the object may be dealloced after notifying the device.
	}
}

#pragma mark TCConnection interface

@synthesize internalState = state_;

-(TCConnectionState)state
{
	TCConnectionState state;
	
	switch (state_)
	{
		case TCConnectionInternalStatePending:
			state = TCConnectionStatePending;
			break;
			
		case TCConnectionInternalStateOpening:
			state = TCConnectionStateConnecting;
			break;
			
		case TCConnectionInternalStateOpen:
		case TCConnectionInternalStateClosing:
			state = TCConnectionStateConnected;
			break;
			
		default:
			state = TCConnectionStateDisconnected;
			break;
	}
	
	return state;
}

-(void)accept
{
	if (state_ == TCConnectionInternalStatePending)
	{
		if ( incomingSoundToken_ != TC_INVALID_SOUND_TOKEN )
		{
			TCSoundToken tmpToken = incomingSoundToken_;
			self.incomingSoundToken = TC_INVALID_SOUND_TOKEN; // nil this out so multiple calls don't try to 
														// stop a sound, which is non-trivial with locks.
			[[TCSoundManager sharedInstance] stopPlaying:tmpToken];	
		}
		
		if ( [device_ numberActiveConnections] != 0 )
		{
			NSLog(@"TCConnection: Cannot accept new connection while another connection is in progress");
			return;
		}
		
		[device_ acceptingConnection:self]; // other pending connections are rejected in this method
		[self connect];		
	}
}

-(void)ignore
{	
	if (state_ == TCConnectionInternalStatePending)
	{
		state_ = TCConnectionInternalStateClosing;

		// sound is stopped in the handlePJSIPInviteStateDisconncted method.
		
		if ( callId_ != PJSUA_INVALID_ID ) // shouldn't happen
		{
            TCHangupCallCommand* hangupCommand = [TCHangupCallCommand hangupCallCommandWithConnection:self];
            [[TCCommandHandler sharedInstance] postCommand:hangupCommand];
			// eventually will call through to handlePJSIPInviteStateDisconnected
			// via PJSIP's state machine.
		}
		else
		{
			// TODO: this is a hack.  find a better way of handling this if possible.
			// Because the callId_ on the connection isn't yet established, there won't
			// be a callback telling us we've been disconnected, but UI or other housekeeping
			// things may be dependent on being notified that this connection is no longer there.
			// it's not clear that pjsua_call_hangup needs to happen here at all,
			// or if we need a callback to the matrix server to send a notice back to the caller
			// that this is ignored.
			[self handlePJSIPInviteStateDisconnected:nil /* error */];
		}
	}
}

-(void)reject
{
    if (state_ == TCConnectionInternalStatePending) // pending implies incoming
	{		
		state_ = TCConnectionInternalStateClosing;

		// sound is stopped in the handlePJSIPInviteStateDisconncted method.

		if ( callId_ != PJSUA_INVALID_ID ) // this shouldn't ever happen
		{
            TCHangupCallCommand* command = [TCHangupCallCommand hangupCallCommandWithConnection:self];
            [[TCCommandHandler sharedInstance] postCommand:command];
		}
		else
		{
#ifdef DEBUG
			NSLog(@"Rejecting call from %@", [parameters_ objectForKey:@"From"]);
#endif
            TCRejectCallCommand* command = [TCRejectCallCommand rejectCallCommandWithConnection:self
                                                                                    eventStream:self.device.eventStream];
            [[TCCommandHandler sharedInstance] postCommand:command];
		
			// finally, have the connection clean up after itself and notify any delegates that it's going away.
			// (do this after the command is created so it retains the connection;
			// calling handlePJSIPInviteStateDisconnected may end up dealloc'ing the connection)
			[self handlePJSIPInviteStateDisconnected:nil /* error */];
		}
	}
	else
	{
		NSLog(@"ERROR: Rejecting on non-pending connection");
	}
}

-(void)disconnect
{
	// send a hangup if we're in an "opening" or "open" state with a valid call id.
	
#if DEBUG
	NSLog(@"---> CONNECTION STATE CURRENTLY %d", state_);
#endif
	// There's a gap between when a connection is uninitialized and when 
	// the connection's connect method may be invoked (e.g. while the outgoing
	// sound is playing.)  If this is the case, there's no chance the disconnect
	// method will ever be called for the connection, and it will never be removed
	// from the device's list of active connections (because it will never move to TCConnectionInternalStateClosed).
	// So we hack that here.
	
	// Note that the TCMakeCallCommand also checks to see if the connection has moved to 
	// closing/closed before actually making the PJSIP call, so we don't need to fire off
	// any other commands, just call the handlePJSIPInviteStateDisconnected
	BOOL forceDisconnectMethod = (state_ == TCConnectionInternalStateUninitialized);
	
	if ( state_ == TCConnectionInternalStatePending || 
		 state_ == TCConnectionInternalStateOpening ||
		 state_ == TCConnectionInternalStateOpen )
	{	
		state_ = TCConnectionInternalStateClosing;
		
		// This may not actually do anything the first time; the call ID might
		// not be established yet.  That's okay -- when on_call_state is executed,
		// it will see that the connection is in a CLOSING state; if any other states
		// other than DISCONNECTED come through, it will force another hangup call command to fire
        TCHangupCallCommand* command = [TCHangupCallCommand hangupCallCommandWithConnection:self];
        [[TCCommandHandler sharedInstance] postCommand:command];
	}
	
	if ( forceDisconnectMethod )
		[self handlePJSIPInviteStateDisconnected:nil /* error */];
}

-(BOOL)isMuted
{
	return muted_;
}

-(void)setMuted:(BOOL)muted
{
	if (state_ == TCConnectionInternalStateOpen)
	{
		muted_ = muted;
        TCMuteCallCommand* command = [TCMuteCallCommand muteCallCommandWithConnection:self
                                                                                      muted:muted];
        [[TCCommandHandler sharedInstance] postCommand:command];
	}
}

-(void)sendDigits:(NSString*)digits
{
	// note: audio is handled in the command
	if (state_ == TCConnectionInternalStateOpen)
	{
        TCSendDigitsCommand* command = [TCSendDigitsCommand sendDigitsCommandWithConnection:self
                                                                               digitsString:digits];
        [[TCCommandHandler sharedInstance] postCommand:command];

	}
}

@end
