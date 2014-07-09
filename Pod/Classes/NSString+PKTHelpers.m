#import "ReactiveCocoa.h"
#import "NSString+PKTHelpers.h"

@implementation NSString (Helpers)

- (BOOL)isClientNumber
{
    // if any of the chars in this charset appear in the input string,
    // then it's a client.  otherwise, the string is made up of only
    // numbers, +, and -, which makes it a phone number.
    // (This isn't precise E.164 parsing, but it's easy enough for now.)
	NSCharacterSet* charsetForClient = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789+-()  "] invertedSet];
	
	return [self rangeOfCharacterFromSet:charsetForClient].location != NSNotFound;
}

- (BOOL)equalsPhoneNumber:(NSString *)number
{
    if (!number)
        return NO;
    
    NSString* stripped = [number stripToDigitsOnly];
    
    return [[self stripToDigitsOnly] isEqualToString:stripped];
}

- (BOOL)isGreaterThanVersion:(NSString *)version
{
    NSArray *me = [self componentsSeparatedByString:@"."];
    NSArray *them = [version componentsSeparatedByString:@"."];
    
    NSEnumerator *zipped = [[RACSequence zip:@[me.rac_sequence, them.rac_sequence]] objectEnumerator];
    
    for (RACTuple *next in zipped) {
        RACTupleUnpack(NSString *myPart, NSString *theirPart) = next;
        NSInteger myNum    = [myPart integerValue];
        NSInteger theirNum = [theirPart integerValue];
        if (myNum != theirNum) {
            return myNum > theirNum;
        }
    }
    // all comparable version parts match at this point; check lengths
    if (me.count != them.count) {
        //assume the longer one is greater (e.g. 1.0.1 vs 1.0)
        return me.count > them.count;
    }
    return NO;
}

- (NSString *)stripToDigitsOnly
{
    NSCharacterSet *strippingCharSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [[self componentsSeparatedByCharactersInSet:strippingCharSet] componentsJoinedByString:@""];
}

- (NSString *)sanitizeNumber
{
    if ([self isClientNumber]) {
        NSRange clientColonRange = [self rangeOfString:@"client:"];
        if (clientColonRange.location != NSNotFound &&
            [self length] > clientColonRange.location + clientColonRange.length) {
            return [self substringFromIndex:clientColonRange.location + clientColonRange.length];
        } else {
            return self;
        }
    } else {
        return [self stripToDigitsOnly];
    }
}

- (NSString *)sanitizeNumberAndRemoveOne
{
    NSString *sanitized = self;
    sanitized = [self sanitizeNumber];
    if (!sanitized.length)
        return sanitized;
    if (![self isClientNumber] &&
        [sanitized characterAtIndex:0] == '1') {
        sanitized = [sanitized substringFromIndex:1];
    }
    return sanitized;
}

@end
