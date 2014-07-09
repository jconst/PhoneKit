//
//  PJSIPAccountInfo.m
//  TwilioSDK
//
//  Created by Ben Lee on 5/28/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import "PJSIPAccountInfo.h"


@implementation PJSIPAccountInfo

@synthesize host = host_;
@synthesize accountId = accountId_;

-(id)init
{
	self = [super init];
	
	if (self)
	{
		accountId_ = -1;
	}
	
	return self;
}

-(void)dealloc
{
	[host_ release];
	
	[super dealloc];
}

-(pjsua_acc_config*)accountConfig
{
	return &accountConfig_;
}

@end
