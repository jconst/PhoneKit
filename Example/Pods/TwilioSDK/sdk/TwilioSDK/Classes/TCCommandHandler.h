//
//  CommandHandler.h
//  TwilioSDK
//
//  Created by Rob Simutis on 12/19/11.
//  Copyright (c) 2011 Twilio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TCCommands.h"
#include <semaphore.h>
#include <dispatch/dispatch.h>

@interface TCCommandHandler : NSObject
{
@private
    dispatch_semaphore_t    semaphore;
    dispatch_queue_t        commandQ; // queue for access to the commands array to prevent multi-threaded access
    NSMutableArray          *commands;
    NSThread                *commandThread;
    void                    *threadDesc; // type hidden so it can't be obviously abused by nefarious developers.
}

+(TCCommandHandler*)sharedInstance;

-(void)shutdown;
-(void)postCommand:(TCCommand*)command; // sem_post's to the thread semaphore, pop from commands queue


@end
