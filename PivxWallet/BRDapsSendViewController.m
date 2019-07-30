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
#import "BRWalletManager.h"
#import "pivxwallet-Swift.h"
#import "RAGTextField-Swift.h"


@interface BRDapsSendViewController ()
@property (weak, nonatomic) IBOutlet RAGTextField *txtDescription;
@property (weak, nonatomic) IBOutlet SwiftyMenu *listWalletAddress;

@end

@implementation BRDapsSendViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationItem.title = @"Send Transaction";
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
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
    
    UIFont *updatedFont = [UIFont italicSystemFontOfSize:12.0];
    NSDictionary *attributes = @{ NSFontAttributeName : updatedFont, NSForegroundColorAttributeName : UIColor.whiteColor };
    self.txtDescription.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Description (optional)." attributes:attributes];
    self.txtDescription.placeholderColor = UIColor.whiteColor;

    [self.listWalletAddress setOptions:@[@"abc"]];
    self.listWalletAddress.rowHeight = 35;
    self.listWalletAddress.listHeight = 70;
    self.listWalletAddress.placeHolderColor = UIColor.whiteColor;
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

@end
