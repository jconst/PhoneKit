/*
 Copyright (c) 2010, Stig Brautaset.
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are
 met:

   Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

   Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

   Neither the name of the the author nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SBJsonStreamParserState.h"
#import "SBJsonStreamParser.h"

#define SINGLETON \
+ (id)sharedInstance { \
    static id state; \
    if (!state) state = [[self alloc] init]; \
    return state; \
}

@implementation TCSBJsonStreamParserState

+ (id)sharedInstance { return nil; }

- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
	return NO;
}

- (TCSBJsonStreamParserStatus)parserShouldReturn:(TCSBJsonStreamParser*)parser {
	return SBJsonStreamParserWaitingForData;
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {}

- (BOOL)needKey {
	return NO;
}

- (NSString*)name {
	return @"<aaiie!>";
}

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateStart

SINGLETON

- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
	return token == sbjson_token_array_start || token == sbjson_token_object_start;
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {

	TCSBJsonStreamParserState *state = nil;
	switch (tok) {
		case sbjson_token_array_start:
			state = [TCSBJsonStreamParserStateArrayStart sharedInstance];
			break;

		case sbjson_token_object_start:
			state = [TCSBJsonStreamParserStateObjectStart sharedInstance];
			break;

		case sbjson_token_array_end:
		case sbjson_token_object_end:
			if (parser.multi)
				state = parser.state;
			else
				state = [TCSBJsonStreamParserStateComplete sharedInstance];
			break;

		case sbjson_token_eof:
			return;

		default:
			state = [TCSBJsonStreamParserStateError sharedInstance];
			break;
	}


	parser.state = state;
}

- (NSString*)name { return @"before outer-most array or object"; }

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateComplete

SINGLETON

- (NSString*)name { return @"after outer-most array or object"; }

- (TCSBJsonStreamParserStatus)parserShouldReturn:(TCSBJsonStreamParser*)parser {
	return SBJsonStreamParserComplete;
}

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateError

SINGLETON

- (NSString*)name { return @"in error"; }

- (TCSBJsonStreamParserStatus)parserShouldReturn:(TCSBJsonStreamParser*)parser {
	return SBJsonStreamParserError;
}

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateObjectStart

SINGLETON

- (NSString*)name { return @"at beginning of object"; }

- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
	switch (token) {
		case sbjson_token_object_end:
		case sbjson_token_string:
			return YES;
			break;
		default:
			return NO;
			break;
	}
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {
	parser.state = [TCSBJsonStreamParserStateObjectGotKey sharedInstance];
}

- (BOOL)needKey {
	return YES;
}

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateObjectGotKey

SINGLETON

- (NSString*)name { return @"after object key"; }

- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
	return token == sbjson_token_keyval_separator;
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {
	parser.state = [TCSBJsonStreamParserStateObjectSeparator sharedInstance];
}

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateObjectSeparator

SINGLETON

- (NSString*)name { return @"as object value"; }

- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
	switch (token) {
		case sbjson_token_object_start:
		case sbjson_token_array_start:
		case sbjson_token_true:
		case sbjson_token_false:
		case sbjson_token_null:
		case sbjson_token_number:
		case sbjson_token_string:
			return YES;
			break;

		default:
			return NO;
			break;
	}
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {
	parser.state = [TCSBJsonStreamParserStateObjectGotValue sharedInstance];
}

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateObjectGotValue

SINGLETON

- (NSString*)name { return @"after object value"; }

- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
	switch (token) {
		case sbjson_token_object_end:
		case sbjson_token_separator:
			return YES;
			break;
		default:
			return NO;
			break;
	}
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {
	parser.state = [TCSBJsonStreamParserStateObjectNeedKey sharedInstance];
}


@end

#pragma mark -

@implementation TCSBJsonStreamParserStateObjectNeedKey

SINGLETON

- (NSString*)name { return @"in place of object key"; }

- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
    return sbjson_token_string == token;
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {
	parser.state = [TCSBJsonStreamParserStateObjectGotKey sharedInstance];
}

- (BOOL)needKey {
	return YES;
}

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateArrayStart

SINGLETON

- (NSString*)name { return @"at array start"; }

- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
	switch (token) {
		case sbjson_token_object_end:
		case sbjson_token_keyval_separator:
		case sbjson_token_separator:
			return NO;
			break;

		default:
			return YES;
			break;
	}
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {
	parser.state = [TCSBJsonStreamParserStateArrayGotValue sharedInstance];
}

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateArrayGotValue

SINGLETON

- (NSString*)name { return @"after array value"; }


- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
	return token == sbjson_token_array_end || token == sbjson_token_separator;
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {
	if (tok == sbjson_token_separator)
		parser.state = [TCSBJsonStreamParserStateArrayNeedValue sharedInstance];
}

@end

#pragma mark -

@implementation TCSBJsonStreamParserStateArrayNeedValue

SINGLETON

- (NSString*)name { return @"as array value"; }


- (BOOL)parser:(TCSBJsonStreamParser*)parser shouldAcceptToken:(tcsbjson_token_t)token {
	switch (token) {
		case sbjson_token_array_end:
		case sbjson_token_keyval_separator:
		case sbjson_token_object_end:
		case sbjson_token_separator:
			return NO;
			break;

		default:
			return YES;
			break;
	}
}

- (void)parser:(TCSBJsonStreamParser*)parser shouldTransitionTo:(tcsbjson_token_t)tok {
	parser.state = [TCSBJsonStreamParserStateArrayGotValue sharedInstance];
}

@end

