#import <Foundation/Foundation.h>

#ifdef COCOAPODS_POD_AVAILABLE_Mantle
# import "Mantle.h"
# define PKT_MODEL MTLModel
#else
# define PKT_MODEL NSObject
#endif

@interface PKTCallRecord : PKT_MODEL

@property (nonatomic, assign) BOOL           incoming;
@property (nonatomic, assign) BOOL           missed;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, strong) NSDate         *startTime;
@property (nonatomic, strong) NSString       *number;
@property (nonatomic, strong) NSString       *city;
@property (nonatomic, strong) NSString       *state;

@end
