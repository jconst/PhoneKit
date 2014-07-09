//
//  TCRosterEntry.m
//  TwilioSDK
//
//  Created by Brian Tarricone on 2/14/12.
//  Copyright (c) 2012 Twilio, Inc. All rights reserved.
//

#import "TCRosterEntry.h"
#import "TCPresenceEvent.h"

@implementation TCRosterEntry

@synthesize name = name_;
#if ENABLE_ADVANCED_PRESENCE
@synthesize status = status_;
@synthesize statusText = statusText;
#endif

+ (id)rosterEntryWithName:(NSString *)name
#if ENABLE_ADVANCED_PRESENCE
                   status:(NSString *)status
               statusText:(NSString *)statusText
#endif
{
    return [[[self alloc] initWithName:name
#if ENABLE_ADVANCED_PRESENCE
                                status:status
                            statusText:statusText
#endif
             ] autorelease];
}

- (id)initWithName:(NSString *)name
#if ENABLE_ADVANCED_PRESENCE
            status:(NSString *)status
        statusText:(NSString *)statusText
#endif
{
    if ((self = [super init]))
    {
        name_ = [name retain];
#if ENABLE_ADVANCED_PRESENCE
        status_ = [status retain];
        statusText_ = [statusText retain];
#endif
    }
    
    return self;
}

- (void)dealloc
{
    [name_ release];
#if ENABLE_ADVANCED_PRESENCE
    [status_ release];
    [statusText_ release];
#endif
    [super dealloc];
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[TCRosterEntry class]])
        return [name_ isEqualToString:((TCRosterEntry *)object).name];
    else if ([object isKindOfClass:[TCPresenceEvent class]])
        return [name_ isEqualToString:((TCPresenceEvent *)object).name];
    else
        return NO;
}

@end
