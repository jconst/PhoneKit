//
//  PKTViewController.m
//  PhoneKit
//
//  Created by Joseph Constantakis on 07/08/2014.
//  Copyright (c) 2014 Joseph Constantakis. All rights reserved.
//

#import "PKTViewController.h"
#import "UIView+FrameAccessor.h"
#import "PKTPhone.h"

@interface PKTViewController ()

@end

@implementation PKTViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    PKTPho
    
    UIButton *callButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    callButton.frame = CGRectMake(0, 0, 100, 50);
    callButton.center = self.view.center;
    [callButton addTarget:self action:@selector(didTapCall:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)didTapCall:(id)sender
{
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
