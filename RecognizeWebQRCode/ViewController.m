//
//  ViewController.m
//  RecognizeWebQRCode
//
//  Created by darkwing90s on 17/2/25.
//  Copyright © 2017年 http://www.devpeng.com All rights reserved.
//

#import "ViewController.h"
#import "LCActionSheet.h"

static NSString* const kTouchJavaScriptString=
@"document.ontouchstart=function(event){\
x=event.targetTouches[0].clientX;\
y=event.targetTouches[0].clientY;\
document.location=\"myweb:touch:start:\"+x+\":\"+y;};\
document.ontouchmove=function(event){\
x=event.targetTouches[0].clientX;\
y=event.targetTouches[0].clientY;\
document.location=\"myweb:touch:move:\"+x+\":\"+y;};\
document.ontouchcancel=function(event){\
document.location=\"myweb:touch:cancel\";};\
document.ontouchend=function(event){\
document.location=\"myweb:touch:end\";};";

// 用于UIWebView保存图片
enum
{
    GESTURE_STATE_NONE = 0,
    GESTURE_STATE_START = 1,
    GESTURE_STATE_MOVE = 2,
    GESTURE_STATE_END = 4,
    GESTURE_STATE_ACTION = (GESTURE_STATE_START | GESTURE_STATE_END),
};

@interface ViewController ()<UIActionSheetDelegate,UIWebViewDelegate>
{
    NSTimer *_timer;	// 用于UIWebView保存图片
    int _gesState;	  // 用于UIWebView保存图片
    NSString *_imgURL;  // 用于UIWebView保存图片
    UIWebView *mainWebView;
    
    LCActionSheet *longPressSheet;
}


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    mainWebView = [[UIWebView alloc]initWithFrame:CGRectMake(0,60, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height-60)];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://www.devpeng.com/?id=12"]];
    mainWebView.delegate = self;
    [self.view addSubview:mainWebView];
    
    [mainWebView loadRequest:request];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark -- JS注入
// 网页加载完成时触发
#pragma mark UIWebDelegate implementation
- (void)webViewDidFinishLoad:(UIWebView*)theWebView
{
    // Black base color for background matches the native apps
    theWebView.backgroundColor = [UIColor blackColor];
    
    // 防止内存泄漏
    [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"WebKitCacheModelPreferenceKey"];
    
    // 响应touch事件，以及获得点击的坐标位置，用于保存图片
    [theWebView stringByEvaluatingJavaScriptFromString:kTouchJavaScriptString];
    
}

// 功能：UIWebView响应长按事件
-(BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)_request navigationType:(UIWebViewNavigationType)navigationType {
    NSString *requestString = [[_request URL] absoluteString];
    NSArray *components = [requestString componentsSeparatedByString:@":"];
    if ([components count] > 1 && [(NSString *)[components objectAtIndex:0]
                                   isEqualToString:@"myweb"]) {
        if([(NSString *)[components objectAtIndex:1] isEqualToString:@"touch"])
        {
            //NSLog(@"you are touching!");
            //NSTimeInterval delaytime = Delaytime;
            if ([(NSString *)[components objectAtIndex:2] isEqualToString:@"start"])
            {
                /*
                 @需延时判断是否响应页面内的js...
                 */
                _gesState = GESTURE_STATE_START;
                NSLog(@"touch start!");
                
                float ptX = [[components objectAtIndex:3]floatValue];
                float ptY = [[components objectAtIndex:4]floatValue];
                NSLog(@"touch point (%f, %f)", ptX, ptY);
                
                NSString *js = [NSString stringWithFormat:@"document.elementFromPoint(%f, %f).tagName", ptX, ptY];
                NSString * tagName = [mainWebView stringByEvaluatingJavaScriptFromString:js];
                _imgURL = nil;
                if ([tagName isEqualToString:@"IMG"]) {
                    _imgURL = [NSString stringWithFormat:@"document.elementFromPoint(%f, %f).src", ptX, ptY];
                }
                if (_imgURL) {
                    
                    NSString *pt = NSStringFromCGPoint(CGPointMake(ptX+mainWebView.frame.origin.x, ptY+mainWebView.frame.origin.y));
                    _timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(handleLongTouchWithPt:) userInfo:pt repeats:NO];
                }
            }
            else if ([(NSString *)[components objectAtIndex:2] isEqualToString:@"move"])
            {
                //**如果touch动作是滑动，则取消hanleLongTouch动作**//
                _gesState = GESTURE_STATE_MOVE;
                NSLog(@"you are move");
            }
        }
        else if ([(NSString*)[components objectAtIndex:2]isEqualToString:@"end"]) {
            [_timer invalidate];
            _timer = nil;
            _gesState = GESTURE_STATE_END;
            NSLog(@"touch end");
        }
        return NO;
    }
    return YES;
}


// 功能：如果点击的是图片，并且按住的时间超过1s，执行handleLongTouch函数，处理图片的保存操作。
- (void)handleLongTouchWithPt:(NSTimer*)timer {
    NSLog(@"%@", _imgURL);
    NSLog(@"userInfo:%@",timer.userInfo);
    if (_imgURL && _gesState == GESTURE_STATE_START) {
        
        NSString *touchPoint = (NSString *)timer.userInfo;
        NSLog(@"touchPoint:%@",touchPoint);
        
        __block UIImage *webImage = [self snapshotScreenInView:self.view.window];
        __block NSString *urlToSave = [mainWebView stringByEvaluatingJavaScriptFromString:_imgURL];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            NSData * data = [[NSData alloc]initWithContentsOfURL:[NSURL URLWithString:urlToSave]];
            BOOL isQRCode = ![self convertNull:[self stringFromFileImage:webImage withPt:touchPoint]];
            
            if (data != nil) {
                
                __weak __typeof__(self) weakSelf = self;
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    __strong __typeof__(weakSelf) strongSelf = weakSelf;
                    NSMutableArray *items = [NSMutableArray arrayWithObjects:@"转发",@"保存图片", nil];
                    
                    if (isQRCode) {
                        
                        [items addObject:@"识别图中二维码"];
                    }
                    
                    if (longPressSheet.isHidden || !longPressSheet) {

                        longPressSheet = [LCActionSheet sheetWithTitle:nil buttonTitles:items specialButtonIndex:-1 delegate:nil];
                        longPressSheet.clickedBlock = ^(NSInteger buttonIndex)
                        {
                            if (buttonIndex == 0) {
                                
                                NSLog(@"转发");
                                
                            } else if (buttonIndex == 1){
                                
                                if (webImage) {
                                    UIImageWriteToSavedPhotosAlbum(webImage, nil, nil, nil);
                                }
                                
                                NSLog(@"保存图片");
                                
                            } else if (buttonIndex == items.count){
                                
                                NSLog(@"取消");
                                
                            } else{         //识别二维码
                                
                                NSLog(@"webImageString:%@",[strongSelf stringFromFileImage:webImage withPt:touchPoint]);
                            }
                        };
                        [longPressSheet show];
                    
                    }
                    
                });
            }
        });
        
    }
}


#pragma mark -- 识别二维码
/**
 * 将二维码图片转化为字符
 */
- (NSString *)stringFromFileImage:(UIImage *)qrCodeImg withPt:(NSString *)pt{
    
    NSLog(@"touchPoint:%@",pt);
    CGPoint point = CGPointFromString(pt);
    NSDictionary *detectorOptions = @{ CIDetectorAccuracy : CIDetectorAccuracyLow }; // TODO: read doc for more tuneups
    CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:detectorOptions];
    
    NSArray *features = [detector featuresInImage:[CIImage imageWithCGImage:qrCodeImg.CGImage]];
    
    //NSArray *features = [detector featuresInImage:qrCodeImg.CIImage];
    
    for (CIQRCodeFeature *qrStr in features) {
        
        if (CGRectContainsPoint([self convertRectFromQRCode:qrStr.bounds], point)) {
            return qrStr.messageString;
        }
        
    }
    
    return @"";

}

- (CGRect)convertRectFromQRCode:(CGRect)QRRect
{
    CGFloat scale = [UIScreen mainScreen].scale;
    CGRect rect = CGRectMake(QRRect.origin.x/scale, QRRect.origin.y/scale, QRRect.size.width/scale, QRRect.size.width/scale);
    CGFloat originX = rect.origin.x;
    CGFloat originY = [UIScreen mainScreen].bounds.size.height-(rect.origin.y+rect.size.height);

    CGRect convertRect = CGRectMake(originX, originY, rect.size.width, rect.size.height);
    
    NSLog(@"featuresRect:%@",NSStringFromCGRect(rect));
    NSLog(@"convertRect:%@",NSStringFromCGRect(convertRect));
    
    return convertRect;
}

#pragma mark -- 截取某视图的内容
/**
 *  截取某视图的内容
 */
- (UIImage *)snapshotScreenInView:(UIView *)view
{
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]){
        UIGraphicsBeginImageContextWithOptions(view.bounds.size, NO, [UIScreen mainScreen].scale);
    } else {
        UIGraphicsBeginImageContext(view.bounds.size);
    }
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

#pragma mark -- 判空
-(BOOL)convertNull:(id)obj
{
    if ([obj isEqual:[NSNull null]]) {
        return YES;
    }
    else if([obj isKindOfClass:[NSNull class]])
    {
        return YES;
    }
    else if(obj==nil)
    {
        return YES;
    }
    else if ([obj isEqualToString:@"(null)"])
    {
        return YES;
    }
    else if ([obj isEqualToString:@""])
    {
        return YES;
    }
    return NO;
}

@end
