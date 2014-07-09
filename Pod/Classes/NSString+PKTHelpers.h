@interface NSString (PKTHelpers)

- (BOOL)isClientNumber;
- (BOOL)equalsPhoneNumber:(NSString *)number;
- (BOOL)isGreaterThanVersion:(NSString *)version;
- (NSString *)stripToDigitsOnly;
- (NSString *)sanitizeNumber;
- (NSString *)sanitizeNumberAndRemoveOne;

@end
