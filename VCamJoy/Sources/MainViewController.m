/*
 * MainViewController.m — VCamJoy (NovaCam style)
 * - SYSTEM STATUS + preview
 * - WIFI LINK: nhập IP, START WIFI MODE
 * - LOCAL MEDIA: chọn ảnh/video từ thư viện, phát loop
 * - Bật Camera Ảo toggle
 * - ColorSync (60Hz) toggle
 */
#import "MainViewController.h"
#import "VCamReceiver.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

#define HEX(h) [UIColor colorWithRed:((h>>16)&0xFF)/255.0 green:((h>>8)&0xFF)/255.0 blue:(h&0xFF)/255.0 alpha:1]
#define CBGBASE  HEX(0x050508)
#define CBGCARD  HEX(0x0d0d13)
#define CGREEN   HEX(0x00ff88)
#define CPINK    HEX(0xff00cc)
#define CCYAN    HEX(0x00ccff)
#define CRED     HEX(0xff3344)
#define CAMBER   HEX(0xf59e0b)
#define CMUTED   HEX(0x555566)
#define CWHITE   [UIColor whiteColor]
#define CFONT    @"Menlo-Regular"
#define CFONTB   @"Menlo-Bold"
static NSString *const kSuite=@"com.vcamjoy.prefs";

@interface MainViewController()
    <NSURLSessionDataDelegate,UIImagePickerControllerDelegate,UINavigationControllerDelegate>
@property (strong) NSURLSession *ses; @property (strong) NSURLSessionDataTask *task;
@property (strong) NSMutableData *buf; @property (assign) BOOL wifiOn;
@property (strong) UIImage *localImg; @property (strong) AVPlayer *player;
@property (strong) AVPlayerLayer *playerLayer; @property (assign) BOOL playing;
@property (strong) NSString *mediaName; @property (assign) BOOL vcamOn;
@property (strong) AVCaptureSession *capSes; @property (strong) CADisplayLink *csLink;
@property (strong) UILabel *lblStatus; @property (strong) UILabel *lblConn;
@property (strong) UITextField *ipField; @property (strong) UIButton *wifiBtn;
@property (strong) UILabel *lblMedia; @property (strong) UIButton *btnPlay;
@property (strong) UISwitch *vcamSw; @property (strong) UISwitch *csSw;
@property (strong) UIImageView *prevImg; @property (strong) UILabel *fpsLbl;
@property (strong) UIView *prevCont;
@property (assign) NSUInteger fpsN; @property (assign) NSTimeInterval fpsT;
@end
static NSData *kSOI,*kEOI;

@implementation MainViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBarHidden=YES;
    self.view.backgroundColor=CBGBASE;
    uint8_t s[]={0xFF,0xD8},e[]={0xFF,0xD9};
    kSOI=[NSData dataWithBytes:s length:2]; kEOI=[NSData dataWithBytes:e length:2];
    self.buf=[NSMutableData data];
    [self buildUI]; [self loadPrefs];
    UITapGestureRecognizer *t=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(dismissKB)];
    t.cancelsTouchesInView=NO; [self.view addGestureRecognizer:t];
}
- (void)dismissKB{[self.view endEditing:YES];}

- (void)buildUI {
    CGFloat W=self.view.bounds.size.width, cw=W-32;
    UIScrollView *sv=[[UIScrollView alloc]initWithFrame:self.view.bounds];
    sv.backgroundColor=CBGBASE;
    sv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:sv];
    UIView *c=[[UIView alloc]initWithFrame:CGRectMake(0,0,W,1600)];
    c.backgroundColor=CBGBASE; [sv addSubview:c];
    CGFloat y=50;

    // Title
    UILabel *tl=[[UILabel alloc]initWithFrame:CGRectMake(16,y,200,38)];
    tl.text=@"VCamJoy"; tl.textColor=CGREEN; tl.font=[UIFont fontWithName:CFONTB size:28];
    [c addSubview:tl]; y+=38;
    UILabel *sub=[[UILabel alloc]initWithFrame:CGRectMake(16,y,cw,16)];
    sub.text=@"> VIRTUAL CAMERA v2.0 _"; sub.textColor=CMUTED;
    sub.font=[UIFont fontWithName:CFONT size:10]; [c addSubview:sub]; y+=26;

    // STATUS card
    CGFloat prevH=cw*9/16;
    UIView *sc=[self card:CGRectMake(16,y,cw,prevH+86) color:CWHITE title:@"SYSTEM STATUS"];
    [c addSubview:sc];
    self.lblStatus=[[UILabel alloc]initWithFrame:CGRectMake(14,34,cw-120,16)];
    self.lblStatus.text=@"CONNECTION"; self.lblStatus.textColor=CMUTED;
    self.lblStatus.font=[UIFont fontWithName:CFONT size:10]; [sc addSubview:self.lblStatus];
    self.lblConn=[[UILabel alloc]initWithFrame:CGRectMake(cw-110,34,96,16)];
    self.lblConn.text=@"STANDBY"; self.lblConn.textColor=CMUTED;
    self.lblConn.font=[UIFont fontWithName:CFONTB size:10];
    self.lblConn.textAlignment=NSTextAlignmentRight; [sc addSubview:self.lblConn];
    self.prevCont=[[UIView alloc]initWithFrame:CGRectMake(14,56,cw-28,prevH)];
    self.prevCont.backgroundColor=HEX(0x030306); self.prevCont.layer.cornerRadius=8;
    self.prevCont.clipsToBounds=YES; [sc addSubview:self.prevCont];
    self.prevImg=[[UIImageView alloc]initWithFrame:self.prevCont.bounds];
    self.prevImg.contentMode=UIViewContentModeScaleAspectFill; self.prevImg.clipsToBounds=YES;
    [self.prevCont addSubview:self.prevImg];
    UILabel *ph=[[UILabel alloc]initWithFrame:self.prevCont.bounds];
    ph.text=@"NO FEED"; ph.textColor=CMUTED; ph.textAlignment=NSTextAlignmentCenter;
    ph.font=[UIFont fontWithName:CFONT size:12]; ph.tag=77; [self.prevCont addSubview:ph];
    self.fpsLbl=[[UILabel alloc]initWithFrame:CGRectMake(6,4,80,14)];
    self.fpsLbl.textColor=CGREEN; self.fpsLbl.font=[UIFont fontWithName:CFONT size:9];
    [self.prevCont addSubview:self.fpsLbl];
    y+=prevH+86+8;

    // WIFI card
    UIView *wc=[self card:CGRectMake(16,y,cw,192) color:CPINK title:@"WIFI LINK"];
    [c addSubview:wc];
    [wc addSubview:[self badge:@"MJPEG" color:CPINK frame:CGRectMake(cw-76,8,62,22)]];
    [wc addSubview:[self small:@"Nhận MJPEG stream từ VCamJoy PC qua WiFi." frame:CGRectMake(14,36,cw-28,14)]];
    UILabel *ipHdr=[[UILabel alloc]initWithFrame:CGRectMake(14,56,150,12)];
    ipHdr.text=@"TARGET SERVER (IP)"; ipHdr.textColor=CPINK;
    ipHdr.font=[UIFont fontWithName:CFONT size:9]; [wc addSubview:ipHdr];
    UIView *ipBg=[[UIView alloc]initWithFrame:CGRectMake(14,72,cw-28,42)];
    ipBg.backgroundColor=HEX(0x0a0a12); ipBg.layer.cornerRadius=6;
    ipBg.layer.borderWidth=1; ipBg.layer.borderColor=CPINK.CGColor; [wc addSubview:ipBg];
    UILabel *gt=[[UILabel alloc]initWithFrame:CGRectMake(10,0,20,42)];
    gt.text=@">"; gt.textColor=CPINK; gt.font=[UIFont fontWithName:CFONTB size:16]; [ipBg addSubview:gt];
    self.ipField=[[UITextField alloc]initWithFrame:CGRectMake(30,0,ipBg.frame.size.width-38,42)];
    self.ipField.textColor=CWHITE; self.ipField.font=[UIFont fontWithName:CFONTB size:17];
    self.ipField.keyboardType=UIKeyboardTypeURL; self.ipField.keyboardAppearance=UIKeyboardAppearanceDark;
    self.ipField.autocorrectionType=UITextAutocorrectionTypeNo;
    self.ipField.autocapitalizationType=UITextAutocapitalizationTypeNone;
    self.ipField.attributedPlaceholder=[[NSAttributedString alloc]initWithString:@"192.168.1.x"
        attributes:@{NSForegroundColorAttributeName:CMUTED}];
    [ipBg addSubview:self.ipField];
    self.wifiBtn=[self outlineBtn:@"START WIFI MODE _" color:CPINK
                           frame:CGRectMake(14,124,cw-28,50) sel:@selector(onWifi)];
    [wc addSubview:self.wifiBtn];
    y+=192+8;

    // LOCAL MEDIA card
    UIView *lc=[self card:CGRectMake(16,y,cw,168) color:CCYAN title:@"LOCAL MEDIA"];
    [c addSubview:lc];
    [lc addSubview:[self badge:@"THƯ VIỆN" color:CCYAN frame:CGRectMake(cw-86,8,72,22)]];
    [lc addSubview:[self small:@"Phát ảnh/video từ thư viện làm nguồn camera ảo." frame:CGRectMake(14,36,cw-28,14)]];
    self.lblMedia=[[UILabel alloc]initWithFrame:CGRectMake(14,56,cw-28,16)];
    self.lblMedia.text=@"Chưa chọn media"; self.lblMedia.textColor=CMUTED;
    self.lblMedia.font=[UIFont fontWithName:CFONT size:11]; [lc addSubview:self.lblMedia];
    CGFloat bw=(cw-38)/2;
    self.btnPlay=[self fillBtn:@"▶  Phát" bg:CGREEN frame:CGRectMake(14,80,bw,46) sel:@selector(onPlay)];
    [lc addSubview:self.btnPlay];
    [lc addSubview:[self fillBtn:@"Đổi media" bg:CCYAN frame:CGRectMake(14+bw+10,80,bw,46) sel:@selector(onPickMedia)]];
    UILabel *hint=[[UILabel alloc]initWithFrame:CGRectMake(14,134,cw-28,14)];
    hint.text=@"👉 Chọn ảnh/video rồi bấm Phát"; hint.textColor=CAMBER;
    hint.font=[UIFont fontWithName:CFONT size:10]; [lc addSubview:hint];
    y+=168+8;

    // SETTINGS card
    UIView *setc=[self card:CGRectMake(16,y,cw,162) color:CWHITE title:@"CÀI ĐẶT"];
    [c addSubview:setc];
    UIView *r1=[self settingRow:CGRectMake(14,36,cw-28,50) lbl:@"Bật Camera Ảo" inCard:setc];
    self.vcamSw=[[UISwitch alloc]init];
    self.vcamSw.center=CGPointMake(cw-28-30,61); self.vcamSw.onTintColor=CGREEN;
    [self.vcamSw addTarget:self action:@selector(onVcam:) forControlEvents:UIControlEventValueChanged];
    [setc addSubview:self.vcamSw];
    UIView *r2=[self settingRow:CGRectMake(14,96,cw-28,50) lbl:@"ColorSync (60Hz)" inCard:setc];
    self.csSw=[[UISwitch alloc]init];
    self.csSw.center=CGPointMake(cw-28-30,121); self.csSw.onTintColor=CGREEN;
    [self.csSw addTarget:self action:@selector(onCS:) forControlEvents:UIControlEventValueChanged];
    [setc addSubview:self.csSw];
    (void)r1; (void)r2;
    y+=162+8;

    // Bottom
    CGFloat bw2=(cw-10)/2;
    [c addSubview:[self fillBtn:@"📞  Hỗ trợ" bg:CCYAN frame:CGRectMake(16,y,bw2,46) sel:@selector(onSupport)]];
    [c addSubview:[self fillBtn:@"● Thoát" bg:CRED frame:CGRectMake(16+bw2+10,y,bw2,46) sel:@selector(onQuit)]];
    y+=56;
    UILabel *ver=[[UILabel alloc]initWithFrame:CGRectMake(16,y,cw,18)];
    ver.text=@"v2.0 VCamJoy  •  iOS 15-16 JB  •  l0k1cam"; ver.textColor=CMUTED;
    ver.font=[UIFont fontWithName:CFONT size:9]; ver.textAlignment=NSTextAlignmentCenter;
    [c addSubview:ver]; y+=28;
    sv.contentSize=CGSizeMake(W,y);
}

#pragma mark - Actions
- (void)onWifi {
    [self dismissKB];
    if(self.wifiOn){[self wifiStop];return;}
    NSString *ip=[self.ipField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if(!ip.length){[self shake:self.ipField];return;}
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"http://%@:8080/stream",ip]];
    if(!url)return;
    [self savePrefs];
    [[VCamReceiver sharedReceiver] startWithURL:url];
    [self wifiStart:url];
}
- (void)wifiStart:(NSURL*)url {
    [self.task cancel];
    NSURLSessionConfiguration *cfg=[NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest=10; cfg.timeoutIntervalForResource=86400;
    cfg.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    self.ses=[NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    self.task=[self.ses dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
    [self.task resume];
    self.lblConn.text=@"CONNECTING"; self.lblConn.textColor=CAMBER;
    [self.wifiBtn setTitle:@"NGẮT KẾT NỐI _" forState:UIControlStateNormal];
    self.wifiBtn.layer.borderColor=CRED.CGColor;
    [self.wifiBtn setTitleColor:CRED forState:UIControlStateNormal];
}
- (void)wifiStop {
    [self.task cancel]; self.task=nil; self.wifiOn=NO;
    [[VCamReceiver sharedReceiver] stop];
    self.lblConn.text=@"STANDBY"; self.lblConn.textColor=CMUTED;
    self.lblStatus.text=@"CONNECTION"; self.lblStatus.textColor=CMUTED;
    [self.wifiBtn setTitle:@"START WIFI MODE _" forState:UIControlStateNormal];
    self.wifiBtn.layer.borderColor=CPINK.CGColor;
    [self.wifiBtn setTitleColor:CPINK forState:UIControlStateNormal];
}
- (void)onPickMedia {
    UIImagePickerController *pk=[[UIImagePickerController alloc]init];
    pk.sourceType=UIImagePickerControllerSourceTypePhotoLibrary;
    pk.mediaTypes=@[@"public.image",@"public.movie"];
    pk.delegate=self; [self presentViewController:pk animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController*)pk didFinishPickingMediaWithInfo:(NSDictionary*)info {
    [pk dismissViewControllerAnimated:YES completion:nil];
    NSString *type=info[UIImagePickerControllerMediaType];
    if([type isEqualToString:@"public.image"]) {
        self.localImg=info[UIImagePickerControllerOriginalImage];
        self.player=nil;
        NSURL *u=info[UIImagePickerControllerImageURL];
        self.mediaName=u.lastPathComponent?:@"Ảnh đã chọn";
    } else {
        NSURL *u=info[UIImagePickerControllerMediaURL]; if(!u)return;
        self.player=[AVPlayer playerWithURL:u]; self.localImg=nil;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerEnd:)
            name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
        self.mediaName=u.lastPathComponent;
    }
    self.lblMedia.text=self.mediaName; self.lblMedia.textColor=CCYAN;
    [self fillBtn2:self.btnPlay title:@"▶  Phát" bg:CGREEN];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)pk{[pk dismissViewControllerAnimated:YES completion:nil];}
- (void)onPlay {
    if(self.playing){[self mediaStop];return;}
    if(!self.localImg && !self.player){[self onPickMedia];return;}
    [self mediaStart];
}
- (void)mediaStart {
    self.playing=YES;
    [self fillBtn2:self.btnPlay title:@"■  Dừng phát" bg:CRED];
    self.lblMedia.text=[NSString stringWithFormat:@"▶ %@",self.mediaName];
    [[self.prevImg.superview viewWithTag:77] setHidden:YES];
    if(self.localImg){ self.prevImg.image=self.localImg; }
    else if(self.player){
        if(self.playerLayer)[self.playerLayer removeFromSuperlayer];
        self.playerLayer=[AVPlayerLayer playerLayerWithPlayer:self.player];
        self.playerLayer.frame=self.prevCont.bounds;
        self.playerLayer.videoGravity=AVLayerVideoGravityResizeAspectFill;
        [self.prevCont.layer insertSublayer:self.playerLayer atIndex:0];
        [self.player play];
    }
}
- (void)mediaStop {
    self.playing=NO;
    [self fillBtn2:self.btnPlay title:@"▶  Phát" bg:CGREEN];
    self.lblMedia.text=self.mediaName;
    [self.player pause]; self.prevImg.image=nil;
    [[self.prevImg.superview viewWithTag:77] setHidden:NO];
}
- (void)playerEnd:(NSNotification*)n{[self.player seekToTime:kCMTimeZero];[self.player play];}
- (void)onVcam:(UISwitch*)sw {
    self.vcamOn=sw.isOn;
    if(sw.isOn){
        dispatch_async(dispatch_get_global_queue(0,0),^{
            self.capSes=[AVCaptureSession new]; [self.capSes beginConfiguration];
            AVCaptureDevice *cam=[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            NSError *err; AVCaptureDeviceInput *inp=[AVCaptureDeviceInput deviceInputWithDevice:cam error:&err];
            if(inp && [self.capSes canAddInput:inp])[self.capSes addInput:inp];
            [self.capSes commitConfiguration]; [self.capSes startRunning];
            dispatch_async(dispatch_get_main_queue(),^{
                self.lblStatus.text=@"CAMERA ẢO ĐANG HOẠT ĐỘNG"; self.lblStatus.textColor=CGREEN;
            });
        });
    } else {
        [self.capSes stopRunning]; self.capSes=nil;
        self.lblStatus.text=@"CONNECTION"; self.lblStatus.textColor=CMUTED;
    }
    [self savePrefs];
}
- (void)onCS:(UISwitch*)sw {
    if(sw.isOn){
        self.csLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(csTick)];
        self.csLink.preferredFramesPerSecond=60;
        [self.csLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } else {
        [self.csLink invalidate]; self.csLink=nil;
    }
}
- (void)csTick {
    UIImage *img=self.prevImg.image; if(!img)return;
    CGImageRef cg=img.CGImage; if(!cg)return;
    CGFloat w=CGImageGetWidth(cg),h=CGImageGetHeight(cg);
    CGContextRef ctx=CGBitmapContextCreate(NULL,1,1,8,4,CGColorSpaceCreateDeviceRGB(),
        kCGBitmapByteOrderDefault|kCGImageAlphaNoneSkipLast);
    if(!ctx)return;
    CGContextDrawImage(ctx,CGRectMake(-w/2,-h/2,w,h),cg);
    uint8_t *d=(uint8_t*)CGBitmapContextGetData(ctx);
    if(d){
        NSString *ip=self.ipField.text;
        if(ip.length){
            NSURL *u=[NSURL URLWithString:[NSString stringWithFormat:@"http://%@:8080/settings",ip]];
            NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:u];
            req.HTTPMethod=@"POST"; [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            req.HTTPBody=[[NSString stringWithFormat:@"{\"rgb_r\":%d,\"rgb_g\":%d,\"rgb_b\":%d,\"rgb_sync\":true}",
                           d[0],d[1],d[2]] dataUsingEncoding:NSUTF8StringEncoding];
            [[[NSURLSession sharedSession] dataTaskWithRequest:req] resume];
        }
    }
    CGContextRelease(ctx);
}
- (void)onSupport{[[UIApplication sharedApplication]openURL:[NSURL URLWithString:@"https://github.com"] options:@{} completionHandler:nil];}
- (void)onQuit{exit(0);}

#pragma mark - NSURLSessionDataDelegate
- (void)URLSession:(NSURLSession*)s dataTask:(NSURLSessionDataTask*)t
didReceiveResponse:(NSURLResponse*)r completionHandler:(void(^)(NSURLSessionResponseDisposition))h {
    self.wifiOn=YES; [self.buf setLength:0]; self.fpsN=0; self.fpsT=CACurrentMediaTime(); h(NSURLSessionResponseAllow);
    dispatch_async(dispatch_get_main_queue(),^{
        self.lblConn.text=@"CONNECTED"; self.lblConn.textColor=CGREEN;
        self.lblStatus.text=[NSString stringWithFormat:@"WiFi → %@",self.ipField.text]; self.lblStatus.textColor=CGREEN;
        [[self.prevImg.superview viewWithTag:77] setHidden:YES];
    });
}
- (void)URLSession:(NSURLSession*)s dataTask:(NSURLSessionDataTask*)t didReceiveData:(NSData*)d {
    [self.buf appendData:d]; [self parse];
}
- (void)URLSession:(NSURLSession*)s task:(NSURLSessionTask*)t didCompleteWithError:(NSError*)e {
    self.wifiOn=NO;
    dispatch_async(dispatch_get_main_queue(),^{
        if(e && e.code!=NSURLErrorCancelled){
            self.lblConn.text=@"ERROR"; self.lblConn.textColor=CRED;
        }
    });
}
- (void)parse {
    while(YES){
        NSRange r1=[self.buf rangeOfData:kSOI options:0 range:NSMakeRange(0,self.buf.length)];
        if(r1.location==NSNotFound){[self.buf setLength:0];break;}
        NSRange sr=NSMakeRange(r1.location+2,self.buf.length-r1.location-2);
        NSRange r2=[self.buf rangeOfData:kEOI options:0 range:sr];
        if(r2.location==NSNotFound)break;
        NSUInteger end=r2.location+2;
        NSData *jpeg=[self.buf subdataWithRange:NSMakeRange(r1.location,end-r1.location)];
        [self.buf replaceBytesInRange:NSMakeRange(0,end) withBytes:NULL length:0];
        UIImage *img=[UIImage imageWithData:jpeg]; if(!img)continue;
        self.fpsN++;
        NSTimeInterval now=CACurrentMediaTime();
        if(now-self.fpsT>=1.0){
            double fps=self.fpsN/(now-self.fpsT); self.fpsN=0; self.fpsT=now;
            dispatch_async(dispatch_get_main_queue(),^{self.fpsLbl.text=[NSString stringWithFormat:@"%.0f fps",fps];});
        }
        dispatch_async(dispatch_get_main_queue(),^{self.prevImg.image=img;});
    }
}

#pragma mark - Prefs
- (void)savePrefs {
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:kSuite];
    if(self.ipField.text.length)[p setObject:[NSString stringWithFormat:@"http://%@:8080/stream",self.ipField.text] forKey:@"streamURL"];
    [p setBool:self.vcamSw.isOn forKey:@"vcamEnabled"]; [p synchronize];
}
- (void)loadPrefs {
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:kSuite];
    NSString *url=[p stringForKey:@"streamURL"];
    if(url){NSURL *u=[NSURL URLWithString:url]; self.ipField.text=u.host?:@"";}
    self.vcamSw.on=[p boolForKey:@"vcamEnabled"];
}

#pragma mark - UI Helpers
- (UIView*)card:(CGRect)f color:(UIColor*)col title:(NSString*)t {
    UIView *v=[[UIView alloc]initWithFrame:f]; v.backgroundColor=CBGCARD;
    v.layer.cornerRadius=12; v.clipsToBounds=YES;
    v.layer.borderWidth=1; v.layer.borderColor=[col colorWithAlphaComponent:0.25].CGColor;
    UILabel *hdr=[[UILabel alloc]initWithFrame:CGRectMake(14,8,f.size.width-28,20)];
    hdr.text=t; hdr.textColor=col; hdr.font=[UIFont fontWithName:CFONTB size:13]; [v addSubview:hdr];
    return v;
}
- (UILabel*)badge:(NSString*)t color:(UIColor*)c frame:(CGRect)f {
    UILabel *l=[[UILabel alloc]initWithFrame:f]; l.text=t; l.textColor=c;
    l.font=[UIFont fontWithName:CFONT size:9]; l.textAlignment=NSTextAlignmentCenter;
    l.layer.borderWidth=1; l.layer.borderColor=c.CGColor; l.layer.cornerRadius=3; l.clipsToBounds=YES;
    return l;
}
- (UILabel*)small:(NSString*)t frame:(CGRect)f {
    UILabel *l=[[UILabel alloc]initWithFrame:f]; l.text=t; l.textColor=CMUTED;
    l.font=[UIFont fontWithName:CFONT size:10]; return l;
}
- (UIButton*)outlineBtn:(NSString*)t color:(UIColor*)c frame:(CGRect)f sel:(SEL)sel {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=f;
    b.backgroundColor=[UIColor clearColor]; b.layer.borderWidth=2; b.layer.borderColor=c.CGColor;
    b.layer.cornerRadius=8; [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:c forState:UIControlStateNormal]; b.titleLabel.font=[UIFont fontWithName:CFONTB size:14];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside]; return b;
}
- (UIButton*)fillBtn:(NSString*)t bg:(UIColor*)bg frame:(CGRect)f sel:(SEL)sel {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom]; b.frame=f;
    b.backgroundColor=bg; b.layer.cornerRadius=10; b.clipsToBounds=YES;
    [b setTitle:t forState:UIControlStateNormal]; [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont fontWithName:CFONTB size:14];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside]; return b;
}
- (void)fillBtn2:(UIButton*)b title:(NSString*)t bg:(UIColor*)bg {
    b.backgroundColor=bg; [b setTitle:t forState:UIControlStateNormal];
}
- (UIView*)settingRow:(CGRect)f lbl:(NSString*)t inCard:(UIView*)card {
    UIView *row=[[UIView alloc]initWithFrame:f]; row.backgroundColor=HEX(0x0a0a10); row.layer.cornerRadius=8;
    [card addSubview:row];
    UILabel *l=[[UILabel alloc]initWithFrame:CGRectMake(14,0,f.size.width-80,f.size.height)];
    l.text=t; l.textColor=[UIColor whiteColor]; l.font=[UIFont fontWithName:CFONTB size:15]; [row addSubview:l];
    return row;
}
- (void)shake:(UIView*)v {
    CAKeyframeAnimation *a=[CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    a.duration=0.4; a.values=@[@(-8),@(8),@(-6),@(6),@(-3),@(3),@0]; [v.layer addAnimation:a forKey:@"shake"];
}
@end
