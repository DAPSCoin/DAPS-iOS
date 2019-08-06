//
//  BRDapsTxDetailsViewController.m
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

#import "BRDapsTxDetailsViewController.h"
#import "BRPeerManager.h"
#import "BRWalletManager.h"
#import "BRPaymentRequest.h"
#import "BRBubbleView.h"
#import "UIImage+Utils.h"
#import "pivxwallet-Swift.h"
#import "RAGTextField-Swift.h"


@interface BRDapsTxDetailsViewController ()
@property (weak, nonatomic) IBOutlet UILabel *lblDestAddress;
@property (weak, nonatomic) IBOutlet UILabel *lblAmount;
@property (weak, nonatomic) IBOutlet UILabel *lblFee;
@property (weak, nonatomic) IBOutlet UILabel *lblBalance;
@property (weak, nonatomic) IBOutlet UILabel *lblStealthAddress;
@property (weak, nonatomic) IBOutlet UILabel *lblTransactionID;
@property (weak, nonatomic) IBOutlet UILabel *lblDate;
@property (weak, nonatomic) IBOutlet UILabel *lblTime;
@property (weak, nonatomic) IBOutlet UIButton *btnBack;

@end

@implementation BRDapsTxDetailsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationItem.title = @"Transaction History";
    
    [self addMenuButton];
    [[self.navigationController navigationBar] setTranslucent:FALSE];
    [[self.navigationController navigationBar] setShadowImage:[UIImage imageNamed:@""]];
    [[self.navigationController navigationBar] setBackgroundImage:[UIImage imageNamed:@""] forBarMetrics: UIBarMetricsDefault];
    
    self.lblDestAddress.text = self.strDestAddress;
    self.lblAmount.text = self.strAmount;
    self.lblFee.text = self.strFee;
    self.lblBalance.text = self.strBalance;
    self.lblStealthAddress.text = self.strStealthAddress;
    self.lblTransactionID.text = self.strTransactionID;
    self.lblDate.text = self.strDate;
    self.lblTime.text = self.strTime;
}

- (void)viewLayoutMarginsDidChange {
    [super viewLayoutMarginsDidChange];
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

- (IBAction)onBack:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}
@end
