//
//  PKTViewController.h
//  PhoneKit
//
//  Created by Joseph Constantakis on 07/08/2014.
//  Copyright (c) 2014 Joseph Constantakis. All rights reserved.
//

#import <UIKit/UIKit.h>

@class PKTCallViewController;

@interface PKTViewController : UIViewController

@property (strong, nonatomic) IBOutlet UITextField *calleeField;
@property (strong, nonatomic) IBOutlet UITextField *callerIdField;
@property (strong, nonatomic) PKTCallViewController *callViewController;

@end
