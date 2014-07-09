//
//  TCStackTrace.m
//  TwilioSDK
//
//  Created by Michael Van Milligan on 12/6/12.
//
//

#import "TCStackTrace.h"

@implementation TCStackTrace

-(id)init
{
    if ( self = [super init] )
        return self;
    
    return nil;
}

- (void)dealloc
{
    [super dealloc];
}

+(NSString *)getStacktrace
{
    NSMutableString *syms = nil;
    NSString *stackShot = nil;
    int frames = 0;
    void *callstack[CALLSTACK_LENGTH];
    char **strs = NULL;
    
    frames = backtrace(callstack, 128);
    strs = backtrace_symbols(callstack, frames);
    
    syms = [[NSMutableString alloc] initWithCapacity:CALLSTACK_LENGTH];
    if (syms) {
        [syms appendFormat:@"\n"];
        for (int i = 0; i < frames; i++) {
            [syms appendFormat:@"%s\n", strs[i]];
        }
        
        stackShot = [NSString stringWithString:syms];
        [syms release];
    }
    
    return stackShot;
}

@end
