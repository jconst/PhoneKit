//
//  TCPresenceEvent.m
//  TwilioSDK
//
//  Created by Brian Tarricone on 1/4/12.
//  Copyright (c) 2012 Twilio, Inc. All rights reserved.
//

#import "TCPresenceEvent.h"
#import "TCPresenceEventPrivate.h"

@implementation TCPresenceEvent

@synthesize name;
@synthesize available;
#if ENABLE_ADVANCED_PRESENCE
@synthesize status;
@synthesize statusText;
#endif

+ (id)presenceEventWithName:(NSString *)name
                  available:(BOOL)available
#if ENABLE_ADVANCED_PRESENCE
                     status:(NSString *)status
                 statusText:(NSString *)statusText
#endif
{
    return [[[self alloc] initWithName:name
                             available:available
#if ENABLE_ADVANCED_PRESENCE
								status:status
                            statusText:statusText
#endif
			 ] 
			autorelease];
}

- (id)initWithName:(NSString *)_name
         available:(BOOL)_available
#if ENABLE_ADVANCED_PRESENCE
			status:(NSString *)_status
        statusText:(NSString *)_statusText
#endif
{
    if ((self = [super init]))
    {
        name = [_name retain];
        available = _available;
#if ENABLE_ADVANCED_PRESENCE
		status = [_status retain];
        statusText = [_statusText retain];
#endif
    }
    
    return self;
}

- (void)dealloc
{
    [name release];
#if ENABLE_ADVANCED_PRESENCE
	[status release];
    [statusText release];
#endif
    [super dealloc];
}

- (NSString *)description
{
#if ENABLE_ADVANCED_PRESENCE
	return [NSString stringWithFormat:@"<%@ %p name=%@, available=%s, status=%@, statusText=%@>",
            [[self class] description], self, name, available ? "YES" : "NO", status, statusText];
#else
	return [NSString stringWithFormat:@"<%@ %p name=%@, available=%s>",
            [[self class] description], self, name, available ? "YES" : "NO"];
#endif

}

@end
