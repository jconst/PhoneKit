//
//  TCCall.h
//  TwilioSDK
//
//  Created by Chris Wendel on 7/12/12.
//  Copyright (c) 2012 Twilio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TCConnectionInternal.h"

@interface TCCall : NSObject
{
    TCConnectionInternal*    connection_;
    NSString*                sipUri_;
    
    pjsua_acc_id             accountId_;
    pj_str_t*                uri_;
    pjsua_msg_data*          msgData_;
    pjsua_call_id            callId_;
}
@property (readonly) TCConnectionInternal *connection;
@property (readonly) NSString *sipUri;
@property (readonly) pjsua_acc_id accountId;
@property (readonly) pj_str_t* uri;
@property (readonly) pjsua_msg_data* msgData;
@property (readonly) pjsua_call_id callId;

-(id)initWithConnection:(TCConnectionInternal*) connection accountId:(pjsua_acc_id)accountId uri:(pj_str_t*)uri messageData:(pjsua_msg_data*)messageData sipUri:(NSString*)sipUri;
-(void)makeCall;
-(void)hangup;
-(void)muteCall:(BOOL)muted;
-(void)sendReinvite;
-(void)sendDigits:(pj_str_t*)stringStruct;

@end
