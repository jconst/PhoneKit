//
//  NSString+pj_str.h
//  TwilioSDK
//
//  Created by Rob Simutis on 8/25/11.
//  Copyright 2011 Twilio. All rights reserved.
//  Utility methods on NSString to convert back and forth to a pj_str_t
//  string type used by PJSIP.
//

#import <Foundation/Foundation.h>
#import <pjsua-lib/pjsua.h>


@interface NSString (pj_str)

-(pj_str_t)PJSTRString;

+(NSString*)stringWithPJStr:(pj_str_t)string;

@end
