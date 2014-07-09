//
//  TWDevice.m
//  TwilioSDK
//
//  Created by Ben Lee on 4/27/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import "TCDevice.h"
#import "TCDeviceInternal.h"

@implementation TCDevice

// Implementation note:
// To keep implementation details semi-private, alloc and allocWithZone
// actually return a TWDeviceInternal class that implements the methods
// specified in the TWDevice header.  This allows us to easily change 
// the class specification (add new private methods or change the class's 
// set of ivars) without having to change the public-facing headers.

+(id)alloc
{
	return (NSAllocateObject([TCDeviceInternal class], 0, nil));
}

+(id)allocWithZone:(NSZone *)zone
{
	return (NSAllocateObject([TCDeviceInternal class], 0, zone));	
}

// Stubs for method implementations handled by TWDeviceInternal.  These prevent
// warnings during compile.

@synthesize state;
@synthesize capabilities;
@synthesize delegate;
@synthesize incomingSoundEnabled;
@synthesize outgoingSoundEnabled;
@synthesize disconnectSoundEnabled;

-(id)initWithCapabilityToken:(NSString*)capabilityToken delegate:(id<TCDeviceDelegate>) delegate
{
	return nil;
}

// deprecated: remove for final release
-(id)initWithCapabilitiesToken:(NSString*)capabilityToken delegate:(id<TCDeviceDelegate>) delegate
{
	return nil;
}

-(void)listen
{
}

-(void)unlisten
{
}

-(void)updateCapabilityToken:(NSString*)capabilityToken
{
}

-(TCConnection*) connect:(NSDictionary*)parameters delegate:(id<TCConnectionDelegate>) delegate
{
	return nil;
}

-(void)disconnectAll
{
}

#if 0

// NOTE: the following is the API documentation, maintained here for easy retrieval later.

/** Updates the device's presence status on the server.
 
 @param status A short status string from an arbitrary enumeration of status types.
 
 @param statusText A descriptive status message
 
 @returns None
 */
-(void)setPresenceStatus:(NSString *)status statusText:(NSString *)statusText;


-(void)setPresenceStatus:(NSString *)status statusText:(NSString *)statusText
{
    
}
#endif
@end
