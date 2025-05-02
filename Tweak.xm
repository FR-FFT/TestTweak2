%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"TAHWD-78912-UYIAD-21876"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

%end
