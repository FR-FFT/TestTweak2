#import <Foundation/Foundation.h>


__attribute__((constructor))
static void init() {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"TAHWD-78912-UYIAD-21876"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


