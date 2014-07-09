#import <UIKit/UIKit.h>
#import "JCDialPad.h"
#import "PKTPhone.h"

@interface PKTCallViewController : UIViewController <JCDialPadDelegate>

@property (weak, nonatomic  ) PKTPhone *phone;
@property (nonatomic, strong) UILabel  * callStatusLabel;

+ (instancetype)presentCallViewWithNumber:(NSString *)number unanswered:(BOOL)unanswered phone:(PKTPhone *)phone;

- (void)callStarted:(NSString*)number unanswered:(BOOL)unanswered;
- (void)callConnected;
- (void)callEnded;
- (void)setMainText:(NSString *)text;

@end
