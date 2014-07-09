/*
 * Copyright (C) 2012 Twilio, Inc.
 * All rights reserved.
 */

#import <Foundation/Foundation.h>

#include <pj/log.h>
#include <pj/os.h>
#include <pj/compat/stdfileio.h>

PJ_DEF(void) pj_log_write(int level, const char *buffer, int len)
{
    PJ_CHECK_STACK();

    // NSLog() adds a timestamp, so chop off the one embedded in the log msg
    NSLog(@"PJSIP(%d): %.*s", level, len - 13, buffer + 13);
}
