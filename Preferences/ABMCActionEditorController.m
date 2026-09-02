#import "ABMCActionEditorController.h"
#import "../ABMCLogger.h"

#define ABMCEditorDomain @"com.huynguyen.actionbuttonmulticlick"
#define ABMCEditorNotice @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

static NSDictionary *ABMCEditorTitles(void) {
    return @{@"default":@"系统默认",@"flashlight":@"手电筒",@"camera":@"相机",@"silent":@"静音模式",@"screenshot":@"屏幕截图",@"lock":@"锁定屏幕",@"respring":@"重启桌面",@"controlCenter":@"控制中心",@"notificationCenter":@"通知中心",@"spotlight":@"聚焦搜索",@"screenRecord":@"屏幕录制",@"mediaPlayPause":@"播放暂停",@"mediaPrevious":@"上一首歌",@"mediaNext":@"下一首歌",@"closeApps":@"关闭应用",@"url:weixin://scanqrcode":@"微信扫一扫",@"url:weixin://widget/pay":@"微信付款码",@"url:alipay://platformapi/startapp?appId=10000007":@"支付宝扫一扫",@"url:alipay://platformapi/startapp?appId=20000056":@"支付宝付款码"};
}

@interface ABMCActionEditorController ()
@property(nonatomic,copy) NSString *preferenceKey;
@property(nonatomic,copy) NSString *actionID;
@property(nonatomic,strong) UITextField *titleField;
@property(nonatomic,strong) UITextField *iconField;
@property(nonatomic,strong) UITextField *bundleField;
@end

@implementation ABMCActionEditorController
- (instancetype)initWithPreferenceKey:(NSString *)key actionID:(NSString *)actionID {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) { _preferenceKey=[key copy]; _actionID=[actionID copy]; }
    return self;
}
- (UITextField *)field:(NSString *)placeholder text:(NSString *)text {
    UITextField *field=[UITextField new]; field.placeholder=placeholder; field.text=text;
    field.autocapitalizationType=UITextAutocapitalizationTypeNone; field.autocorrectionType=UITextAutocorrectionTypeNo;
    return field;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"编辑动作";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"存储" style:UIBarButtonItemStyleDone target:self action:@selector(save:)];
    CFPropertyListRef raw=CFPreferencesCopyValue(CFSTR("actionMetadata"),(__bridge CFStringRef)ABMCEditorDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    NSDictionary *all=raw?(__bridge_transfer NSDictionary *)raw:@{}; NSDictionary *item=[all[_actionID] isKindOfClass:[NSDictionary class]]?all[_actionID]:@{};
    NSString *fallback=ABMCEditorTitles()[_actionID] ?: ([_actionID hasPrefix:@"app:"]?[_actionID substringFromIndex:4]:_actionID);
    self.titleField=[self field:@"标题（必填）" text:item[@"title"] ?: fallback];
    self.iconField=[self field:@"图标：仅支持 SF 符号（可选）" text:item[@"icon"]];
    self.bundleField=[self field:@"应用标识符：Bundle ID（可选）" text:[_actionID hasPrefix:@"app:"]?[_actionID substringFromIndex:4]:item[@"appBundle"]];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 3; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"动作详情"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[UITableViewCell new]; UITextField *field=@[self.titleField,self.iconField,self.bundleField][path.row];
    field.frame=CGRectMake(16,0,CGRectGetWidth(tableView.bounds)-32,56); field.autoresizingMask=UIViewAutoresizingFlexibleWidth; [cell.contentView addSubview:field];
    return cell;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { return 56.0; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"图标仅支持 SF Symbols；应用标识符用于打开应用动作。留空时保留原动作。"; }
- (void)save:(id)sender {
    NSString *title=[self.titleField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *icon=[self.iconField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *bundle=[self.bundleField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length) return;
    if (icon.length && ![UIImage systemImageNamed:icon]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"图标无效" message:@"请输入有效的 SF Symbols 名称。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; return;
    }
    NSString *newID=([_actionID hasPrefix:@"app:"] && bundle.length)?[@"app:" stringByAppendingString:bundle]:_actionID;
    CFPropertyListRef raw=CFPreferencesCopyValue(CFSTR("actionMetadata"),(__bridge CFStringRef)ABMCEditorDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    NSDictionary *old=raw?(__bridge_transfer NSDictionary *)raw:@{}; NSMutableDictionary *all=[NSMutableDictionary dictionaryWithDictionary:[old isKindOfClass:[NSDictionary class]]?old:@{}];
    NSMutableDictionary *entry=[NSMutableDictionary dictionaryWithDictionary:[all[_actionID] isKindOfClass:[NSDictionary class]]?all[_actionID]:@{}]; entry[@"title"]=title;
    if(icon.length) entry[@"icon"]=icon; else [entry removeObjectForKey:@"icon"];
    if(bundle.length) entry[@"appBundle"]=bundle; else [entry removeObjectForKey:@"appBundle"];
    all[newID]=entry; if(![newID isEqual:_actionID]) [all removeObjectForKey:_actionID];
    CFPreferencesSetValue(CFSTR("actionMetadata"),(__bridge CFPropertyListRef)all,(__bridge CFStringRef)ABMCEditorDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    if(![newID isEqual:_actionID]) CFPreferencesSetValue((__bridge CFStringRef)self.preferenceKey,(__bridge CFPropertyListRef)newID,(__bridge CFStringRef)ABMCEditorDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)ABMCEditorDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    ABMCLog(@"Action editor saved key=%@ old=%@ new=%@ title=%@ icon=%@ bundle=%@",self.preferenceKey,_actionID,newID,title,icon,bundle);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge CFStringRef)ABMCEditorNotice,NULL,NULL,YES);
    [self.navigationController popViewControllerAnimated:YES];
}
@end
