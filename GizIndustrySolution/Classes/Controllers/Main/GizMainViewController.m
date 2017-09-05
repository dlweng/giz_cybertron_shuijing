//
//  GizMainViewController.m
//  GizIndustrySolution
//
//  Created by Minus🍀 on 16/9/9.
//  Copyright © 2016年 Gizwits. All rights reserved.
//

#import <GizWifiSDK/GizWifiSDK.h>

#import "GizMainViewController.h"
#import "GizUserInfoViewController.h"
#import "GizMoreViewController.h"

#import "GizDeviceCell.h"
#import <WebKit/WebKit.h>
#import "GizNetTools.h"
#import "GizWeakScriptMessageDelegate.h"
#import "MenuView.h"
#import "SDAutoLayout.h"
#import "MBProgressHUD.h"
#import "GosTipView.h"
#import "GosAlertView.h"


#define MAX_VISIBLE_CELL_COUNT 3

//Open API定时接口
#define OPEN_API   @"http://api.gizwits.com"
#define POST_GET_APPPOINTMENT [NSString stringWithFormat:@"%@/app/devices/%@/scheduler",OPEN_API,self.currentDevice.did]
#define DELETE_UPDATE_APPPOINTMENT(TaskID) [NSString stringWithFormat:@"%@/app/devices/%@/scheduler/%@",OPEN_API,self.currentDevice.did,TaskID]

typedef NS_ENUM(NSInteger, GizMainLeftBarButtonStyle) {
    GizMainLeftBarDefaultButton = 0,    // 默认，点击后显示用户信息
    GizMainLeftBarBackButton = 1,       // 返回，点击后 h5 返回上一页
};

typedef NS_ENUM(NSInteger, GizMainRightBarButtonStyle) {
    GizMainRightBarDefaultButton = 1,    // 关机
    GizMainRightBarConfimButton = 2,       // 打钩
};

@interface GizMainViewController () <GizWifiSDKDelegate, GizWifiDeviceDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, GosAlertViewDelegate>
{
    // webView 是否加载了页面的标识，用于第一次加载完成后 主动获取设备状态，然后忽略后续页面加载完成的回调
    BOOL hasLoadedHTML;
    // html 加载之后才能进行 hash 跳转，但是 hash 跳转成功之后，没有任何方法回调，无法知道什么时候跳转成功
    // 因此，加个 timer，获取 js 方法，当不是 undefined 时，就当作跳转成功，然后更新设备状态。
    NSTimer *loadHTMLTimer;
}

@property (nonatomic, strong) UIView *titleView;            // 标题视图
@property (nonatomic, strong) UILabel *titleLabel;          // 标题label
@property (nonatomic, strong) UIImageView *arrowImageView;  // 箭头
@property (nonatomic, strong) UIButton *titleButton;        // 标题button（点击显示设备列表）

@property (nonatomic, assign) GizMainLeftBarButtonStyle leftBarButtonStyle; // 导航栏 左边按钮的功能
@property (nonatomic, assign) GizMainRightBarButtonStyle rightBarButtonStyle; // 导航栏 左边按钮的功能
@property (nonatomic, strong) UIBarButtonItem *userInfoBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *backBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *confimBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *powerBarButtonItem;


@property (weak, nonatomic) IBOutlet UIBarButtonItem *moreBarButtonItem;

@property (nonatomic, assign) NSInteger selectedDeviceIndex;            // 当前选中的设备

@property (strong, nonatomic) WKWebView *wkWebView;

@property (nonatomic, strong) NSMutableArray<GizWifiDevice *> *deviceArray;
@property (nonatomic, strong) GizWifiDevice *currentDevice;
@property (nonatomic, strong) MenuView *menuView;

@property (nonatomic, assign) BOOL lx1_Alarm;
@property (nonatomic, assign) BOOL lx2_Alarm;
@property (nonatomic, assign) BOOL lx3_Alarm;
@property (nonatomic, assign) BOOL lx4_Alarm;
@property (nonatomic, assign) BOOL lx5_Alarm;
@property (nonatomic, assign) BOOL water_Lacking;  // 缺水报警
@property (nonatomic, assign) BOOL water_Leakage;   //漏水报警

@end

@implementation GizMainViewController

@synthesize deviceArray;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self createTitleView];
    [self setupFirstDevice];
    self.leftBarButtonStyle = GizMainLeftBarDefaultButton;
    
    [GizWifiSDK sharedInstance].delegate = self;
    
    [self setupWKWebView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didBindDeviceNotification:) name:GizDidBindDeviceNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didUnbindDeviceNotification:) name:GizDidUnbindDeviceNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if ([deviceArray count] > self.selectedDeviceIndex) {
        self.currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
        self.titleLabel.text = self.currentDevice.customName;
        [self.titleLabel updateLayout];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [GizWifiSDK sharedInstance].delegate = self;
    [self setDeviceDelegates];
    
    if (hasLoadedHTML) {
        GizWifiDevice *currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
        
        [self js_didUpdateNetStatus:currentDevice status:currentDevice.netStatus];
        [self js_didUpdateStatus:currentDevice status:currentDevice.savedStatus];
        
        [currentDevice getDeviceStatus:nil];
    }
}

- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    self.menuView = nil;
    [MenuView clearMenuWithAnimation:YES];
    [self arrowImageViewAnimationToUp:NO];
}

- (void)dealloc
{
    [self.wkWebView.configuration.userContentController removeAllUserScripts];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupWKWebView{
    WKWebViewConfiguration *configuretion = [[WKWebViewConfiguration alloc] init];
    configuretion.preferences = [[WKPreferences alloc] init];
    configuretion.preferences.minimumFontSize = 10;
    configuretion.preferences.javaScriptEnabled = true;
    configuretion.processPool = [[WKProcessPool alloc] init];
    // 通过js与webview内容交互配置
    configuretion.userContentController = [[WKUserContentController alloc] init];
    
    //OC注册供JS调用的方法(JS调用OC)
    [configuretion.userContentController addScriptMessageHandler:[[GizWeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"sendCmd"];
    [configuretion.userContentController addScriptMessageHandler:[[GizWeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"getDeviceStatus"];
    [configuretion.userContentController addScriptMessageHandler:[[GizWeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"setLeftBarButton"];
    [configuretion.userContentController addScriptMessageHandler:[[GizWeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"setRightBarButton"];
    [configuretion.userContentController addScriptMessageHandler:[[GizWeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"addAppointment"];
    [configuretion.userContentController addScriptMessageHandler:[[GizWeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"deleteAppointment"];
    [configuretion.userContentController addScriptMessageHandler:[[GizWeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"updateAppointment"];
    [configuretion.userContentController addScriptMessageHandler:[[GizWeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"getAllAppointment"];
    [configuretion.userContentController addScriptMessageHandler:[[GizWeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"getAggregatedData"];
    // 默认是不能通过JS自动打开窗口的，必须通过用户交互才能打开
    configuretion.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    
    self.wkWebView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 64, GizScreenWidth, GizScreenHeight-64) configuration:configuretion];
    self.wkWebView.scrollView.bounces = NO;
    self.wkWebView.scrollView.showsVerticalScrollIndicator = NO;
    self.wkWebView.scrollView.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:self.wkWebView];
    hasLoadedHTML = NO;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    
    self.wkWebView.navigationDelegate = self;
    self.wkWebView.UIDelegate = self;
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.wkWebView loadRequest:request];
}

- (void)createTitleView
{
    self.titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, GizScreenWidth-60*2, 44)];
    self.navigationItem.titleView = self.titleView;
    
    self.titleLabel = [UILabel new];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.titleLabel.text = @"万和壁挂炉";
    self.titleLabel.textColor = GizNavigationBarTitleColor;
    [self.titleView addSubview:self.titleLabel];
    self.arrowImageView = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"arrow_down.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    self.arrowImageView.tintColor = GizNavigationBarTitleColor;
    [self.arrowImageView sizeToFit];
    self.arrowImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.titleView addSubview:self.arrowImageView];
    
    self.titleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.titleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.titleButton addTarget:self action:@selector(actionShowTopDeviceList:) forControlEvents:UIControlEventTouchUpInside];
    [self.titleView addSubview:self.titleButton];
    
    self.titleLabel.sd_layout.centerXEqualToView(self.titleView).centerYEqualToView(self.titleView);
    [self.titleLabel setSingleLineAutoResizeWithMaxWidth:GizScreenWidth-60*2-20];
    self.arrowImageView.sd_layout.centerYEqualToView(self.titleView).leftSpaceToView(self.titleLabel,5).heightIs(6).widthIs(10);
    self.titleButton.sd_layout.centerXEqualToView(self.titleView).centerYEqualToView(self.titleView).widthIs(GizScreenWidth-60*2-40).heightIs(40);;
}

- (void)setupFirstDevice
{
    deviceArray = [GizCommon sharedInstance].boundDeviceArray;
    self.selectedDeviceIndex = 0;
    for (GizWifiDevice *device in deviceArray) {
        if ([device.did isEqualToString:[self getLastUseDeviceDid]]) {
            self.selectedDeviceIndex = [deviceArray indexOfObject:device];
        }
    }
    GizWifiDevice *device = [deviceArray objectAtIndex:self.selectedDeviceIndex];
    
    self.titleLabel.text = device.customName;
    [self.titleLabel updateLayout];
    
    self.arrowImageView.hidden = (deviceArray.count == 1);
    self.titleButton.hidden = (deviceArray.count == 1);
}

#pragma mark - Getters

- (UIBarButtonItem *)userInfoBarButtonItem
{
    if (!_userInfoBarButtonItem) {
        _userInfoBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"navigation_btn_person"] style:UIBarButtonItemStylePlain target:self action:@selector(actionShowUserInfo:)];
    }
    
    return _userInfoBarButtonItem;
}

- (UIBarButtonItem *)backBarButtonItem
{
    if (!_backBarButtonItem) {
        _backBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"navigation_btn_back_normal.png"] style:UIBarButtonItemStylePlain target:self action:@selector(actionBackBarButtonClicked:)];
    }
    
    return _backBarButtonItem;
}

- (UIBarButtonItem *)confimBarButtonItem
{
    if (!_confimBarButtonItem) {
        _confimBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"nav_ic_submits"] style:UIBarButtonItemStylePlain target:self action:@selector(js_rightAction:)];
    }
    
    return _confimBarButtonItem;
}

- (UIBarButtonItem *)powerBarButtonItem
{
    if (!_powerBarButtonItem) {
        _powerBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"nav_ic_power"] style:UIBarButtonItemStylePlain target:self action:@selector(actionPowerButtonClicked:)];
    }
    
    return _powerBarButtonItem;
}

#pragma mark - Actions

- (IBAction)actionShowUserInfo:(id)sender
{
    GizUserInfoViewController *viewController = [UIStoryboard mi_instantiateViewControllerWithIdentifier:@"GizUserInfoViewController" storyboard:@"User"];
    
    [self.navigationController pushViewController:viewController animated:YES];
}

- (void)actionBackBarButtonClicked:(id)sender
{
    if (self.wkWebView.canGoBack) {
        [self.wkWebView goBack];
    }
    if (self.menuView.isShowMenu) {
        [MenuView clearMenuWithAnimation:YES];
    }
}

- (IBAction)actionShowMore:(id)sender
{
    GizMoreViewController *viewController = [UIStoryboard mi_instantiateViewControllerWithIdentifier:@"GizMoreViewController" storyboard:@"User"];
    viewController.device = [deviceArray count] > 0 ? [deviceArray objectAtIndex:self.selectedDeviceIndex] : nil;
    
    [self.navigationController pushViewController:viewController animated:YES];
}

- (void)actionPowerButtonClicked:(id)sender{
    [self.currentDevice write:@{
                                @"OnOffStatus":@"0",
                                }withSN:0];
    if (self.menuView.isShowMenu) {
        [MenuView clearMenuWithAnimation:YES];
    }
}

- (void)actionShowTopDeviceList:(id)sender
{
    if (!deviceArray || [deviceArray count] <= 0)
    {
        return;
    }
    if (self.menuView.isShowMenu) {
        [MenuView clearMenuWithAnimation:YES];
        [self arrowImageViewAnimationToUp:NO];
    }else{
        NSMutableArray *deviceListArray = [[NSMutableArray alloc] init];
        for (GizWifiDevice *device in self.deviceArray) {
            BOOL isSelect = NO;
            if ([device isEqual:self.currentDevice]) {
                isSelect = YES;
            }
            NSDictionary *dic = @{@"itemName":device.customName,@"selected":@(isSelect)};
            [deviceListArray addObject:dic];
        }
        JBWeakSelf(self);
        self.menuView = [MenuView createMenuWithFrame:CGRectMake(GizScreenWidth/2, 64, 0, 0) target:self.navigationController dataArray:deviceListArray itemsClickBlock:^(NSString *str, NSInteger tag) {
            GizWifiDevice *device = [deviceArray objectAtIndex:tag-1];
            [weakself selectedDevice:device];
            [MenuView clearMenuWithAnimation:YES];
            [weakself arrowImageViewAnimationToUp:NO];
        } backViewTap:^{
            [MenuView clearMenuWithAnimation:YES];
            [weakself arrowImageViewAnimationToUp:NO];
        }];
        [MenuView showMenuWithAnimation:YES];
        [self arrowImageViewAnimationToUp:YES];
    }
    
}

- (void)arrowImageViewAnimationToUp:(BOOL)up{
    CABasicAnimation *imageAnimation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    if (up) {
        imageAnimation.toValue = [NSNumber numberWithFloat:M_PI];
    }else{
        imageAnimation.toValue = [NSNumber numberWithFloat:M_PI*2];
    }
    imageAnimation.duration = 0.2;
    imageAnimation.repeatCount = 0;
    imageAnimation.autoreverses = NO;
    imageAnimation.removedOnCompletion = NO;
    imageAnimation.fillMode = kCAFillModeForwards;
    [self.arrowImageView.layer addAnimation:imageAnimation forKey:nil];
}

#pragma mark - Transactions

- (void)setDeviceDelegates
{
    deviceArray = [GizCommon sharedInstance].boundDeviceArray;
    
    for (GizWifiDevice *device in deviceArray)
    {
        device.delegate = self;
        
        if (!device.isSubscribed) {
            [device setSubscribe:GizProductSecret subscribed:YES];
        }
    }
}

- (void)getDevicesStatus
{
    for (GizWifiDevice *device in deviceArray)
    {
        if (device.netStatus == GizDeviceControlled)
        {
            NSLog(@"查询设备状态 %@ %@", device.macAddress, device.did);
            [device getDeviceStatus:nil];
        }
    }
}

#pragma mark - Notifications

- (void)didBindDeviceNotification:(NSNotification *)notification
{
    deviceArray = [GizCommon sharedInstance].boundDeviceArray;
    
    GizWifiDevice *currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
    self.titleLabel.text = currentDevice.customName;
    [self.titleLabel updateLayout];
    
    self.arrowImageView.hidden = (deviceArray.count == 1);
    self.titleButton.hidden = (deviceArray.count == 1);
}

- (void)didUnbindDeviceNotification:(NSNotification *)notification
{
    NSUInteger unbindDeviceIndex = [notification.object unsignedIntegerValue];
    
    deviceArray = [GizCommon sharedInstance].boundDeviceArray;
    
    self.arrowImageView.hidden = (deviceArray.count == 1);
    self.titleButton.hidden = (deviceArray.count == 1);
    
    if (self.selectedDeviceIndex == unbindDeviceIndex) {
        self.selectedDeviceIndex = 0;
        GizWifiDevice *device = deviceArray.firstObject;
        [device getDeviceStatus:nil];
        
        self.titleLabel.text = device.customName;
        [self.titleLabel updateLayout];
    }
}

- (void)selectedDevice:(GizWifiDevice*)device{
    self.selectedDeviceIndex = [self.deviceArray indexOfObject:device];
    self.titleLabel.text = device.customName;
    [self.titleLabel updateLayout];
    self.currentDevice = device;
    [self setLastUseDeviceDid:device.did];
    
    [self js_didUpdateNetStatus:device status:device.netStatus];
    [self js_didUpdateStatus:device status:device.savedStatus];
    [self js_getAllAppointment:nil];
    [device getDeviceStatus:nil];
}

- (NSString*)getLastUseDeviceDid{
    return [[NSUserDefaults standardUserDefaults] valueForKey:@"LastUseDevice"];
}

- (void)setLastUseDeviceDid:(NSString*)did{
    [[NSUserDefaults standardUserDefaults] setObject:did forKey:@"LastUseDevice"];
}

#pragma mark - WKWebViewDelegate
/*开始加载WKWebView时调用的方法*/
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation { // 类似UIWebView的 -webViewDidStartLoad:
    NSLog(@"WKWebView didStartProvisionalNavigation");
    [self showLoading:@"正在加载..."];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    NSLog(@"WKWebView didCommitNavigation");
}

/*结束加载WKWebView时调用的方法*/
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation { // 类似 UIWebView 的 －webViewDidFinishLoad:
    NSLog(@"WKWebView didFinishNavigation");
    
    if (!hasLoadedHTML)
    {
        hasLoadedHTML = YES;
        
        [self.wkWebView evaluateJavaScript:@"window.location.href = '#/mobile/deviceinfo'" completionHandler:^(id _Nullable response, NSError * _Nullable error) {
            
        }];
        
        loadHTMLTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(checkingContext) userInfo:nil repeats:YES];
        
        [self getDevicesStatus];
        /*
         GizWifiDevice *currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
         [self js_didUpdateNetStatus:currentDevice status:currentDevice.netStatus];*/
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_wkWebView.title.length > 0) {
                self.title = _wkWebView.title;
            }
        });
    });
    [self hideLoading];
}

/*加载WKWebView失败时调用的方法*/
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    // 类似 UIWebView 的- webView:didFailLoadWithError:
    NSLog(@"WKWebView didFailProvisionalNavigation");
    [self hideLoading];
    [self alertWithTitle:@"页面加载出错" message:error.localizedDescription confirm:@"确定"];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    
    NSLog(@"WKWebView decidePolicyForNavigationResponse");
    
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    decisionHandler(WKNavigationActionPolicyAllow);
    // 类似 UIWebView 的 -webView: shouldStartLoadWithRequest: navigationType:
    NSLog(@"WKWebView decidePolicyForNavigationAction: %@",navigationAction.request);
}

#pragma mark - WKScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSLog(@">>>> JS触发 %@", message.name);
    if ([message.name isEqualToString:@"sendCmd"]) {
        [self js_sendCmd:message.body];
    }
    else if ([message.name isEqualToString:@"getDeviceStatus"]) {
        [self js_getDeviceStatus:nil];
    }
    else if ([message.name isEqualToString:@"setLeftBarButton"]) {
        // 打印所传过来的参数，只支持NSNumber, NSString, NSDate, NSArray,
        // NSDictionary, and NSNull类型
        NSNumber *style = message.body;
        [self js_setLeftBarButton:style.integerValue];
    }
    else if ([message.name isEqualToString:@"setRightBarButton"]) {
        NSNumber *style = message.body;
        [self js_setRightBarButton:style.integerValue];
    }
    else if ([message.name isEqualToString:@"addAppointment"]) {
        [self js_addAppointment:message.body];
    }
    else if ([message.name isEqualToString:@"deleteAppointment"]) {
        [self js_deleteAppointment:message.body];
    }
    else if ([message.name isEqualToString:@"updateAppointment"]) {
        [self js_updateAppointment:message.body];
    }
    else if ([message.name isEqualToString:@"getAllAppointment"]) {
        [self js_getAllAppointment:nil];
    }
    else if ([message.name isEqualToString:@"getAggregatedData"]) {
        [self js_getAggregatedData:message.body];
    }
}

- (void)checkingContext
{
    [loadHTMLTimer invalidate];
    loadHTMLTimer = nil;
    
    GizWifiDevice *currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
    [self js_didUpdateNetStatus:currentDevice status:currentDevice.netStatus];
}

#pragma mark GizJSMethodExports (JS 调 OC 方法)
- (void)js_sendCmd:(NSString *)jsonString
{
    if ([jsonString length] <= 0) {
        return;
    }
    
    NSError *error = nil;
    
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *cmdDict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
    
    if (error) {
        NSLog(@"控制命令解析错误 %@ %@", error, jsonString);
        return;
    }
    
    NSLog(@"➔ JS 调 OC 方法 sendCmd 参数: %@", jsonString);
    
    GizWifiDevice *currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
    NSLog(@">>%@",currentDevice.savedStatus);
    
    [currentDevice write:cmdDict withSN:0];
}

- (void)js_getDeviceStatus:(id)object
{
    NSLog(@"➔ JS 调 OC 方法 getDeviceStatus");
    
    GizWifiDevice *currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
    [currentDevice getDeviceStatus:nil];
}

- (void)js_setLeftBarButton:(NSInteger)style
{
    NSLog(@"➔ JS 调 OC 方法 setLeftBarButton 参数: %@", @(style));
    
    if (style == self.leftBarButtonStyle) {
        return;
    }
    
    self.leftBarButtonStyle = style;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (style) {
            case GizMainLeftBarBackButton:
                self.navigationItem.leftBarButtonItem = self.backBarButtonItem;
                break;
                
            default:
                self.navigationItem.leftBarButtonItem = self.userInfoBarButtonItem;
                break;
        }
    });
}

- (void)js_setRightBarButton:(NSInteger)style
{
    NSLog(@"➔ JS 调 OC 方法 setRightBarButton 参数: %@", @(style));
    
    if (style == self.rightBarButtonStyle) {
        return;
    }
    
    self.rightBarButtonStyle = style;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (style) {
            case GizMainRightBarConfimButton:
                self.navigationItem.rightBarButtonItem = self.confimBarButtonItem;
                break;
                
            default:
                self.navigationItem.rightBarButtonItem = self.powerBarButtonItem;
                break;
        }
    });
}

- (void)js_addAppointment:(NSString *)appointment {
    if ([appointment length] <= 0) {
        return;
    }
    NSData *jsonData = [appointment dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:jsonData
                                                        options:NSJSONReadingMutableContainers
                                                          error:&err];
    NSLog(@"➔ JS 调 OC 方法 addAppointment 参数: %@", appointment);
    [GizNetTools postWithURLString:POST_GET_APPPOINTMENT parameters:dic success:^(NSDictionary *data) {
        [self js_appointmentSuccess:@"1" dataDic:data];
    } failure:^(NSError *error) {
        [self js_appointmentFail:@"1"];
    }];
}


- (void)js_deleteAppointment:(NSString *)appointmentId{
    if ([appointmentId length] <= 0) {
        return;
    }
    NSLog(@"➔ JS 调 OC 方法 deleteAppointment 参数: %@", appointmentId);
    [GizNetTools deleteWithURLString:DELETE_UPDATE_APPPOINTMENT(appointmentId) parameters:nil success:^(NSDictionary *data) {
        if (!data) {
            data = @{@"state":@"Success"};
        }
        [self js_appointmentSuccess:@"2" dataDic:data];
    } failure:^(NSError *error) {
        [self js_appointmentFail:@"2"];
    }];
}

- (void)js_updateAppointment:(NSString *)appointment{
    if ([appointment length] <= 0) {
        return;
    }
    NSLog(@"➔ JS 调 OC 方法 updateAppointment 参数: %@", appointment);
    NSError *error = nil;
    NSData *data = [appointment dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *appointmentDic = [[NSMutableDictionary alloc] init];
    appointmentDic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
    NSString *appointmentId = [appointmentDic valueForKey:@"id"];
    [GizNetTools putWithURLString:DELETE_UPDATE_APPPOINTMENT(appointmentId) parameters:appointmentDic success:^(NSDictionary *data) {
        [self js_appointmentSuccess:@"3" dataDic:data];
    } failure:^(NSError *error) {
        [self js_appointmentFail:@"3"];
    }];
}

- (void)js_getAllAppointment:(id)object{
    NSLog(@"➔ JS 调 OC 方法 getAllAppointment");
    [GizNetTools getWithURLString:POST_GET_APPPOINTMENT parameters:nil success:^(NSDictionary *data) {
        [self js_showAppointment:data];
        
    } failure:^(NSError *error) {
        [self js_appointmentFail:@"4"];
    }];
}

- (void)js_getAggregatedData:(NSString *)params {
    
    if ([params length] <= 0) {
        return;
    }
    
    NSLog(@"➔ JS 调 OC 方法 getAggregatedData 参数: %@", params);
    
    NSError *error = nil;
    NSData *data = [params dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
    
    GizWifiDevice *currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
    
    NSString *urlStr = [NSString stringWithFormat:@"%@/app/devdata/%@/agg_data", OPEN_API, currentDevice.did];
    
    [GizNetTools putWithURLString:urlStr parameters:dict success:^(NSDictionary *data) {
        [self js_getAggregatedDataSuccess:data];
    } failure:^(NSError *error) {
        NSLog(@"获取聚合数据失败: [%ld] %@", error.code, error.localizedDescription);
    }];
}

#pragma mark JS Methods (OC 调 JS 方法)
- (void)js_didUpdateStatus:(GizWifiDevice *)device status:(NSDictionary *)data
{
    if (!data || data.count == 0) {
        return;
    }
    
    NSDictionary *dataDict = data[@"data"];
    if (!dataDict || dataDict.count == 0) {
        return;
    }
    
    if ([deviceArray count] > 0 )
    {
        GizWifiDevice *currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
        
        if ([currentDevice isEqual:device])
        {
            NSString *status = [data mi_JSONString];
            
            NSLog(@"➔ OC 调 JS 方法 showFromDeviceResponse 参数: %@", status);
            if (!status) {
                NSLog(@"状态解析出错，不调用 JS 方法...");
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.wkWebView evaluateJavaScript:[NSString stringWithFormat:@"showFromDeviceResponse('%@')",status] completionHandler:^(id _Nullable response, NSError * _Nullable error) {
                    if (error)NSLog(@">>> OC调用JS - showFromDeviceResponse error:%@",error);
                }];
            });
        }
    }
}

- (void)js_didUpdateNetStatus:(GizWifiDevice *)device status:(GizWifiDeviceNetStatus)netStatus
{
    GizWifiDevice *currentDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
    
    if ([currentDevice isEqual:device])
    {
        NSInteger status = 0;
        
        switch (netStatus)
        {
            case GizDeviceOnline:
            case GizDeviceControlled:
                status = 1;
                break;
                
            case GizDeviceOffline:
            case GizDeviceUnavailable:
                status = 0;
                break;
        }
        
        NSDictionary *statusDict = @{@"isOnline": @(status)};
        //            NSDictionary *statusDict = @{@"isOnline": @(1)};
        NSString *statusJSON = [statusDict mi_JSONString];
        NSLog(@"➔ OC 调 JS 方法 showFromDeviceState 参数: %@", statusJSON);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.wkWebView evaluateJavaScript:[NSString stringWithFormat:@"showFromDeviceState('%@')",statusJSON] completionHandler:^(id _Nullable response, NSError * _Nullable error) {
                if (error)NSLog(@">>> OC调用JS - showFromDeviceState error:%@",error);
            }];
        });
    }
}

- (void)js_rightAction:(id)object{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.wkWebView evaluateJavaScript:@"rightAction()" completionHandler:^(id _Nullable response, NSError * _Nullable error) {
            if (error)NSLog(@">>> OC调用JS - rightAction error:%@",error);
        }];
    });
}

- (void)js_appointmentSuccess:(NSString *)status dataDic:(NSDictionary*)data{
    if (!data || data.count == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.wkWebView evaluateJavaScript:[NSString stringWithFormat:@"appointmentSuccess('%@','%@')",status,[data mi_JSONString]] completionHandler:^(id _Nullable response, NSError * _Nullable error) {
            if (error)NSLog(@">>> OC调用JS - appointmentSuccess error:%@",error);
        }];
    });
}

- (void)js_appointmentFail:(NSString *)status{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.wkWebView evaluateJavaScript:[NSString stringWithFormat:@"appointmentFail('%@')",status] completionHandler:^(id _Nullable response, NSError * _Nullable error) {
            if (error)NSLog(@">>> OC调用JS - appointmentFail error:%@",error);
        }];
    });
}

- (void)js_showAppointment:(NSDictionary *)appointments{
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:appointments
                                                       options:kNilOptions
                                                         error:&error];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData
                                                 encoding:NSUTF8StringEncoding];
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self.wkWebView evaluateJavaScript:[NSString stringWithFormat:@"showAppointment('%@')",jsonString] completionHandler:^(id _Nullable response, NSError * _Nullable error) {
            if (error)NSLog(@">>> OC调用JS - showAppointment error:%@",error);
        }];
    });
}

- (void)js_getAggregatedDataSuccess:(NSDictionary *)aggregatedData {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:aggregatedData
                                                       options:kNilOptions
                                                         error:&error];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData
                                                 encoding:NSUTF8StringEncoding];
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self.wkWebView evaluateJavaScript:[NSString stringWithFormat:@"getAggregatedDataSuccess('%@')",jsonString] completionHandler:^(id _Nullable response, NSError * _Nullable error) {
            if (error)NSLog(@">>> OC调用JS - getAggregatedDataSuccess error:%@",error);
        }];
    });
}


#pragma mark - GizWifiSDKDelegate

- (void)wifiSDK:(GizWifiSDK *)wifiSDK didDiscovered:(NSError *)result deviceList:(NSArray *)deviceList
{
    if (result.code == GIZ_SDK_SUCCESS)
    {
        NSLog(@"主页面 发现设备列表 %@", deviceList);
    }
}

#pragma mark - GizWifiDeviceDelegate

- (void)device:(GizWifiDevice *)device didSetSubscribe:(NSError *)result isSubscribed:(BOOL)isSubscribed
{
    if (result.code == GIZ_SDK_SUCCESS)
    {
        NSString *str = isSubscribed ? @"订阅成功" : @"取消订阅";
        NSLog(@"设备 %@ %@ %@", device.macAddress, device.did, str);
    }
    else
    {
        NSLog(@"设备 %@ %@  订阅出错 %@", device.macAddress, device.did, result);
    }
}

- (void)device:(GizWifiDevice *)device didUpdateNetStatus:(GizWifiDeviceNetStatus)netStatus
{
    NSArray *array = @[@"离线", @"在线", @"可控", @"不可用"];
    NSLog(@"设备 %@ %@ 网络状态改变: %@", device.macAddress, device.did, array[(int)netStatus]);
    
    if (netStatus == GizDeviceControlled)
    {
        NSLog(@"查询设备状态 %@ %@", device.macAddress, device.did);
        [device getDeviceStatus:nil];
    }
    
    GizWifiDevice *selectedDevice = [deviceArray objectAtIndex:self.selectedDeviceIndex];
    
    if ([selectedDevice isEqual:device])
    {
        [self js_didUpdateNetStatus:device status:device.netStatus];
    }
}

- (void)device:(GizWifiDevice *)device didReceiveData:(NSError *)result data:(NSDictionary *)dataMap withSN:(NSNumber *)sn
{
    
    if (result.code == GIZ_SDK_SUCCESS)
    {
        NSLog(@"设备 %@ %@ %@ 上报数据", device.macAddress, device.did, device.productName);
        NSLog(@"→ %@", dataMap);
        
        //**********************************************************************
        NSDictionary *alerts = dataMap[@"alerts"];
        if (alerts.count > 0)
        {
            NSNumber *LX1_Alarm = alerts[@"LX1_Alarm"];
            NSNumber *LX2_Alarm = alerts[@"LX2_Alarm"];
            NSNumber *LX3_Alarm = alerts[@"LX3_Alarm"];
            NSNumber *LX4_Alarm = alerts[@"LX4_Alarm"];
            NSNumber *LX5_Alarm = alerts[@"LX5_Alarm"];
            NSNumber *Water_Lacking = alerts[@"Water_Lacking"];
            NSNumber *Water_Leakage = alerts[@"Water_Leakage"];
            NSMutableString *alertStr = [NSMutableString string];
            if (LX1_Alarm.boolValue)
            {
                
                if (!self.lx1_Alarm) {
                    [alertStr appendFormat:@"滤芯1报警\n"];
                }
                self.lx1_Alarm = YES;
                
            }
            else
            {
                self.lx1_Alarm = NO;
            }
            if (LX2_Alarm.boolValue)
            {
                if (!self.lx2_Alarm) {
                    [alertStr appendFormat:@"滤芯2报警\n"];
                }
                self.lx2_Alarm = YES;
            }
            else
            {
                self.lx2_Alarm = NO;
            }
            if (LX3_Alarm.boolValue)
            {
                if (!self.lx3_Alarm) {
                    [alertStr appendFormat:@"滤芯3报警\n"];
                }
                self.lx3_Alarm = YES;
            }
            else
            {
                self.lx3_Alarm = NO;
            }
            if (LX4_Alarm.boolValue)
            {
                if (!self.lx4_Alarm) {
                    [alertStr appendFormat:@"滤芯4报警\n"];
                }
                self.lx4_Alarm = YES;
            }
            else
            {
                self.lx4_Alarm = NO;
            }
            if (LX5_Alarm.boolValue)
            {
                if (!self.lx5_Alarm) {
                    [alertStr appendFormat:@"滤芯5报警\n"];
                }
                self.lx5_Alarm = YES;
                
            }
            else
            {
                self.lx5_Alarm = NO;
            }
            if (Water_Lacking.boolValue)
            {
                if (!self.water_Lacking) {
                    [alertStr appendFormat:@"缺水报警\n"];
                }
                self.water_Lacking = YES;
            }
            else
            {
                self.water_Lacking = NO;
            }
            if (Water_Leakage.boolValue) {
                if (!self.water_Leakage) {
                    [alertStr appendFormat:@"漏水报警\n"];
                }
                self.water_Leakage = YES;
            }
            else
            {
                self.water_Leakage = NO;
            }
            
            if (alertStr.length > 0)
            {
                [self alertWithTitle:@"提示" message:[alertStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] confirm:@"确定"];
            }
        }
       
        //**********************************************************************
        
        NSMutableDictionary *statusDic = [dataMap valueForKey:@"data"];
        if (statusDic.count == 0) {
            return;
        }
        device.savedStatus = statusDic;
        [self js_didUpdateStatus:device status:dataMap];
    }
    else if(result.code == GIZ_SDK_REQUEST_TIMEOUT)
    {
        [device getDeviceStatus:nil];
    }
    else
    {
        NSLog(@"设备 %@ %@ 上报数据出错 %@", device.macAddress, device.did, result);
    }
}

- (void)device:(GizWifiDevice *)device didSetCustomInfo:(NSError *)result
{
    // SDK有bug，该方法回调，修改成功，这里 device.alias 还是修改之前的值，
    // 导致 self.titleLabel.text 显示的还是修改之前的设备名
    
    NSDictionary *dict = @{@"device": device,
                           @"result": result};
    
    [[NSNotificationCenter defaultCenter] postNotificationName:GizDeviceNameDidChangeNotification object:dict];
    
    NSUInteger index = [deviceArray indexOfObject:device];
    
    if (index != NSNotFound)
    {
        if (index == self.selectedDeviceIndex)
        {
            self.titleLabel.text = device.customName;
            [self.titleLabel updateLayout];
        }
    }
}

/**
 *  点击提示框按钮时 调用的代理方法
 *
 *  @param alertView 提示框对象
 *  @param isConfirm 按钮标识   YES: 表示确定按钮  NO: 表示取消按钮
 */
- (void)GosAlertViewDidDismissButton:(GosAlertView *)alertView withButton:(BOOL)isConfirm
{
    if (isConfirm)
    {
        [alertView hide:YES];
    }
}

@end
