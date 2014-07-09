//
//  PJSIPAccountInfo.h
//  TwilioSDK
//
//  Created by Ben Lee on 5/28/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <pjsua-lib/pjsua.h>

@interface PJSIPAccountInfo : NSObject
{
	NSString*			host_;
	pjsua_acc_config	accountConfig_;
	pjsua_acc_id		accountId_;
}

@property (retain) NSString* host;
@property (readonly) pjsua_acc_config* accountConfig;
@property (assign) pjsua_acc_id	accountId;

@end
