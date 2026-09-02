#import "ABMCLinkEditorController.h"
#import "../ABMCLogger.h"

#define ABMCLinkDomain @"com.huynguyen.actionbuttonmulticlick"
#define ABMCLinkNotice @"com.huynguyen.actionbuttonmulticlick/prefsChanged"

@interface ABMCLinkEditorController ()
@property(nonatomic,copy) NSString *key;
@property(nonatomic,copy) NSString *oldURL;
@property(nonatomic,strong) UITextField *titleField;
@property(nonatomic,strong) UITextField *iconField;
@property(nonatomic,strong) UITextField *urlField;
@property(nonatomic,strong) UISwitch *browserSwitch;
@end

@implementation ABMCLinkEditorController

- (instancetype)initWithPreferenceKey:(NSString *)key existingURL:(NSString *)url {
    if ((self=[super init])) { _key=[key copy]; _oldURL=[url copy]; }
    return self;
}

- (UITextField *)makeField:(NSString *)placeholder text:(NSString *)text keyboard:(UIKeyboardType)keyboard {
    UITextField *field=[UITextField new]; field.placeholder=placeholder; field.text=text; field.keyboardType=keyboard;
    field.borderStyle=UITextBorderStyleRoundedRect; field.autocapitalizationType=UITextAutocapitalizationTypeNone; field.autocorrectionType=UITextAutocorrectionTypeNo;
    return field;
}

- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=[UIColor systemGroupedBackgroundColor]; self.title=_oldURL.length?@"编辑链接":@"自定义链接";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"存储" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    BOOL presetMode = [self.key isEqualToString:@"presetLinks"];
    CFStringRef storageKey = presetMode ? CFSTR("presetLinks") : CFSTR("customLinks");
    CFPropertyListRef raw=CFPreferencesCopyValue(storageKey,(__bridge CFStringRef)ABMCLinkDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost); NSArray *links=raw?(__bridge_transfer NSArray *)raw:@[]; NSDictionary *found=nil;
    for (NSDictionary *item in [links isKindOfClass:[NSArray class]] ? links : @[]) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        if ([item[@"url"] isEqual:_oldURL]) { found=item; break; }
    }
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds]; scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:scroll];
    UIView *content=[UIView new]; content.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor], [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor], [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor], [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
    UILabel *header=[UILabel new]; header.text=@"链接详情"; header.textColor=[UIColor secondaryLabelColor]; header.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; header.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:header];
    self.titleField=[self makeField:@"标题（必填）" text:found[@"title"] keyboard:UIKeyboardTypeDefault]; self.iconField=[self makeField:@"图标：SF 符号或应用 Bundle ID（可选）" text:found[@"icon"] keyboard:UIKeyboardTypeDefault]; self.urlField=[self makeField:@"链接（必填）" text:_oldURL keyboard:UIKeyboardTypeURL];
    for (UITextField *field in @[self.titleField,self.iconField,self.urlField]) { field.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:field]; }
    UILabel *browserLabel=[UILabel new]; browserLabel.text=@"跳转浏览器"; browserLabel.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:browserLabel]; self.browserSwitch=[UISwitch new]; self.browserSwitch.on=[found[@"browser"] boolValue]; self.browserSwitch.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:self.browserSwitch];
    UILabel *note=[UILabel new]; note.numberOfLines=0; note.textColor=[UIColor secondaryLabelColor]; note.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; note.text=@"链接占位符：\n- @@@：打开链接前输入关键词并替换占位符。\n- $$$：读取剪贴板；剪贴板为空时请求输入。\n图标支持 SF Symbols 或应用 Bundle ID；留空使用 Safari 图标。"; note.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:note];
    [NSLayoutConstraint activateConstraints:@[[header.topAnchor constraintEqualToAnchor:content.topAnchor constant:28],[header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],[header.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],[self.titleField.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:14],[self.titleField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],[self.titleField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],[self.titleField.heightAnchor constraintEqualToConstant:52],[self.iconField.topAnchor constraintEqualToAnchor:self.titleField.bottomAnchor constant:10],[self.iconField.leadingAnchor constraintEqualToAnchor:self.titleField.leadingAnchor],[self.iconField.trailingAnchor constraintEqualToAnchor:self.titleField.trailingAnchor],[self.iconField.heightAnchor constraintEqualToConstant:52],[self.urlField.topAnchor constraintEqualToAnchor:self.iconField.bottomAnchor constant:10],[self.urlField.leadingAnchor constraintEqualToAnchor:self.titleField.leadingAnchor],[self.urlField.trailingAnchor constraintEqualToAnchor:self.titleField.trailingAnchor],[self.urlField.heightAnchor constraintEqualToConstant:100],[browserLabel.topAnchor constraintEqualToAnchor:self.urlField.bottomAnchor constant:18],[browserLabel.leadingAnchor constraintEqualToAnchor:self.titleField.leadingAnchor],[browserLabel.centerYAnchor constraintEqualToAnchor:self.browserSwitch.centerYAnchor],[self.browserSwitch.trailingAnchor constraintEqualToAnchor:self.titleField.trailingAnchor],[self.browserSwitch.topAnchor constraintEqualToAnchor:self.urlField.bottomAnchor constant:10],[note.topAnchor constraintEqualToAnchor:self.browserSwitch.bottomAnchor constant:24],[note.leadingAnchor constraintEqualToAnchor:self.titleField.leadingAnchor],[note.trailingAnchor constraintEqualToAnchor:self.titleField.trailingAnchor],[note.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-30]]];
}

- (void)save {
    NSString *title=[self.titleField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; NSString *url=[self.urlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; NSString *icon=[self.iconField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *parsed=[NSURL URLWithString:url]; if (!title.length || !url.length || !parsed.scheme.length) { UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"无法存储" message:@"请填写标题和有效链接。" preferredStyle:UIAlertControllerStyleAlert]; [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; return; }
    BOOL presetMode = [self.key isEqualToString:@"presetLinks"];
    CFStringRef storageKey = presetMode ? CFSTR("presetLinks") : CFSTR("customLinks");
    CFPropertyListRef raw=CFPreferencesCopyValue(storageKey,(__bridge CFStringRef)ABMCLinkDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost); NSArray *saved=raw?(__bridge_transfer NSArray *)raw:@[]; NSMutableArray *result=[NSMutableArray array];
    for (id object in [saved isKindOfClass:[NSArray class]] ? saved : @[]) {
        if (![object isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *item = object;
        if (![item[@"url"] isEqual:_oldURL]) [result addObject:item];
    }
    [result addObject:@{@"title":title,@"icon":icon?:@"",@"url":url,@"browser":@(self.browserSwitch.on)}];
    CFPreferencesSetValue(storageKey,(__bridge CFPropertyListRef)result,(__bridge CFStringRef)ABMCLinkDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    if (!presetMode) CFPreferencesSetValue((__bridge CFStringRef)self.key,(__bridge CFPropertyListRef)[@"customURL:" stringByAppendingString:url],(__bridge CFStringRef)ABMCLinkDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)ABMCLinkDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    _oldURL = [url copy];
    ABMCLog(@"Link editor saved mode=%@ key=%@ title=%@ url=%@ browser=%@",presetMode?@"preset":@"custom",self.key,title,url,self.browserSwitch.on?@"on":@"off"); CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),(__bridge CFStringRef)ABMCLinkNotice,NULL,NULL,YES); [self.view endEditing:YES];
}
@end
