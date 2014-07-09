//
//  Commands.m
//  TwilioSDK
//
//  Created by Rob Simutis on 12/19/11.
//  Copyright (c) 2011 Twilio. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <pjsua.h>
#import "NSObject+JSON.h"
#import "PJSIPAccountInfo.h"
#import "Twilio.h"
#import "TCCommands.h"
#import "NSString+pj_str.h"
#import "TCSoundManager.h"
#import "TCConstants.h"
#import "TCCall.h"

@implementation TCCommand

@synthesize connection = _connection;

-(id)initWithConnection:(TCConnectionInternal*)connection
{
    if ( self = [super init] )
    {
        self.connection = connection;
    }
    return self;
}

-(void)dealloc
{
    [_connection release];
    [super dealloc];
}

-(void)run
{
    if ( ![self respondsToSelector:@selector(run)] )
    {
        [NSException raise:NSInternalInconsistencyException 
                    format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];    
    }
}
@end

#pragma mark -
#pragma mark TCMakeCallCommand

@interface TCMakeCallCommand (Private)
- (NSString *)URLParamsStringFromDictionary:(NSDictionary *)dict;
@end

@implementation TCMakeCallCommand

-(id)initWithConnection:(TCConnectionInternal*)connection
             parameters:(NSDictionary*)params
                 device:(TCDeviceInternal*)inDevice
        capabilityToken:(NSString*)token
     connectionDelegate:(id<TCConnectionDelegate>)delegate
{
    if ( self = [super initWithConnection:connection] )
    {
        self.connection = connection;
        _connectionParameters = [params retain];
        _device = [inDevice retain];
        _capabilityToken = [token retain];
        _connectionDelegate = [delegate retain];
    }
    return self;
}

+(TCMakeCallCommand*)makeCallCommandWithConnection:(TCConnectionInternal*)connection
                                 parameters:(NSDictionary*)params
                                     device:(TCDeviceInternal*)device
                            capabilityToken:(NSString*)token
                         connectionDelegate:(id<TCConnectionDelegate>)delegate
{
    TCMakeCallCommand* command = [[TCMakeCallCommand alloc] initWithConnection:connection 
                                                                    parameters:params 
                                                                        device:device 
                                                               capabilityToken:token 
                                                            connectionDelegate:delegate];
    return [command autorelease];
}

-(void)dealloc
{
    [_connectionDelegate release];
    [_capabilityToken release];
    [_device release];
    [_connectionParameters release];
    
    [super dealloc];
}

-(void)run
{
	NSString*			appSid = [_device.capabilities objectForKey:[TCDeviceInternal TCDeviceCapabilityKeyName:TCDeviceCapabilitiesAppSid]];
	BOOL				useTLS = [Twilio sharedInstance] ? [Twilio sharedInstance]->config_.transport_config.sip_transport_type == TRANSPORT_TYPE_TLS : YES;
    BOOL				incoming = self.connection.isIncoming;
#if SRV_RECORD_SUPPORT
	NSString*			host = [TCConstants callControlHost];
	unsigned short      port = [TCConstants callControlPort];  // see if the app has overridden in dev mode
	if (port > 0)
		host = [host stringByAppendingFormat:@":%u", port];
#else
	NSString*			host = [NSString stringWithFormat:@"%@:%u", [TCConstants callControlHost], [TCConstants callControlPortUsingTLS:useTLS]];
#endif
    NSString            *sipFrom = nil;
	NSString*			urlAsString;
	
	if ( host && (([appSid length] == 0 && incoming) || ([appSid length] > 0)) )
	{
        sipFrom = [NSString stringWithFormat:@"%@@%@", ([appSid length] > 0) ? appSid : @"chunder-incoming", host];
		urlAsString = [NSString stringWithFormat:@"sip:%@;transport=%@", sipFrom, (useTLS) ? @"tls" : @"tcp"];
        
		if (urlAsString)
		{
			pj_status_t	status = PJ_SUCCESS;
			
            const char* theURL = [urlAsString cStringUsingEncoding:NSASCIIStringEncoding];
            
			// It may seem strange to verify the URL each time, but because the appSid isn't sanitized
			// at all, so we want to make sure everything's kosher.
			status = pjsua_verify_url(theURL);
			
			if (status == PJ_SUCCESS)
			{
				NSString*				tokenName;
				NSMutableDictionary*	header;
				NSDictionary*			devParams = [_device.capabilities objectForKey:[TCDeviceInternal TCDeviceCapabilityKeyName:TCDeviceCapabilitiesDeveloperParams]];
				
				if (incoming)
					tokenName = @"X-Twilio-Bridge";
				else
					tokenName = @"X-Twilio-Token";
				
				header = [NSMutableDictionary dictionaryWithObjectsAndKeys:_capabilityToken, tokenName, nil];
				
				if (header)
				{
					if (([_connectionParameters count] > 0) || ([devParams count] > 0))
					{
						//	Combine if needed
						NSMutableDictionary*	compositeDict = [NSMutableDictionary dictionaryWithCapacity:1];
						NSString*				paramsAsString;
						
						if ([_connectionParameters count] > 0)
							[compositeDict addEntriesFromDictionary:_connectionParameters];
						
						// Add dev params from the capability token afterwards so they always "win" in the case of collisions.
						// Dev params are assumed to be "constants" that can't be overriden on a per-connection basis.
						if ([devParams count] > 0)
							[compositeDict addEntriesFromDictionary:devParams];
						
						paramsAsString = [self URLParamsStringFromDictionary:compositeDict];
						
						if (paramsAsString)
							[header setObject:paramsAsString forKey:@"X-Twilio-Params"];
					}
					
					NSString* clientString = [TCConstants clientString];
					if ( clientString )
						[header setObject:clientString forKey:@"X-Twilio-Client"];
					
					NSString* accountSID = [_device.capabilities objectForKey:[TCDeviceInternal TCDeviceCapabilityKeyName:
																			  TCDeviceCapabilitiesAccountSid]];
					[header setObject:accountSID forKey:@"X-Twilio-Accountsid"];
					
					pjsua_msg_data msg_data;
					
					memset(&msg_data, 0, sizeof(msg_data));
					
					pjsua_msg_data_init(&msg_data);
					
					//	Build header info for PJ SIP
					NSString*					key;
					NSString*					value;
					pj_str_t					hdrName;
					pj_str_t					hdrValue;
					// create an array of pjsip_generic_string_hdr structs
					// to pack the header strings into.  this gets freed after
					// the call is made.
					pjsip_generic_string_hdr*	stringHdrArray = malloc(sizeof(pjsip_generic_string_hdr) * [header count]);
					if ( stringHdrArray )
					{
						int	i = 0;
						
						for (key in header)
						{
							value = [header objectForKey:key];
							
							if (value)
							{
								pjsip_generic_string_hdr* stringHdr = &(stringHdrArray[i++]);
								
								memset(stringHdr, 0, sizeof(pjsip_generic_string_hdr));
								
								hdrName = [key PJSTRString];
								hdrValue = [value PJSTRString];
								
								pjsip_generic_string_hdr_init2(stringHdr, &hdrName, &hdrValue);
								
								pj_list_push_back(&msg_data.hdr_list, stringHdr);
							}
						}
						
						pj_str_t uri = pj_str((char *)[urlAsString UTF8String]);
						
						// If the connection was disconnected before we got this far, just skip the making call phase
						TCConnectionInternalState internalState = self.connection.internalState;
						if ( internalState != TCConnectionInternalStateClosing &&
							 internalState != TCConnectionInternalStateClosed )
						{
                            // Create a new call object
                            TCCall *theCall = [[TCCall alloc] initWithConnection:self.connection accountId:((TCDeviceInternal*)_device).userAccount.accountId uri:&uri messageData:&msg_data sipUri:urlAsString];
                                                                                                            
                            self.connection.callHandle = theCall;
                            [theCall makeCall];
                            
                            [theCall release];
						}
						free(stringHdrArray);
					}
				}
			}
		}
    }
}

- (NSString *)URLParamsStringFromDictionary:(NSDictionary *)dict 
{
	NSMutableString*	str = [[[NSMutableString alloc] initWithCapacity:0] autorelease];
	NSArray*			allKeys = [dict allKeys];
	unsigned int		i;
	NSString*			key;
	NSString*			value;
	CFStringRef			valueEscapedCF;
	NSString*			valueEscaped;
	
	for (i = 0; i < [allKeys count]; i++) 
	{
		key = [allKeys objectAtIndex:i];
		value = [dict objectForKey:key];
		
		valueEscapedCF = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                 (CFStringRef)value,
                                                                 NULL,
                                                                 (CFStringRef)@"!*'\"();:@&=+$,/?%#[]% ",
                                                                 kCFStringEncodingUTF8);
		
		valueEscaped = [(NSString *)valueEscapedCF autorelease];
		
		[str appendFormat:@"%@=%@", key, valueEscaped];
		
		if ((i + 1) < [allKeys count]) 
		{
			[str appendString:@"&"];
		}
	}
	
	return str;
}


@end

#pragma mark -
#pragma mark TCHangupCallCommand

@implementation TCHangupCallCommand

+(TCHangupCallCommand*)hangupCallCommandWithConnection:(TCConnectionInternal*)connection
{
    TCHangupCallCommand* command = [[TCHangupCallCommand alloc] initWithConnection:connection];
    return [command autorelease];
}

-(void)run
{
    TCCall *call = self.connection.callHandle;                    
    
    [call hangup];
}

@end

#pragma mark -
#pragma mark TCSendReinviteCommand

@implementation TCSendReinviteCommand

+(TCSendReinviteCommand*)sendReinviteCommandWithConnection:(TCConnectionInternal*)connection
{
    TCSendReinviteCommand* command = [[TCSendReinviteCommand alloc] initWithConnection:connection];
    return [command autorelease];
}

-(void)run
{
    TCCall *call = self.connection.callHandle;
    
    [call sendReinvite];
}

@end

#pragma mark -
#pragma mark TCMuteCallCommand

@implementation TCMuteCallCommand

-(id)initWithConnection:(TCConnectionInternal*)connection
                  muted:(BOOL)muted
{
    if ( self = [super initWithConnection:connection] )
    {
        self.connection = connection;
        _muted = muted;
    }
    return self;
}

+(TCMuteCallCommand*)muteCallCommandWithConnection:(TCConnectionInternal*)connection
                                             muted:(BOOL)muted

{
    TCMuteCallCommand* command = [[TCMuteCallCommand alloc] initWithConnection:connection
                                                                         muted:muted];
    return [command autorelease];
}

-(void)run
{
    TCCall *callHandle = self.connection.callHandle;
    
    [callHandle muteCall:_muted];
    
}

@end

#pragma mark -
#pragma mark TCRejectCallCommand

@implementation TCRejectCallCommand

-(id)initWithConnection:(TCConnectionInternal*)connection
             eventStream:(TCEventStream*)eventStream
{
    if ( self = [super initWithConnection:connection] )
    {
        self.connection = connection;
        _eventStream = [eventStream retain];
    }
    return self;
}

-(void)dealloc
{
    [_eventStream release];
	[super dealloc];
}

+(TCRejectCallCommand*)rejectCallCommandWithConnection:(TCConnectionInternal*)connection
                                           eventStream:(TCEventStream*)eventStream
{
    TCRejectCallCommand* command = [[TCRejectCallCommand alloc] initWithConnection:connection
                                                                       eventStream:eventStream];
    return [command autorelease];
}

-(void)run
{
	NSDictionary* rtPayload = [NSDictionary dictionaryWithObjectsAndKeys:
												@"reject",	@"Response",
						self.connection.incomingCallSid,	@"CallSid",
												nil];

	NSDictionary* rtMessage = [NSDictionary dictionaryWithObjectsAndKeys:
												@"publish",	@"rt.message",
							self.connection.rejectChannel,	@"rt.subchannel",
												rtPayload,	@"rt.payload",
												nil];
	
	NSString* jsonPayload = [rtMessage TCJSONRepresentation];

#ifdef DEBUG
	NSLog(@"Created connection for payload: %@", jsonPayload);
#endif
    
    [_eventStream postMessage:jsonPayload
                 toSubchannel:self.connection.rejectChannel
                  contentType:@"application/json"];
}

@end

#pragma mark -
#pragma mark TCSendDigitsCommand

@implementation TCSendDigitsCommand

static NSCharacterSet* sValidDigits = nil;

-(id)initWithConnection:(TCConnectionInternal*)connection
           digitsString:(NSString *)digits
{
    if ( self = [super initWithConnection:connection] )
    {
        _digits = [digits retain];
        
        if ( !sValidDigits )
            sValidDigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789*#w"] retain];

        // verify digits here and quick-exit with a nil object, releasing self
        // trim out all valid digits.  if there's a 0 length string, the input contains
        // only valid digits.  only if that's the case do we send digits.
        NSString* invalidDigits = [_digits stringByTrimmingCharactersInSet:sValidDigits];
        if ( [_digits length] == 0 || [invalidDigits length] != 0 )
        {
            NSLog(@"[TCConnection sendDigits] error: input string %@ contains invalid digits.", digits);
            [self release];
            return nil;
        }        
    }
    return self;
}

-(void)dealloc
{
    [_digits release];
    [super dealloc];
}

+(TCSendDigitsCommand*)sendDigitsCommandWithConnection:(TCConnectionInternal*)connection
                                                 digitsString:(NSString *)digits

{
    TCSendDigitsCommand* command = [[TCSendDigitsCommand alloc] initWithConnection:connection
                                                                      digitsString:digits];
    return [command autorelease];
}

+(ETCSound)digit2Sound:(char)character
{
	switch (character)
	{
		case '0':
			return eTCSound_Zero;
		case '1':
			return eTCSound_One;
		case '2':
			return eTCSound_Two;
		case '3':
			return eTCSound_Three;
		case '4':
			return eTCSound_Four;
		case '5':
			return eTCSound_Five;
		case '6':
			return eTCSound_Six;
		case '7':
			return eTCSound_Seven;
		case '8':
			return eTCSound_Eight;
		case '9':
			return eTCSound_Nine;
		case '*':
			return eTCSound_Star;
		case '#':
			return eTCSound_Hash;
	}
	return eTCSound_One; // TODO: need to handle this case better.
}

-(void)run
{
    pjsua_call_id callId = self.connection.callId; // TODO: check when the command is created?
                                                    // shoudl that be done for all commands?
    if ( callId != PJSUA_INVALID_ID ) 
    {
        // The algorithm is as such:
        // Loop over each character in the string.  if it's a valid digit
        // (e.g. not a 'w' char), call the function in pjsip to send a DTMF
        // RTP packet, and then wait for 200 milliseconds.  if it's a 'w',
        // wait for 500 milliseconds.
        // We have to wait after sending each digit because the thread that
        // transmits the dtmf digits is separate from this one, and each
        // digit represents 160-200 ms of duration.  If we send down in batches
        // of substrings split by 'w's rather one char at a time, this thread
        // will finish each call to pjsua_call_dial_dtmf() and return almost immediately,
        // while the RTP transmission thread has yet to finish.  This ends up eating
        // up any waits done on this thread, so we artificially block after each char is
        // sent and assume it will take 200 ms to transmit.
        int length = [_digits length];
        int i = 0;
        
        pj_str_t stringStruct; // reused struct every time through the loop.  pjmedia copies everything out by value internally.
        stringStruct.slen = 1; // always send a digit at a time.
        
        while ( i < length )
        {
            char character = (char)[_digits characterAtIndex:i++];
            
            if ( character != 'w' )
            {
				ETCSound digitSound = [TCSendDigitsCommand digit2Sound:character];
				[[TCSoundManager sharedInstance] playSound:digitSound];
				
                stringStruct.ptr = &character;
#ifdef DEBUG
                NSLog(@"Sending DTMF: %c", character);
#endif
                TCCall *callHandle = self.connection.callHandle;
                [callHandle sendDigits:&stringStruct];
                
                [NSThread sleepForTimeInterval:.2 /* 200 ms */]; // go ahead and block after each, even if it's the last digit,
                // in case the app has some kind of keypad.  don't want later calls 
                // to stomp on previous presses
            }
            else
            {
                [NSThread sleepForTimeInterval:.5 /* 500 ms */];
            }
        }
#ifdef DEBUG
        NSLog(@"DTMF digits finished sending");
#endif
    }
}

@end

#if 0 // enhanced presence

#pragma mark -
#pragma mark TCSetPresenceCommand

@implementation TCSetPresenceCommand

- (id)initWithEventStream:(TCEventStream*)eventStream
                   status:(NSString*)status
               statusText:(NSString*)statusText
{
    if ( (self = [super init]) )
    {
        _eventStream = [eventStream retain];
        _status = [status retain];
        _statusText = [statusText retain];
    }
    
    return self;
}

+ (id)setPresenceCommandWithEventStream:(TCEventStream*)eventStream
                                 status:(NSString*)status
                             statusText:(NSString*)statusText
{
    return [[[self alloc] initWithEventStream:eventStream status:status statusText:statusText] autorelease];
}

- (void)run
{
    NSString* const subchannel = @"presence";
    
    NSDictionary* rtPayload = [NSDictionary dictionaryWithObjectsAndKeys:
                               @"available",	@"availablility",
                               _status,         @"status",
                               _statusText,     @"status_text",
                               nil];
    
	NSDictionary* rtMessage = [NSDictionary dictionaryWithObjectsAndKeys:
                               @"publish",	@"rt.message",
                               subchannel,	@"rt.subchannel",
                               rtPayload,	@"rt.payload",
                               nil];
	
	NSString* jsonPayload = [rtMessage TCJSONRepresentation];
    
#ifdef DEBUG
	NSLog(@"Created connection for payload: %@", jsonPayload);
#endif
	
    [_eventStream postMessage:jsonPayload
                 toSubchannel:subchannel
                  contentType:@"application/json"];
}


@end
#endif