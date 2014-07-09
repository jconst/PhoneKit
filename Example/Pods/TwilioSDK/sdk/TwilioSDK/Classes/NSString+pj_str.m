//
//  NSString+pj_str.m
//  TwilioSDK
//
//  Created by Rob Simutis on 8/25/11.
//  Copyright 2011 Twilio. All rights reserved.
//

#import "NSString+pj_str.h"

#define kMaxStrLenBytes 1024*8 // restrict to a reasonable size.
								// this prevents crashers from out of memory
								// when invalid pj_str_ts get passed in that 
								// have been previously dealloc'ed.  
								// strings coming out of PJSIP are rarely over 1 kB.
	

@implementation NSString (pj_str)

-(pj_str_t)PJSTRString
{
	char* utf8String = (char*)[self UTF8String];
	return pj_str(utf8String);
}

+(NSString*)stringWithPJStr:(pj_str_t)string
{
	NSString* theString = nil;
	if ( string.slen != 0 && string.slen < kMaxStrLenBytes ) 
	{
		char* value = malloc(string.slen+1);
		if ( value )
		{
			strlcpy(value, string.ptr, string.slen+1);
			theString = [NSString stringWithCString:value encoding:NSUTF8StringEncoding];
			free(value);
		}

	}
	
#if DEBUG
	if ( !theString && string.slen > kMaxStrLenBytes )
		NSLog(@"Invalid pj_str_t passed in"); // can set breakpoint here for when this happens to try to trace root cause.  
											  // TODO: is there easy way to break into debugger on iOS like on OS X?
#endif
	
	return theString;
}


@end
