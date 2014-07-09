//
//  TwilioError.m
//  TwilioSDK
//
//  Created by Ben Lee on 6/14/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import "TwilioError.h"


@implementation TwilioError

@synthesize twilioError = twilioError_;
@synthesize sipError = sipError_;
@synthesize httpError = httpError_;
@synthesize iOSError = iOSError_;
@synthesize twilioErrorDescription = twilioErrorDescription_;

-(void)dealloc
{
	[twilioErrorDescription_ release];
	[iOSError_ release];
	
	[super dealloc];
}

-(NSError*)error
{
	NSError*				error = nil;
	NSMutableDictionary*	userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
	
	//	Order of importance is Twilio then SIP then HTTP then iOS
	if (twilioError_ != 0)
	{
		if (twilioErrorDescription_)
			[userInfo setObject:twilioErrorDescription_ forKey:NSLocalizedDescriptionKey];
		else
			[userInfo setObject:@"Twilio Services Error" forKey:NSLocalizedDescriptionKey];
		
		error = [NSError errorWithDomain:TwilioServicesErrorDomain code:twilioError_ userInfo:userInfo];
	}
	else if (sipError_ != 0)
	{
		[userInfo setObject:@"Status Code" forKey:NSLocalizedDescriptionKey];
		
		error = [NSError errorWithDomain:TwilioTransportErrorDomain code:sipError_ userInfo:userInfo];
	}
	else if (httpError_ != 0 && httpError_ != 200)
	{
		[userInfo setObject:@"Status Code" forKey:NSLocalizedDescriptionKey];
		
		error = [NSError errorWithDomain:TwilioHTTPErrorDomain code:httpError_ userInfo:userInfo];		
	}
	else if (iOSError_)
	{
		error = iOSError_;
	}

	return error;
}

-(id)initWithTwilioError:(int32_t)error description:(NSString*)description
{
	self = [super init];
	
	if (self)
	{
		twilioError_ = error;
		
		if (description)
			twilioErrorDescription_ = [[NSString alloc] initWithString:description];
	}
	
	return self;
}

-(id)initWithSipError:(int32_t)error
{
	self = [super init];
	
	if (self)
	{
		sipError_ = error;
	}
	
	return self;	
}

-(id)initWithHttpError:(int32_t)error
{
	self = [super init];
	
	if (self)
	{
		httpError_ = error;
	}
	
	return self;
}

-(id)initWithNSError:(NSError*)error
{
	self = [super init];
	
	if (self)
	{
		iOSError_ = [error retain];
	}
	
	return self;	
}

@end
