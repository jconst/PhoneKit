//
//  TCRosterEntry.h
//  TwilioSDK
//
//  Created by Brian Tarricone on 2/14/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Twilio.h"  // for ENABLE_ADVANCED_PRESENCE

@interface TCRosterEntry : NSObject
{
@private
	NSString *name_;
#if ENABLE_ADVANCED_PRESENCE
	NSString *status_;
	NSString *statusText_;
#endif
}

+ (id)rosterEntryWithName:(NSString *)name
#if ENABLE_ADVANCED_PRESENCE
				   status:(NSString *)status
			   statusText:(NSString *)statusText
#endif
;

- (id)initWithName:(NSString *)name
#if ENABLE_ADVANCED_PRESENCE
			status:(NSString *)status
		statusText:(NSString *)statusText
#endif
;

@property (nonatomic, readonly) NSString *name;
#if ENABLE_ADVANCED_PRESENCE 
@property (nonatomic, retain)   NSString *status;
@property (nonatomic, retain)   NSString *statusText;
#endif

@end
