//
//  BRDapsSendViewController.m
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

#import "BRDapsSendViewController.h"
#import "BRPeerManager.h"
#import "BRPaymentRequest.h"
#import "BRWalletManager.h"
#import "BRScanViewController.h"
#import "pivxwallet-Swift.h"
#import "RAGTextField-Swift.h"
#import "NSString+Bitcoin.h"
#import "NSString+Dash.h"


@interface BRDapsSendViewController ()
@property (weak, nonatomic) IBOutlet RAGTextField *txtDescription;
@property (weak, nonatomic) IBOutlet SwiftyMenu *listWalletAddress;
@property (weak, nonatomic) IBOutlet RAGTextField *txtAmount;
@property (weak, nonatomic) IBOutlet SwiftyMenu *listFee;
@property (weak, nonatomic) IBOutlet UIButton *btnSend;
@property (weak, nonatomic) IBOutlet UIButton *btnQRScan;
@property (strong, nonatomic) BRScanViewController *scanController;

@end

@implementation BRDapsSendViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationItem.title = @"Send Transaction";
    
    UITapGestureRecognizer* tapGesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(dismissNumKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
    
    [self addMenuButton];
    [[self.navigationController navigationBar] setTranslucent:FALSE];
    [[self.navigationController navigationBar] setShadowImage:[UIImage imageNamed:@""]];
    [[self.navigationController navigationBar] setBackgroundImage:[UIImage imageNamed:@""] forBarMetrics: UIBarMetricsDefault];
    
    OutlineView *bgView = [[OutlineView alloc] initWithFrame:CGRectMake(0, 0, self.txtDescription.frame.size.width, self.txtDescription.frame.size.height)];
    bgView.lineWidth = 1;
    bgView.lineColor = [UIColor rgb:131 green:250 blue:255 alpha:255];
    bgView.fillColor = UIColor.clearColor;
    bgView.cornerRadius = 6.0;
    [bgView setUserInteractionEnabled:NO];
    
    [self.txtDescription addSubview:bgView];
    [self.txtDescription sendSubviewToBack:bgView];
    self.txtDescription.textColor = UIColor.whiteColor;
    self.txtDescription.tintColor = UIColor.whiteColor;
    self.txtDescription.delegate = self;
    
    UIFont *updatedFont = [UIFont italicSystemFontOfSize:12.0];
    NSDictionary *attributes = @{ NSFontAttributeName : updatedFont, NSForegroundColorAttributeName : UIColor.whiteColor };
    self.txtDescription.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Description (optional)." attributes:attributes];
    self.txtDescription.placeholderColor = UIColor.whiteColor;
    
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
    
    [self.listFee setOptions:@[@"Slow (0.005x DAPS/KB)", @"Medium (0.5x DAPS/KB)", @"Faster (0.6x DAPS/KB)", @"Fast (0.9x DAPS/KB)"]];
    self.listFee.rowHeight = 35;
    self.listFee.listHeight = 180;
    self.listFee.selectedIndex = 0;
    self.listFee.placeHolderColor = UIColor.whiteColor;
    
    self.btnSend.layer.cornerRadius = 10;
    self.btnSend.clipsToBounds = YES;
    
    self.btnQRScan.layer.cornerRadius = 7;
    self.btnQRScan.clipsToBounds = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewLayoutMarginsDidChange {
    [super viewLayoutMarginsDidChange];
    
    [self.txtDescription layoutIfNeeded];
    [self.txtAmount layoutIfNeeded];
    for (UIView *view in self.txtDescription.subviews) {
        if ([view isKindOfClass:[OutlineView class]]) {
            [view setFrame:CGRectMake(0, 0, self.txtDescription.frame.size.width, self.txtDescription.frame.size.height)];
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

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (! self.scanController) {
        self.scanController = [self.storyboard instantiateViewControllerWithIdentifier:@"ScanViewController"];
    }
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

-(float)getFee {
    if (self.listFee.selectedIndex == 0)
        return 0.005;
    else if (self.listFee.selectedIndex == 1)
        return 0.5;
    else if (self.listFee.selectedIndex == 2)
        return 0.6;
    
    return 0.9;
}

- (void)resetQRGuide
{
    self.scanController.message.text = nil;
    self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide"];
}

- (void)updateListAddress:(NSString *)address {
    BOOL isFind = false;
    for (int i = 0; i < self.listWalletAddress.options.count; i++) {
        if ([self.listWalletAddress.options[i] isEqualToString:address]) {
            self.listWalletAddress.selectedIndex = i;
            isFind = true;
            break;
        }
    }
    
    if (!isFind) {
        NSMutableArray *tempArray = [NSMutableArray arrayWithArray:self.listWalletAddress.options];
        [tempArray addObject:address];
        self.listWalletAddress.options = tempArray;
        self.listWalletAddress.selectedIndex = self.listWalletAddress.options.count - 1;
        if (self.listWalletAddress.options.count >= 3)
            self.listWalletAddress.listHeight = 145;
        else if (self.listWalletAddress.options.count >= 2)
            self.listWalletAddress.listHeight = 110;
    }
}

- (void)updateDataWithRequest:(BRPaymentRequest *)request {
    [self updateListAddress:request.paymentAddress];
    self.txtDescription.text = request.label;
    self.txtAmount.text = [NSString stringWithFormat:@"%llu",request.amount];
}

- (IBAction)onSend:(id)sender {
    NSString *destAddress;
    UInt64 amount;
    float fee;
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    destAddress = self.listWalletAddress.options[self.listWalletAddress.selectedIndex];
    fee = [self getFee] * COIN;
    if (fee > manager.wallet.feePerKb)
        manager.wallet.feePerKb = fee;
    
    NSScanner *scanner = [NSScanner scannerWithString:self.txtAmount.text];
    [scanner scanUnsignedLongLong:&amount];
    
    BRTransaction *tx = [BRTransaction new];
    if (![manager.wallet SendToStealthAddress:destAddress :amount :tx :false :5]) {
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"couldn't make payment", nil)
                                     message:[NSString stringWithFormat:NSLocalizedString(@"make transaction error", nil)]
                                     preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* okButton = [UIAlertAction
                                   actionWithTitle:NSLocalizedString(@"ok", nil)
                                   style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction * action) {

                                   }];


        [alert addAction:okButton];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
}

- (IBAction)onQRScan:(id)sender {
    self.scanController.delegate = self;
//    self.scanController.transitioningDelegate = self;
    [self.navigationController presentViewController:self.scanController animated:YES completion:nil];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection
{
    for (AVMetadataMachineReadableCodeObject *codeObject in metadataObjects) {
        if (! [codeObject.type isEqual:AVMetadataObjectTypeQRCode]) continue;
        
        NSString *addr = [codeObject.stringValue stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BRPaymentRequest *request = [BRPaymentRequest requestWithString:addr];
        if ((request.isValid) || [addr isValidBitcoinPrivateKey] || [addr isValidDashPrivateKey] || [addr isValidDashBIP38Key]) {
            self.scanController.cameraGuide.image = [UIImage imageNamed:@"cameraguide-green"];
            [self.scanController stop];
            
            [self.navigationController dismissViewControllerAnimated:YES completion:^{
                [self resetQRGuide];
                [self updateDataWithRequest: request];
            }];
        }
        
        break;
    }
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
