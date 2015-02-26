//
//  Copyright 2011-2015 Twilio. All rights reserved.
//
//  Use of this software is subject to the terms and conditions of the 
//  Twilio Terms of Service located at http://www.twilio.com/legal/tos
//

#import "TCConnection.h"
#import "TCConnectionDelegate.h"
#import "TCDevice.h"
#import "TCDeviceDelegate.h"
#import "TCPresenceEvent.h"

@interface TwilioClient : NSObject 

typedef NS_ENUM(NSInteger, TCLogLevel) {
    TC_LOG_OFF = 0,
    TC_LOG_ERROR,
    TC_LOG_WARN,
    TC_LOG_INFO,
    TC_LOG_DEBUG,
    TC_LOG_VERBOSE
};

@property (nonatomic, readonly) NSString* version;

+(id)sharedInstance;
-(void)setLogLevel:(TCLogLevel)level;

@end

