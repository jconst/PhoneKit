//
//  TCStackTrace.h
//  TwilioSDK
//
//  Created by Michael Van Milligan on 12/6/12.
//
//

#import <Foundation/Foundation.h>

#include <execinfo.h>
#include <stdio.h>

#define CALLSTACK_LENGTH    (128)

@interface TCStackTrace : NSObject
{
@private
    // Empty for now, we may want to expand this object to include errors.
}

+(NSString *)getStacktrace;

@end
