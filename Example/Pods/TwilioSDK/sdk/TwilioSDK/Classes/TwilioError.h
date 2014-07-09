//
//  TwilioError.h
//  TwilioSDK
//
//  Created by Ben Lee on 6/14/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import <Foundation/Foundation.h>

#define TwilioServicesErrorDomain	@"TwilioServicesErrorDomain"
#define TwilioTransportErrorDomain	@"TwilioTransportErrorDomain"
#define TwilioHTTPErrorDomain		@"TwilioHTTPErrorDomain"


// This enum covers errors that may be exposed to the end user.
// See https://sites.google.com/a/twilio.com/wiki/engineering/teams/client-team/chunder/developers-corner/implementation-details/error-codes.

enum ETwilioErrors
{
	eTwilioError_GenericError = 31000,
	eTwilioError_ApplicationNotFound = 31001,
	eTwilioError_ConnectionDeclined = 31002,
	eTwilioError_ConnectionTimeout = 31003,
	eTwilioError_MalformedRequest = 31100,
	eTwilioError_GenericAuthorizationError = 31201,
	eTwilioError_NotAValidJWTToken = 31204,
};

@interface TwilioError : NSObject 
{
	int32_t		twilioError_;
	NSString*	twilioErrorDescription_;
	
	int32_t		sipError_;
	
	int32_t		httpError_;
	
	NSError*	iOSError_;
}

@property (assign) int32_t twilioError;
@property (retain) NSString* twilioErrorDescription;
@property (assign) int32_t sipError;
@property (assign) int32_t httpError;
@property (retain) NSError* iOSError;

-(NSError*)error;

-(id)initWithTwilioError:(int32_t)error description:(NSString*)description;
-(id)initWithSipError:(int32_t)error;
-(id)initWithHttpError:(int32_t)error;
-(id)initWithNSError:(NSError*)error;

@end
