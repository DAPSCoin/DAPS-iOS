//
//  MenuController.swift
//  BreadWallet
//
//  Created by German Mendoza on 9/26/17.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//

import UIKit

class MenuController: BaseController {

    @IBOutlet weak var titleLabel1: UILabel!
    @IBOutlet weak var titleLabel2: UILabel!
    @IBOutlet weak var titleLabel3: UILabel!
    @IBOutlet weak var titleLabel4: UILabel!
    @IBOutlet weak var titleLabel5: UILabel!
    
    @IBOutlet weak var titleImg1: UIImageView!
    @IBOutlet weak var titleImg2: UIImageView!
    @IBOutlet weak var titleImg3: UIImageView!
    @IBOutlet weak var titleImg4: UIImageView!
    @IBOutlet weak var titleImg5: UIImageView!
    
    
    @IBOutlet weak var syncImageView: UIImageView!
//    @IBOutlet weak var syncLabel: UILabel!
//    @IBOutlet weak var versionLabel: UILabel!
    @IBOutlet weak var cotainerViewHeightConstraint: NSLayoutConstraint!
    var optionSelected:Int = 1
    
    var syncTimer:Timer? = nil;
    
    override func setup(){
        cotainerViewHeightConstraint.constant = K.main.height - 130
        selectTitle()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.syncStarted),
            name: Notification.Name.BRPeerManagerSyncStartedNotification,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.syncFinished),
            name: Notification.Name.BRPeerManagerSyncFinishedNotification,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.syncFailed),
            name: Notification.Name.BRPeerManagerSyncFailedNotification,
            object: nil)
    }
    
    override func viewDidLayoutSubviews() {
        var gradient:CAGradientLayer!
        gradient = CAGradientLayer.init()
        
        gradient.frame = self.view.bounds;
        gradient.colors = [UIColor.rgb(93, green: 0, blue: 86).cgColor, UIColor.rgb(13,  green: 0, blue: 17).cgColor];
        
        self.view.layer.insertSublayer(gradient, at: 0)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        var templateImage = titleImg1.image?.withRenderingMode(.alwaysTemplate)
        titleImg1.image = templateImage
        
        templateImage = titleImg2.image?.withRenderingMode(.alwaysTemplate)
        titleImg2.image = templateImage
        
        templateImage = titleImg3.image?.withRenderingMode(.alwaysTemplate)
        titleImg3.image = templateImage
        
        templateImage = titleImg4.image?.withRenderingMode(.alwaysTemplate)
        titleImg4.image = templateImage
        
        templateImage = titleImg5.image?.withRenderingMode(.alwaysTemplate)
        titleImg5.image = templateImage
        
        
        let dictionary = Bundle.main.infoDictionary!
        let version = dictionary["CFBundleShortVersionString"] as! String
//        versionLabel.text = "v" + version
    }
    
    /**
    * This method is called when the instance is dealocated in swift.s
    */
    deinit {
        NotificationCenter.default.removeObserver(self);
        stopTimer();
    }


    @IBAction func tappedMyWalletButton(_ sender: Any) {
        if optionSelected == 1 {
            slideMenuController()?.closeLeft()
            return
        }
        
        let homeController = RootController.shared
        let nav = UINavigationController(rootViewController: homeController)
        slideMenuController()?.changeMainViewController(nav, close: true)
        optionSelected = 1
        selectTitle()
    }
    @IBAction func tappedSendButton(_ sender: Any) {
        if optionSelected == 2 {
            slideMenuController()?.closeLeft()
            return
        }
//        let controller = AddressContactController()
        let controller = SendController.shared
        let navigation = UINavigationController(rootViewController: controller)
        slideMenuController()?.changeMainViewController(navigation, close: true)
        optionSelected = 2
        selectTitle()
    }
    @IBAction func tappedReceiveButton(_ sender: Any) {
        if optionSelected == 3 {
            slideMenuController()?.closeLeft()
            return
        }
        let controller = ReceiveController.shared
        let navigation = UINavigationController(rootViewController: controller)
        slideMenuController()?.changeMainViewController(navigation, close: true)
        optionSelected = 3
        selectTitle()
    }
    @IBAction func tappedHistoryButton(_ sender: Any) {
        if optionSelected == 4 {
            slideMenuController()?.closeLeft()
            return
        }
        let controller =  HistoryController.shared
        //let controller = TxHistoryController.shared
        let nav = UINavigationController(rootViewController: controller)
        slideMenuController()?.changeMainViewController(nav, close: true)
        optionSelected = 4
        selectTitle()
    }
    @IBAction func tappedSettingButton(_ sender: Any) {
        if optionSelected == 5 {
            slideMenuController()?.closeLeft()
            return
        }
        let controller =  SettingsController.shared
        //let controller = TxHistoryController.shared
        let nav = UINavigationController(rootViewController: controller)
        slideMenuController()?.changeMainViewController(nav, close: true)
        optionSelected = 5
        selectTitle()
    }
//    @IBAction func tappedDonationButton(_ sender: Any) {
//        if optionSelected == 4 {
//            slideMenuController()?.closeLeft()
//            return
//        }
//        let controller = DonationController(nibName:"Donation", bundle:nil)
//        let navigation = UINavigationController(rootViewController: controller)
//        slideMenuController()?.changeMainViewController(navigation, close: true)
//        optionSelected = 4
//        selectTitle()
//    }
    
    func selectTitle(){
        titleLabel1.textColor = UIColor.white
        titleLabel2.textColor = UIColor.white
        titleLabel3.textColor = UIColor.white
        titleLabel4.textColor = UIColor.white
        titleLabel5.textColor = UIColor.white
        
        titleImg1.tintColor = UIColor.white
        titleImg2.tintColor = UIColor.white
        titleImg3.tintColor = UIColor.white
        titleImg4.tintColor = UIColor.white
        titleImg5.tintColor = UIColor.white
        
        switch optionSelected {
        case 1:
            titleLabel1.textColor = K.color.c70fbff
            titleImg1.tintColor = K.color.c70fbff
            break
        case 2:
            titleLabel2.textColor = K.color.c70fbff
            titleImg2.tintColor = K.color.c70fbff
            break
        case 3:
            titleLabel3.textColor = K.color.c70fbff
            titleImg3.tintColor = K.color.c70fbff
            break
        case 4:
            titleLabel4.textColor = K.color.c70fbff
            titleImg4.tintColor = K.color.c70fbff
            break
        case 5:
            titleLabel5.textColor = K.color.c70fbff
            titleImg5.tintColor = K.color.c70fbff
            break
        default:
            print("default")
            break
        }
    }
    
    @objc func updateSync(){
        let progress:Double = (BRPeerManager.sharedInstance()?.syncProgress)!;
//        syncLabel.text = String.init(format: "Syncing %0.1f%%", (progress > 0.1 ? progress - 0.1 : 0.0)*111.0);
    }
    
    @objc func syncStarted(){
        print("Sync started!");
        
        updateSync();
        if (syncTimer == nil) {
            syncTimer = Timer.scheduledTimer(timeInterval: 7.0, target: self, selector: #selector(updateSync), userInfo: nil, repeats: true);
        }else{
            syncTimer?.fire();
        }
    }
    
    @objc func syncFinished(){
        print("Sync finished!");
        stopTimer();
//        syncLabel.text = "Synced";
    }
    
    func stopTimer() {
        syncTimer?.invalidate();
    }
    
    @objc func syncFailed(){
        print("Sync failed!");
//        syncLabel.text = "Not connection";
    }
    
    
}
