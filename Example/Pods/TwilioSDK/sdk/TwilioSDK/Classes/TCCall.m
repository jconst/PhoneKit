//
//  TCCall.m
//  TwilioSDK
//
//  Created by Chris Wendel on 7/12/12.
//  Copyright (c) 2012 Twilio. All rights reserved.
//

#import "TCCall.h"
#include <pjsua-lib/pjsua.h>

@implementation TCCall
@synthesize connection = connection_;
@synthesize sipUri = sipUri_;
@synthesize accountId = accountId_;
@synthesize msgData = msgData_;
@synthesize uri = uri_;
@synthesize callId = callId_;

-(id)initWithConnection:(TCConnectionInternal*) connection accountId:(pjsua_acc_id)accountId uri:(pj_str_t*)uri messageData:(pjsua_msg_data*)messageData sipUri:(NSString *)sipUri
{
    if ( self = [super init] )
    {
        connection_ = connection;
        sipUri_ = [sipUri copy];
        accountId_ = accountId;
        uri_ = uri;
        msgData_ = messageData;
        callId_ = PJSUA_INVALID_ID;
    }
    
    return self;
}

-(void)dealloc
{
    [sipUri_ release];
    [super dealloc];
}

-(void)makeCall
{
    if (callId_ != PJSUA_INVALID_ID) {
#ifdef DEBUG
        NSLog(@"Call already in progress");
#endif
        return;
    }
    
    pj_status_t status;
    status = pjsua_call_make_call(accountId_, uri_, 0 /* options */, connection_, msgData_, &callId_);
    
    if (status == PJ_SUCCESS)
    {
        self.connection.callId = callId_;
    }
    
}

-(void)hangup
{
    if (callId_ != PJSUA_INVALID_ID)
    {
#ifdef DEBUG
        NSLog(@"Hanging up call, callID: %d", callId_);
#endif
        if (PJ_SUCCESS != pjsua_call_hangup(callId_, 0 /* code */, NULL /* reason string */, NULL /* msg_data */))
        {
            NSLog(@"Unable to hangup call, callID: %d", callId_);
        }
    }
}

-(void)muteCall:(BOOL)muted
{
    if (callId_ != PJSUA_INVALID_ID )
    {
        pjsua_call_info ci;
        pjsua_call_get_info(callId_, &ci);
        
        pjsua_conf_port_id conferenceSlot = ci.conf_slot;
        if ( conferenceSlot != PJSUA_INVALID_ID )
        {
            pjsua_conf_adjust_tx_level(conferenceSlot, muted == YES ?
                                       0.0 /* muted */ :
                                       1.0 /* unmuted */);
        }
    }
}

/*
 *  Issues a reinvite to the current call
 */
-(void)sendReinvite
{
    if (callId_ == PJSUA_INVALID_ID)
        return;

    pj_status_t status = PJ_SUCCESS;
    pj_str_t new_contact = { NULL, 0 };
    pj_pool_t *pool = pjsua_pool_create("Contact", 512, 512);
   
	const char *sip_uri = [sipUri_ UTF8String];
	pj_str_t uri = pj_str((char *)sip_uri);
	status = pjsua_acc_create_uac_contact(pool, &new_contact, accountId_, &uri);
	
	if(status != PJ_SUCCESS)
	{
	   NSLog(@"Failed to create contact");
	}

    if(new_contact.slen > 0)
    {
        pjsip_inv_session *inv = NULL;
        status = pjsua_call_get_inv_session(callId_, &inv);
        if (status == PJ_SUCCESS)
        {
            pjsip_tx_data *tdata = NULL;
            status = pjsip_inv_reinvite(inv, &new_contact, NULL, &tdata);
            if(status != PJ_SUCCESS)
            {
                NSLog(@"Failed sending the reinvite");
            }
            else
            {
                status = pjsip_inv_send_msg(inv, tdata);
                if(status != PJ_SUCCESS)
                {
                    NSLog(@"Failed sending the message");
                }
            }
        }
    }
    
    if(pool)
        pj_pool_release(pool);
}

-(void)sendDigits:(pj_str_t*)stringStruct
{
    if (callId_ != PJSUA_INVALID_ID)
        pjsua_call_dial_dtmf(callId_, stringStruct);
}

@end
