//
//  TCPresenceEventPrivate.h
//  TwilioSDK
//
//  Created by Brian Tarricone on 1/4/12.
//  Copyright (c) 2012 Twilio, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TCPresenceEvent.h"
#import "Twilio.h"  // for ENABLE_ADVANCED_PRESENCE

@interface TCPresenceEvent (TwilioPrivate)

#if ENABLE_ADVANCED_PRESENCE // enhanced presence, not ready for prime time
@property (nonatomic, readonly) NSString *status;
@property (nonatomic, readonly) NSString *statusText;
#endif

+ (id)presenceEventWithName:(NSString *)name
                  available:(BOOL)available
#if ENABLE_ADVANCED_PRESENCE
                     status:(NSString *)status
                 statusText:(NSString *)statusText
#endif
;

- (id)initWithName:(NSString *)name
         available:(BOOL)available
#if ENABLE_ADVANCED_PRESENCE
            status:(NSString *)status
        statusText:(NSString *)statusText
#endif
		;



@end