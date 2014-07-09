//
//  TWConnection.m
//  TwilioSDK
//
//  Created by Ben Lee on 4/28/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import "TCConnection.h"
#import "TCConnectionInternal.h"

@implementation TCConnection

// Implementation note:
// To keep implementation details semi-private, alloc and allocWithZone
// actually return a TWConnectionInternal class that implements the methods
// specified in the TWConnection header.  This allows us to easily change 
// the class specification (add new private methods or change the class's 
// set of ivars) without having to change the public-facing headers.

+(id)alloc
{
	return (NSAllocateObject([TCConnectionInternal class], 0, nil));
}

+(id)allocWithZone:(NSZone *)zone
{
	return (NSAllocateObject([TCConnectionInternal class], 0, zone));	
}

// Stubs for method implementations handled by TWDeviceInternal.  These prevent
// warnings during compile.

@synthesize state;
@synthesize incoming;
@synthesize parameters;
@synthesize delegate;

-(void)accept
{
}

-(void)ignore
{
}

-(void)disconnect
{
}

-(BOOL)isMuted
{
	return NO;
}

-(void)setMuted:(BOOL)muted
{
}

-(void)reject
{
}

-(void)sendDigits:(NSString*)digits
{
}

@end
