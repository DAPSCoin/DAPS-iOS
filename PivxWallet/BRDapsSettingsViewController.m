//
//  BRDapsSettingsViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "BRDapsSettingsViewController.h"
#import "BRPeerManager.h"
#import "BRWalletManager.h"
#import "BRBubbleView.h"
#import "pivxwallet-Swift.h"
#import "RAGTextField-Swift.h"


@interface BRDapsSettingsViewController ()
@property (weak, nonatomic) IBOutlet RAGTextField *txtOldpass;
@property (weak, nonatomic) IBOutlet RAGTextField *txtNewpass;
@property (weak, nonatomic) IBOutlet RAGTextField *txtConfirmpass;
@property (weak, nonatomic) IBOutlet UIButton *btnSubmit;
@property (weak, nonatomic) IBOutlet UIButton *btnShowPhrase;


@end

@implementation BRDapsSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationItem.title = @"Settings";
    
    UITapGestureRecognizer* tapGesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(dismissNumKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
    
    [self addMenuButton];
    [[self.navigationController navigationBar] setTranslucent:FALSE];
    [[self.navigationController navigationBar] setShadowImage:[UIImage imageNamed:@""]];
    [[self.navigationController navigationBar] setBackgroundImage:[UIImage imageNamed:@""] forBarMetrics: UIBarMetricsDefault];
 
    OutlineView *bgView = [[OutlineView alloc] initWithFrame:CGRectMake(0, 0, self.txtOldpass.frame.size.width, self.txtOldpass.frame.size.height)];
    bgView.lineWidth = 1;
    bgView.lineColor = [UIColor rgb:131 green:250 blue:255 alpha:255];
    bgView.fillColor = UIColor.clearColor;
    bgView.cornerRadius = 6.0;
    [bgView setUserInteractionEnabled:NO];
    
    [self.txtOldpass addSubview:bgView];
    [self.txtOldpass sendSubviewToBack:bgView];
    self.txtOldpass.textColor = UIColor.whiteColor;
    self.txtOldpass.tintColor = UIColor.whiteColor;
    self.txtOldpass.keyboardType = UIKeyboardTypeDecimalPad;
    
    bgView = [[OutlineView alloc] initWithFrame:CGRectMake(0, 0, self.txtNewpass.frame.size.width, self.txtNewpass.frame.size.height)];
    bgView.lineWidth = 1;
    bgView.lineColor = [UIColor rgb:131 green:250 blue:255 alpha:255];
    bgView.fillColor = UIColor.clearColor;
    bgView.cornerRadius = 6.0;
    [bgView setUserInteractionEnabled:NO];
    
    [self.txtNewpass addSubview:bgView];
    [self.txtNewpass sendSubviewToBack:bgView];
    self.txtNewpass.textColor = UIColor.whiteColor;
    self.txtNewpass.tintColor = UIColor.whiteColor;
    self.txtNewpass.keyboardType = UIKeyboardTypeDecimalPad;
    
    bgView = [[OutlineView alloc] initWithFrame:CGRectMake(0, 0, self.txtConfirmpass.frame.size.width, self.txtConfirmpass.frame.size.height)];
    bgView.lineWidth = 1;
    bgView.lineColor = [UIColor rgb:131 green:250 blue:255 alpha:255];
    bgView.fillColor = UIColor.clearColor;
    bgView.cornerRadius = 6.0;
    [bgView setUserInteractionEnabled:NO];
    
    [self.txtConfirmpass addSubview:bgView];
    [self.txtConfirmpass sendSubviewToBack:bgView];
    self.txtConfirmpass.textColor = UIColor.whiteColor;
    self.txtConfirmpass.tintColor = UIColor.whiteColor;
    self.txtConfirmpass.keyboardType = UIKeyboardTypeDecimalPad;
    
    self.btnSubmit.layer.cornerRadius = 10;
    self.btnSubmit.clipsToBounds = YES;
    
    self.btnShowPhrase.layer.cornerRadius = 10;
    self.btnShowPhrase.clipsToBounds = YES;
    
}

- (void)viewLayoutMarginsDidChange {
    [super viewLayoutMarginsDidChange];
    
    [self.txtOldpass layoutIfNeeded];
    [self.txtNewpass layoutIfNeeded];
    [self.txtConfirmpass layoutIfNeeded];
    
    for (UIView *view in self.txtOldpass.subviews) {
        if ([view isKindOfClass:[OutlineView class]]) {
            [view setFrame:CGRectMake(0, 0, self.txtOldpass.frame.size.width, self.txtOldpass.frame.size.height)];
            break;
        }
    }
    
    for (UIView *view in self.txtNewpass.subviews) {
        if ([view isKindOfClass:[OutlineView class]]) {
            [view setFrame:CGRectMake(0, 0, self.txtNewpass.frame.size.width, self.txtNewpass.frame.size.height)];
            break;
        }
    }
    
    for (UIView *view in self.txtConfirmpass.subviews) {
        if ([view isKindOfClass:[OutlineView class]]) {
            [view setFrame:CGRectMake(0, 0, self.txtConfirmpass.frame.size.width, self.txtConfirmpass.frame.size.height)];
            break;
        }
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    
}

-(void)addMenuButton {
    UIImage *image = [UIImage imageNamed:@"burger"];
    self.navigationItem.hidesBackButton = TRUE;
    UIBarButtonItem *menuButton = [[UIBarButtonItem alloc] initWithImage:image
                                                                   style:UIBarButtonItemStylePlain target:self action:@selector(tappedMenuButton)];
    [menuButton setTintColor: UIColor.whiteColor];
    self.navigationItem.leftBarButtonItem = menuButton;
}

-(void)tappedMenuButton{
    [Utils openLeftMenu];
}

-(void)dismissNumKeyboard
{
    [self.txtOldpass resignFirstResponder];
    [self.txtNewpass resignFirstResponder];
    [self.txtConfirmpass resignFirstResponder];
}
@end
