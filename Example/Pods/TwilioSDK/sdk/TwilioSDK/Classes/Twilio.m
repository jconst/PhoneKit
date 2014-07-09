//
//  Twilio.m
//  TwilioSDK
//
//  Created by Ben Lee on 5/17/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "Twilio.h"
#import "TwilioError.h"
#import "TCDeviceInternal.h"
#import "TCConnectionInternal.h"
#import "PJSIPAccountInfo.h"
#import "NSObject+JSON.h"
#import "NSString+pj_str.h"
#import "TCCommandHandler.h"
#import "TCSoundManager.h"
#import "TCConstants.h"

static NSString* TwilioDefaultSIPUsername = @"twilio";
static NSString* TwilioDefaultSIPPassword = @"none";


@interface Twilio ()
-(id)initWithConfig:(twilio_config*)config;
-(void)transportConnected:(pjsip_transport*)transport;
-(void)transportDisconnected:(pjsip_transport*)transport;
-(void)destroyTransports;
@end


#if 0 // not needed yet
static void on_call_tsx_state(pjsua_call_id call_id, 
 pjsip_transaction *tsx,
 pjsip_event *e)
{
	NSLog(@"\n\n\ncall transaction state is...");
}
#endif

// Translate the SIP error code to a Twilio Error code per this spec:
// https://sites.google.com/a/twilio.com/wiki/engineering/teams/client-team/chunder/developers-corner/implementation-details/error-codes
// In some cases may still return the original SIP code if we don't have our own version.
static NSInteger transportToTwilioErrorCode(int32_t sipErrorCode)
{
	NSInteger errorCode = sipErrorCode;
	switch (sipErrorCode)
	{
		case 400: // malformed request
			errorCode = eTwilioError_MalformedRequest; 
			break;
		case 401: // generic authorization error
		case 407: // generic authorization error
			errorCode = eTwilioError_GenericAuthorizationError;
			break;
		case 404: // Application not found
			errorCode = eTwilioError_ApplicationNotFound;
			break;
		case 408: // Connection timeout
			errorCode = eTwilioError_ConnectionTimeout;
			break;
		case 603: // Connection declined
			errorCode = eTwilioError_ConnectionDeclined;
			break;
		default:
			// If the sip error code is not in the range of the Twilio-specific
			// error codes, just make it a generic error.  Otherwise the sip error
			// code is a twilio-specific one sent by the server, so just copy it 
			// to the errorCode value.
			if ( sipErrorCode < eTwilioError_GenericError ) 
				errorCode = eTwilioError_GenericError;
			else
				errorCode = sipErrorCode;
			break;
	}
	return errorCode;
}

static void on_call_state(pjsua_call_id call_id, pjsip_event *e)
{
	NSAutoreleasePool*	pool = [[NSAutoreleasePool alloc] init];
	pjsua_call_info		ci;
	pj_status_t			status = PJ_SUCCESS;
	TwilioError*		error = nil;
	
	status = pjsua_call_get_info(call_id, &ci);
    
    if (PJ_SUCCESS == status && e->body.tsx_state.type == PJSIP_EVENT_TRANSPORT_ERROR)
    {
        error = [[[TwilioError alloc] initWithSipError:ci.last_status] autorelease];
        error.twilioError = transportToTwilioErrorCode(ci.last_status);
    }

    /*
     * We used to have a deeper dive understanding of whatever particular SIP error was generated from an invitation failure,
     * however, we were relying upon winning a race between the transport thread and the callback thread. The transport thread
     * must immediately upon receiving an invite and notifying the upward layers deallocate the backing store from the pool
     * (unsafely) without giving a contractual gaurentee to any callee outside of the private transport layer's private API.
     *
     * Pasting in the comments from sip_transport.h:
     *
     * ###
     *
     *      Incoming message buffer.
     *      This structure keep all the information regarding the received message. >>>This
     *      buffer lifetime is only very short, normally after the transaction has been
     *      called, this buffer will be deleted/recycled.<<< So care must be taken when
     *      allocating storage from the pool of this buffer.
     *      struct pjsip_rx_data {
     *      ...
     *
     * ###
     *
     * So we can't do cute things like this:
     *      pjsip_rx_data *rdata = e->body.tsx_state.src.rdata;
     * 
     * And expect that everything is sane from the transport layer for us to make sense of any SIP related state that we
     * care about. PJSIP fail.
     */
	
	if (status == PJ_SUCCESS) 
	{
		TCConnectionInternal* connection = pjsua_call_get_user_data(call_id);  
		
		// further error processing -- in some cases we can ignore/modify errors
		// based on connection state.
		if ( error.twilioError == eTwilioError_ApplicationNotFound &&
			 connection.incoming )
		{
			// If an app-not-found happens during an incoming call, then it means
			// the session isn't present so the other party/parties
			// have hung up already.  Don't present an error in this case.
			error = nil;
		}
		
		TCConnectionInternalState internalState = connection.internalState;
#if DEBUG
		NSLog(@"Internal State: %d", internalState);
#endif
		if ( internalState == TCConnectionInternalStateClosing && 
			 ci.state != PJSIP_INV_STATE_DISCONNECTED)
		{
			// This first if() block is to catch an edge case for this sequence:
			// 1.  connect() is called.
			// 2.  connect() kicks off a TCMakeCallCommand in another thread
			// 3.  disconnect() is called, but the TCConnection has no call id yet
			// 4.  The call connects, and we get here.  We want to kill the call.
			
			TCHangupCallCommand* command = [TCHangupCallCommand hangupCallCommandWithConnection:connection];
			[[TCCommandHandler sharedInstance] postCommand:command];
			
			// Do not notify the TCConnection or anybody of a state change; when
			// the call actually hangs up we should get PJSIP_INV_STATE_DISCONNECTED.

			// TODO: this is still a problem with timeouts: it doesn't fire off an immediate "handlePJSIPStateDisconnected"
			// on the connection if there's a timeout from the server, and then later an error condition comes through, like a 408.
		}
		else
		{
			switch (ci.state) 
			{
				case PJSIP_INV_STATE_CALLING:
#if DEBUG
					NSLog(@"PJSIP_INV_STATE_CALLING");
#endif
					[connection handlePJSIPInviteStateCalling:error];
					break;
					
				case PJSIP_INV_STATE_INCOMING:
#if DEBUG
					NSLog(@"PJSIP_INV_STATE_INCOMING");
#endif
					[connection handlePJSIPInviteStateIncoming:error];
					break;
					
				case PJSIP_INV_STATE_EARLY:
#if DEBUG
					NSLog(@"PJSIP_INV_STATE_EARLY");
#endif
					[connection handlePJSIPInviteStateEarly:error];
					break;
					
				case PJSIP_INV_STATE_CONFIRMED:
#if DEBUG
					NSLog(@"PJSIP_INV_STATE_CONFIRMED");
#endif
			
					[connection handlePJSIPInviteStateConfirmed:error];
					break;
					
				case PJSIP_INV_STATE_CONNECTING:
#if DEBUG
					NSLog(@"PJSIP_INV_STATE_CONNECTING");
#endif
					[connection handlePJSIPInviteStateConnecting:error];
					break;
					
				case PJSIP_INV_STATE_DISCONNECTED:
#if DEBUG
					NSLog(@"PJSIP_INV_STATE_DISCONNECTED");
#endif
					if (ci.last_status >= 400)
					{
                        if (internalState == TCConnectionInternalStateClosing)
                        {
                            // If the connection state is closing, we are going to ignore
                            // PJSIP erros because the connection is already being killed.
                            // This will also fix the bug where didFailWithError is called
                            // when a connection is killed before it connects
                            
                            error = nil;
                            
                        }
                        else 
                        {
                            NSInteger errorCode = transportToTwilioErrorCode(ci.last_status);

                            if (error)
                            {
                                error.sipError = ci.last_status;
                                error.twilioError = errorCode;
                            }
                            else
                            {
                                error = [[[TwilioError alloc] initWithSipError:ci.last_status] autorelease];
                                error.twilioError = errorCode;
                            }
                        }
					}
							
					// Retain the device from the connection while it's disconnecting.
					// This is to prevent potential seg faults in the case of
					// calling [TCDevice disconnectAll] where the device may be deallocated
					// during the handlePJSIPInviteStateDisconnected method if the 
					// calling code has already released the device.
					// Connection/Device lifecycle and object retention needs work...it's kind of gross.
					TCDeviceInternal* theDevice = [connection.device retain]; // grab from connection now since connection may be dealloc-ed after the next line.
					
					[connection handlePJSIPInviteStateDisconnected:error];
					[theDevice release];

					[[Twilio sharedInstance] releaseCallTransports];
					break;
				case PJSIP_INV_STATE_NULL:
					// nothing to do (case put here to avoid compilation warnings)
					break;
			}
		}
	}
	
	[pool release];
}

static void on_call_media_state(pjsua_call_id call_id)
{
	pjsua_call_info ci;
	
	pjsua_call_get_info(call_id, &ci);
	
	if (ci.media_status == PJSUA_CALL_MEDIA_ACTIVE) 
	{
#if DEBUG
		NSLog(@"PJSUA_CALL_MEDIA_ACTIVE");
#endif
		// When media is active, connect call to sound device.
		pjsua_conf_connect(ci.conf_slot, 0);
		pjsua_conf_connect(0, ci.conf_slot);
	}
}

static void on_transport_state(pjsip_transport *tp,
							   pjsip_transport_state state,
							   const pjsip_transport_state_info *info)
{
	if ( state == PJSIP_TP_STATE_CONNECTED )
	{
		[[Twilio sharedInstance] transportConnected:tp];
	} 
	else if ( state == PJSIP_TP_STATE_DISCONNECTED )
	{
		[[Twilio sharedInstance] transportDisconnected:tp];
	}
}


@implementation Twilio

@synthesize userAccounts = userAccounts_;
@synthesize config = config_;

static Twilio* instance = nil;


+(Twilio*)sharedInstance
{
	if (instance == nil)
	{
		twilio_config config;
		twilio_config_defaults(&config);
		instance = [Twilio setupSharedInstanceWithConfig:&config];
	}
	return instance;
}

+(Twilio*)setupSharedInstanceWithConfig:(twilio_config*)config
{
	if (instance == nil)
	{
		instance = [[Twilio alloc] initWithConfig:config];
	}
	
	return instance;
}

+(void)destroySharedInstance
{
	[instance release];
	instance = nil;
}

-(id)init
{
	if ( (self = [super init]))
	{
		userAccounts_ = [[NSMutableDictionary alloc] initWithCapacity:1];
		defaultUserAccount_ = nil;
		mainTransportId_ = PJSUA_INVALID_ID;
		transports_ = [[NSMutableArray alloc] initWithCapacity:2]; // we currently get 2 because we get routed through a load balancer,
		// which establishes the first transport, then all subsequent requests
		// are routed to the destination machine via a second transport.
        transportsQ_ = dispatch_queue_create("com.twilio.Twilio.transportsQ_", NULL);
	}

	return self;
}

-(id)initWithConfig:(twilio_config*)config
{
	if ( self = [self init] )
	{
		pj_status_t	status = PJ_SUCCESS;
		BOOL		pjsipInitialized = NO;
		
		status = pjsua_create();
	
		// TODO: REMOVE BEFORE CHECKIN
		//config->transport_config.sip_transport_type = TRANSPORT_TYPE_TCP;
		twilio_config_copy(&self->config_, config);
		
		if (status == PJ_SUCCESS)
		{
			needsPJSUDestroy = YES;
			
			pjsua_config			cfg;
			pjsua_logging_config	log_cfg;
			
			pjsua_config_default(&cfg);
			
			cfg.cb.on_call_media_state = &on_call_media_state;
			cfg.cb.on_call_state = &on_call_state;
			cfg.cb.on_transport_state = &on_transport_state;
			cfg.timer_setting.sess_expires = 4 * 60 * 60; // the maximum time supported by Asterisk inside of Twilio.
	//		cfg.cb.on_call_tsx_state = &on_call_tsx_state; // not needed yet
			
#if SRV_RECORD_SUPPORT
			// iOS doesn't give us the ability to fetch the currently
			// configured DNS servers, so the PJSIP resolver backend
			// on iOS just uses DNSServicesQueryRecord(), which uses
			// the current DNS servers under the hood.  However, PJSIP's
			// internals require a DNS server to be set, otherwise it
			// just falls back to resolving via A records.
			cfg.nameserver_count = 0;
			cfg.nameserver[cfg.nameserver_count++] = pj_str("208.67.222.222");  // opendns
#endif
			
			//	Release version should not log
#if DEBUG
			pjsua_logging_config_default(&log_cfg);
			log_cfg.console_level = 6;
#else
			pjsua_logging_config_default(&log_cfg);
			log_cfg.console_level = 0;			
#endif
			
			// Set up the audio quality settings
			pjsua_media_config media_cfg;
			pjsua_media_config_default(&media_cfg);
			media_cfg.no_vad = !config->media_config.vad_enabled; 
			media_cfg.quality = config->media_config.voice_quality; 
			media_cfg.ec_tail_len = config->media_config.echo_cancellation_tail_ms;
			media_cfg.snd_rec_latency = config->media_config.sound_record_latency_ms;
			media_cfg.snd_play_latency = config->media_config.sound_playback_latency_ms;
			
			status = pjsua_init(&cfg, &log_cfg, &media_cfg);

			if (status == PJ_SUCCESS)
			{
				//	Add transport of the specified type (UDP/TCP/TLS)
				status = [self recreateMainTransport];

				if (status == PJ_SUCCESS)
				{
                    status = pjsua_start();
                
                    if (status == PJ_SUCCESS)
                    {

                        [self createDefaultUserAccount];
                        if (defaultUserAccount_)
                        {
							// enable a short-list of codecs, and let server-side
							// decide which one to use
							NSDictionary *goodCodecs = [NSDictionary dictionaryWithObjectsAndKeys:
														[NSNumber numberWithInt:PJMEDIA_CODEC_PRIO_NEXT_HIGHER], @"speex/16000",
														[NSNumber numberWithInt:PJMEDIA_CODEC_PRIO_NORMAL],      @"speex/8000",
														[NSNumber numberWithInt:PJMEDIA_CODEC_PRIO_LOWEST],      @"PCMU/8000",
														nil];
							
							pjsua_codec_info codec_info[32];
							unsigned n_codecs = sizeof(codec_info) / sizeof(codec_info[0]);
							status = pjsua_enum_codecs(codec_info, &n_codecs);
							if (status == PJ_SUCCESS)
							{
								for (unsigned i = 0; i < n_codecs; ++i)
								{
									// codec names are of the form $NAME/$SAMPLERATE/$CODEC_NUM, and we want
									// to strip '/$CODEC_NUM'
									NSString *fullCodecName = [NSString stringWithPJStr:codec_info[i].codec_id];
									NSRange firstSlash = [fullCodecName rangeOfString:@"/"];
									NSRange lastSlash = [fullCodecName rangeOfString:@"/" options:NSBackwardsSearch];
									
									NSString *codecName = nil;
									if (lastSlash.location != NSNotFound && lastSlash.location != firstSlash.location)
										codecName = [fullCodecName substringToIndex:lastSlash.location];
									else
										codecName = fullCodecName;
									
									NSNumber *prioNum = [goodCodecs objectForKey:codecName];
									int prio;
									if (prioNum)
										prio = [prioNum intValue];
									else
										prio = PJMEDIA_CODEC_PRIO_DISABLED;
									
									pj_str_t codec_name_pj = [codecName PJSTRString];
									status = pjsua_codec_set_priority(&codec_name_pj, prio);
									if (status != PJ_SUCCESS)
										break;
								}
							}
                            
							if (status == PJ_SUCCESS)
								pjsipInitialized = YES;							
                        }
                    }
                }
			}
			
			if ( pjsipInitialized )
			{
				// Set up the command handler (which involves spinning up another
				// thread) so the system is ready-to-go and as responsive as possible.
				[TCCommandHandler sharedInstance];
				
				// Set up the audio manager, which may take some time to prepare for audio playback.
				[TCSoundManager sharedInstance];
			}
			else
			{
				needsPJSUDestroy = NO;
				pjsua_destroy();
			}
		}
		
#if 0
		if (pjsipInitialized == NO)
		{
			//	We have an error, so release self and return nil
			[self release];
			return nil;
		}
#endif
		if ( status == PJ_SUCCESS )
		{
			// TODO: move to TCConstants
		}
	}
	
	return self;
}

-(void)reinviteConnection:(TCConnectionInternal*)connection;
{
    TCSendReinviteCommand *command = [TCSendReinviteCommand sendReinviteCommandWithConnection:connection];
    [[TCCommandHandler sharedInstance] postCommand:command];
}

-(void)createDefaultUserAccount
{
#if SRV_RECORD_SUPPORT
	defaultUserAccount_ = [[self addUserAccount:TwilioDefaultSIPUsername host:[TCConstants callControlHost]] retain];
#else
	BOOL useTLS = config_.transport_config.sip_transport_type == TRANSPORT_TYPE_TLS;
	NSString* chunderHost = [NSString stringWithFormat:@"%@:%u", [TCConstants callControlHost], [TCConstants callControlPortUsingTLS:useTLS]];
	defaultUserAccount_ = [[self addUserAccount:TwilioDefaultSIPUsername host:chunderHost] retain];
#endif
}

-(BOOL)recreateDefaultAccount
{
	// first get rid of all existing accounts
	for (NSString* user in userAccounts_)
	{
		PJSIPAccountInfo* info = [userAccounts_ objectForKey:user];
		if (info.accountId != PJSUA_INVALID_ID)
		{
			pjsua_acc_del(info.accountId);
		}
	}
	[userAccounts_ removeAllObjects];

	[defaultUserAccount_ release];
	defaultUserAccount_ = nil;

	[self createDefaultUserAccount];
	return (defaultUserAccount_ != nil);
}

-(pj_status_t)recreateMainTransport
{
    pj_status_t status = PJ_SUCCESS;
    
	if (mainTransportId_ != PJSUA_INVALID_ID)
	{
        status = pjsua_transport_close(mainTransportId_, PJ_TRUE);
#if DEBUG
		if(status != PJ_SUCCESS)
        {
            NSLog(@"Failed to close the current transport %d", status);
        }
#endif
        
        mainTransportId_ = PJSUA_INVALID_ID;
	}
	
	// hacky hack for testing on dev (nodes have diff IP addresses on VPN than off)
	pjsip_endpoint *endpt = pjsua_get_pjsip_endpt();
	pj_dns_resolver *resolver = pjsip_endpt_get_resolver(endpt);
	if (resolver)
		pj_dns_resolver_flush_cache(resolver);

	pjsua_transport_config	transportCfg;
	pjsua_transport_config_default(&transportCfg);
	pjsip_transport_type_e transportType = PJSIP_TRANSPORT_TLS;

    //	Add transport of the specified type (UDP/TCP/TLS)
    switch ( config_.transport_config.sip_transport_type )
    {
#if DEBUG
        case TRANSPORT_TYPE_UDP:
			transportType = PJSIP_TRANSPORT_UDP;
			break;
        case TRANSPORT_TYPE_TCP:
			transportType = PJSIP_TRANSPORT_TCP;
			break;
#endif
        case TRANSPORT_TYPE_TLS:
        default:
            transportCfg.tls_setting.method = PJSIP_TLSV1_METHOD; // The most secure transport available in PJSIP.  SSLv3 has some
            // known security issues, and TLS v1.0 was created after SSL v3.
            
            // can't verify yet, PJSIP needs a cert file containing at least the root CA cert,
            // which we're not sure yet how we're going to distribute.  this may involve embedding the cert
            // in the code.
            //				transportCfg.tls_setting.verify_server = PJ_TRUE;
            break;
    }

    status = pjsua_transport_create(transportType, &transportCfg, &mainTransportId_);
#if DEBUG
	if(status != PJ_SUCCESS)
	{
		NSLog(@"Failed to create the new transport %d", status);
	}
#endif

	return status;
}

-(void)dealloc
{
	if (needsPJSUDestroy)
		pjsua_destroy(); // do this first in case anything needs to happen using any of the other objects
						 // in this instance (e.g. transports_)

	[[TCCommandHandler sharedInstance] shutdown]; //releases shared instance
	[[TCSoundManager sharedInstance] shutdown]; //releases shared instance
	[TCConstants shutdown]; // frees up any allocated objects.  not a singleton yet, but has internal statics
	
	[self destroyTransports];
	[transports_ release];
    
    if (transportsQ_)
        dispatch_release(transportsQ_);
	
	[userAccounts_ release];
	
	[defaultUserAccount_ release];

		
	[super dealloc];
}

-(PJSIPAccountInfo*)addUserAccount:(NSString*)user host:(NSString*)host
{
	return [self addUserAccount:user password:TwilioDefaultSIPPassword host:host];
}

-(PJSIPAccountInfo*)addUserAccount:(NSString*)user password:(NSString*)password host:(NSString*)host
{
	if (user == nil || password == nil || host == nil)
		return nil;

	NSString*			sipDomain = [[NSString alloc] initWithString:host]; // make a copy.  (actually not sure why this is done, why not just retain?)
	NSString*			sipUsername = user;
	NSString*			sipPassword = password;
	PJSIPAccountInfo*	accountInfo = nil;
	pjsua_acc_config*	accCfg;	
	pj_status_t			status;
	pjsua_acc_id		accountId;
	BOOL				updateAccount = NO;
	
	
	accountInfo = [[userAccounts_ objectForKey:user] retain];
	
	if (accountInfo == nil)
		accountInfo = [[PJSIPAccountInfo alloc] init];
	else
	{
		//	TODO: How do we really want to handle the case where a different host is used for the same user?
		
		//	Delete old account if the identity is different
		if ((accountInfo.host && [accountInfo.host compare:host] == NSOrderedSame) == NO)
			pjsua_acc_del(accountInfo.accountId);
		else
			updateAccount = YES;
	}
	
	if (accountInfo)
	{
		accCfg = accountInfo.accountConfig;
		
		pjsua_acc_config_default(accCfg);
		
		accCfg->id = [[NSString stringWithFormat:@"sip:%@@%@", sipUsername, sipDomain] PJSTRString];
		accCfg->cred_count = 1;
		accCfg->cred_info[0].realm = [sipDomain PJSTRString];
		accCfg->cred_info[0].scheme = pj_str("digest");
		accCfg->cred_info[0].username = [sipUsername PJSTRString];
		accCfg->cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
		accCfg->cred_info[0].data = [sipPassword PJSTRString];
		accCfg->allow_contact_rewrite = 1;
		accCfg->rtp_cfg.qos_type = PJ_QOS_TYPE_VOICE;
		// pick a port between 4000 and 4999 
		// (RTP ports usually start at 4000)
		// TODO: this could potentially fail if another
		// instance of Twilio is active in another
		// mobile application.
		accCfg->rtp_cfg.port = (pj_rand() % 1000 + 4000);
		
		status = pjsua_acc_add(accCfg, PJ_TRUE, &accountId);		
		
		if (status == PJ_SUCCESS)
		{
			accountInfo.host = sipDomain; // retained
			accountInfo.accountId = accountId;
			
			[userAccounts_ setObject:accountInfo forKey:user];
		}
		else if (updateAccount)
		{
			[userAccounts_ removeObjectForKey:user];
			[userAccounts_ setObject:accountInfo forKey:user];
		}
		else
		{
			[accountInfo release];
			accountInfo = nil;
		}

	}
    [sipDomain release];
    
	return [accountInfo autorelease];
}

-(BOOL)removeUserAccount:(PJSIPAccountInfo*)user;
{
	BOOL		removed = NO;
	NSArray*	keys;
	NSString*	key;
	
	if (user)
	{
		
		keys = [userAccounts_ allKeysForObject:user];
		
		if ([keys count] > 0)
		{
			pj_status_t status;
			
			status = pjsua_acc_del(user.accountId);

			for (key in keys)
			{
				//	Still delete if there was an error
				[userAccounts_ removeObjectForKey:key];
			}
			
			if (status == PJ_SUCCESS)
				removed = YES;
		}
	}
	
	return removed;
}

-(void)transportConnected:(pjsip_transport*)transport
{
#ifdef DEBUG
	NSLog(@"------>Transport connected: 0x%x", (int)transport);
#endif
	
	dispatch_sync(transportsQ_, ^(void) {
        NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
        
		[transports_ addObject:[NSValue valueWithPointer:transport]];
		pjsip_transport_add_ref(transport); // increment the ref count so PJSIP won't kill this from under us
											// during the call
        
        [pool release];
	});
}

-(void)transportDisconnected:(pjsip_transport*)transport
{
#ifdef DEBUG
	NSLog(@"------>Transport disconnected: 0x%x", (int)transport);
#endif
	// don't do anything when disconnected, just wait till the call disconnects
}

-(void)destroyTransports
{
#ifdef DEBUG
	NSLog(@"------>Destroying transports");
#endif
	[self releaseCallTransports];
}

-(void)releaseCallTransports
{
	dispatch_sync(transportsQ_, ^(void) {
        NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
        
		for ( NSValue* pointerValue in transports_ )
		{
			pjsip_transport* transport = [pointerValue pointerValue];
			if ( transport )
			{
#ifdef DEBUG
				NSLog(@"------>Destroying transport: 0x%x", (int)transport);
#endif
				pjsip_transport_dec_ref(transport);
				pjsip_transport_shutdown(transport);
			}
		}
		[transports_ removeAllObjects];
        
        [pool release];
	});
}

@end
