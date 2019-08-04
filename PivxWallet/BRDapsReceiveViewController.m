//
//  BRDapsReceiveViewController.m
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

#import "BRDapsReceiveViewController.h"
#import "BRPeerManager.h"
#import "BRWalletManager.h"
#import "BRPaymentRequest.h"
#import "BRBubbleView.h"
#import "UIImage+Utils.h"
#import "pivxwallet-Swift.h"
#import "RAGTextField-Swift.h"


@interface BRDapsReceiveViewController ()
@property (weak, nonatomic) IBOutlet SwiftyMenu *listWalletAddress;
@property (weak, nonatomic) IBOutlet RAGTextField *txtPaymentID;
@property (weak, nonatomic) IBOutlet UIButton *btnGenerate;
@property (weak, nonatomic) IBOutlet UIButton *btnSubmit;
@property (weak, nonatomic) IBOutlet UIImageView *imgQRcode;
@property (weak, nonatomic) IBOutlet UILabel *txtQRcode;
@property (weak, nonatomic) IBOutlet RAGTextField *txtAmount;
@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;

@end

@implementation BRDapsReceiveViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationItem.title = @"Receive Transaction";
    
    UITapGestureRecognizer* tapGesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(dismissNumKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
    
    [self addMenuButton];
    [[self.navigationController navigationBar] setTranslucent:FALSE];
    [[self.navigationController navigationBar] setShadowImage:[UIImage imageNamed:@""]];
    [[self.navigationController navigationBar] setBackgroundImage:[UIImage imageNamed:@""] forBarMetrics: UIBarMetricsDefault];
    
    OutlineView *bgView = [[OutlineView alloc] initWithFrame:CGRectMake(0, 0, self.txtPaymentID.frame.size.width, self.txtPaymentID.frame.size.height)];
    bgView.lineWidth = 1;
    bgView.lineColor = [UIColor rgb:131 green:250 blue:255 alpha:255];
    bgView.fillColor = UIColor.clearColor;
    bgView.cornerRadius = 6.0;
    [bgView setUserInteractionEnabled:NO];
    
    [self.txtPaymentID addSubview:bgView];
    [self.txtPaymentID sendSubviewToBack:bgView];
    self.txtPaymentID.textColor = UIColor.whiteColor;
    self.txtPaymentID.tintColor = UIColor.whiteColor;
    self.txtPaymentID.delegate = self;
    
    UIFont *updatedFont = [UIFont italicSystemFontOfSize:12.0];
    NSDictionary *attributes = @{ NSFontAttributeName : updatedFont, NSForegroundColorAttributeName : UIColor.whiteColor };
    self.txtPaymentID.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Payment ID" attributes:attributes];
    self.txtPaymentID.placeholderColor = UIColor.whiteColor;
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSString *myAddress = manager.wallet.receiveStealthAddress;
    [self.listWalletAddress setOptions:@[myAddress]];
    self.listWalletAddress.rowHeight = 35;
    self.listWalletAddress.listHeight = 70;
    self.listWalletAddress.selectedIndex = 0;
    self.listWalletAddress.placeHolderColor = UIColor.whiteColor;
    
    bgView = [[OutlineView alloc] initWithFrame:CGRectMake(0, 0, self.txtAmount.frame.size.width, self.txtAmount.frame.size.height)];
    bgView.lineWidth = 1;
    bgView.lineColor = [UIColor rgb:131 green:250 blue:255 alpha:255];
    bgView.fillColor = UIColor.clearColor;
    bgView.cornerRadius = 6.0;
    [bgView setUserInteractionEnabled:NO];
    
    [self.txtAmount addSubview:bgView];
    [self.txtAmount sendSubviewToBack:bgView];
    self.txtAmount.textColor = UIColor.whiteColor;
    self.txtAmount.tintColor = UIColor.whiteColor;
    self.txtAmount.keyboardType = UIKeyboardTypeDecimalPad;
    self.txtAmount.delegate = self;
    
    self.btnSubmit.layer.cornerRadius = 10;
    self.btnSubmit.clipsToBounds = YES;
    
    self.btnGenerate.layer.cornerRadius = 7;
    self.btnGenerate.clipsToBounds = YES;
    
    self.imgQRcode.layer.cornerRadius = 7;
    self.imgQRcode.clipsToBounds = YES;
    self.imgQRcode.layer.borderColor = [UIColor colorWithRed:94 green:0 blue:87 alpha:255].CGColor;
    self.imgQRcode.layer.borderWidth = 1;
    self.imgQRcode.backgroundColor = UIColor.clearColor;
    
    self.txtQRcode.text = @"";
}

- (void)viewLayoutMarginsDidChange {
    [super viewLayoutMarginsDidChange];
    
    [self.txtPaymentID layoutIfNeeded];
    [self.txtAmount layoutIfNeeded];
    
    for (UIView *view in self.txtPaymentID.subviews) {
        if ([view isKindOfClass:[OutlineView class]]) {
            [view setFrame:CGRectMake(0, 0, self.txtPaymentID.frame.size.width, self.txtPaymentID.frame.size.height)];
            break;
        }
    }
    
    for (UIView *view in self.txtAmount.subviews) {
        if ([view isKindOfClass:[OutlineView class]]) {
            [view setFrame:CGRectMake(0, 0, self.txtAmount.frame.size.width, self.txtAmount.frame.size.height)];
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

- (IBAction)onSubmit:(id)sender {
    NSScanner *scanner = [NSScanner scannerWithString:self.txtAmount.text];
    unsigned long long amount = 0;
    [scanner scanUnsignedLongLong:&amount];
    
    NSString *paymentURL = [NSString stringWithFormat:@"dapscoin://%@?amount=%llu&label=%@",
                            self.listWalletAddress.options[self.listWalletAddress.selectedIndex],
                            amount,
                            self.txtPaymentID.text];
    self.txtQRcode.text = paymentURL;
    
    BRPaymentRequest *req = [BRPaymentRequest requestWithString:paymentURL];
    UIImage *image = [UIImage imageWithQRCodeData:req.data color:[CIColor colorWithRed:0.0 green:0.0 blue:0.0]];
    self.imgQRcode.image = [image resize:self.imgQRcode.frame.size withInterpolationQuality:kCGInterpolationNone];
    self.imgQRcode.backgroundColor = UIColor.whiteColor;
}

- (IBAction)onCopy:(id)sender {
    [UIPasteboard generalPasteboard].string = self.txtQRcode.text;
    [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"copied", nil)
                                                center:CGPointMake(self.view.bounds.size.width/2.0, self.view.bounds.size.height/2.0 - 130.0)] popIn]
                           popOutAfterDelay:2.0]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

-(void)dismissNumKeyboard
{
    [self.txtAmount resignFirstResponder];//Assuming that UITextField Object is textField
}
@end
