//
//  SUSystemProfiler.m
//  Sparkle
//
//  Created by Andy Matuschak on 12/22/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "SUSystemProfiler.h"
#import "NSBundle+SUAdditions.h"
#import <sys/sysctl.h>

@implementation SUSystemProfiler
+ (NSDictionary *)modelTranslationTable
{
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"SUModelTranslation" ofType:@"plist"];
	return [[NSDictionary alloc] initWithContentsOfFile:path];	
}

+ (NSMutableArray *)systemProfileInformationArrayWithHostBundle:(NSBundle *)hostBundle
{
	NSDictionary *modelTranslation = [self modelTranslationTable];
	
	// Gather profile information and append it to the URL.
	NSMutableArray *profileArray = [NSMutableArray array];
	NSArray *profileDictKeys = [NSArray arrayWithObjects:@"key", @"visibleKey", @"value", @"visibleValue", nil];
	int error = 0 ;
	int value = 0 ;
	unsigned long length = sizeof(value) ;
	
	// OS version (Apple recommends using SystemVersion.plist instead of Gestalt() here, don't ask me why).
	NSString *currentSystemVersion = SUSystemVersionString();
	if (currentSystemVersion != nil)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"osVersion",@"OS Version",currentSystemVersion,currentSystemVersion,nil] forKeys:profileDictKeys]];
	
	// CPU type (decoder info for values found here is in mach/machine.h)
	error = sysctlbyname("hw.cputype", &value, &length, NULL, 0);
	int cpuType = -1;
	if (error == 0) {
		cpuType = value;
		NSString *visibleCPUType;
		switch(value) {
			case 7:		visibleCPUType=@"Intel";	break;
			case 18:	visibleCPUType=@"PowerPC";	break;
			default:	visibleCPUType=@"Unknown";	break;
		}
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"cputype",@"CPU Type", [NSNumber numberWithInt:value], visibleCPUType,nil] forKeys:profileDictKeys]];
	}
	error = sysctlbyname("hw.cpusubtype", &value, &length, NULL, 0);
	if (error == 0) {
		NSString *visibleCPUSubType;
		if (cpuType == 7) {
			// Intel
			visibleCPUSubType = @"Intel";	// If anyone knows how to tell a Core Duo from a Core Solo, please email tph@atomicbird.com
		} else if (cpuType == 18) {
			// PowerPC
			switch(value) {
				case 9:					visibleCPUSubType=@"G3";	break;
				case 10:	case 11:	visibleCPUSubType=@"G4";	break;
				case 100:				visibleCPUSubType=@"G5";	break;
				default:				visibleCPUSubType=@"Other";	break;
			}
		} else {
			visibleCPUSubType = @"Other";
		}
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"cpusubtype",@"CPU Subtype", [NSNumber numberWithInt:value], visibleCPUSubType,nil] forKeys:profileDictKeys]];
	}
	error = sysctlbyname("hw.model", NULL, &length, NULL, 0);
	if (error == 0) {
		char *cpuModel;
		cpuModel = (char *)malloc(sizeof(char) * length);
		error = sysctlbyname("hw.model", cpuModel, &length, NULL, 0);
		if (error == 0) {
			NSString *rawModelName = [NSString stringWithUTF8String:cpuModel];
			NSString *visibleModelName = [modelTranslation objectForKey:rawModelName];
			if (visibleModelName == nil)
				visibleModelName = rawModelName;
			[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"model",@"Mac Model", rawModelName, visibleModelName, nil] forKeys:profileDictKeys]];
		}
		if (cpuModel != NULL)
			free(cpuModel);
	}
	
	// Number of CPUs
	error = sysctlbyname("hw.ncpu", &value, &length, NULL, 0);
	if (error == 0)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"ncpu",@"Number of CPUs", [NSNumber numberWithInt:value], [NSNumber numberWithInt:value],nil] forKeys:profileDictKeys]];
	
	// User preferred language
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSArray *languages = [defs objectForKey:@"AppleLanguages"];
	if (languages && ([languages count] > 0))
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"lang",@"Preferred Language", [languages objectAtIndex:0], [languages objectAtIndex:0],nil] forKeys:profileDictKeys]];
	
	// Application sending the request
	NSString *appName = [hostBundle name];
	if (appName)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"appName",@"Application Name", appName, appName,nil] forKeys:profileDictKeys]];
	NSString *appVersion = [hostBundle version];
	if (appVersion)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"appVersion",@"Application Version", appVersion, appVersion,nil] forKeys:profileDictKeys]];
	
	// Number of displays?
	// CPU speed
	OSErr err;
	SInt32 gestaltInfo;
	err = Gestalt(gestaltProcClkSpeedMHz,&gestaltInfo);
	if (err == noErr)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"cpuFreqMHz",@"CPU Speed (MHz)", [NSNumber numberWithInt:gestaltInfo], [NSNumber numberWithInt:gestaltInfo],nil] forKeys:profileDictKeys]];
	
	// amount of RAM
	err = Gestalt(gestaltPhysicalRAMSizeInMegabytes,&gestaltInfo);
	if (err == noErr)
		[profileArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"ramMB",@"Memory (MB)", [NSNumber numberWithInt:gestaltInfo], [NSNumber numberWithInt:gestaltInfo],nil] forKeys:profileDictKeys]];
	
	return profileArray;
}

+ (NSURL *)profiledURLForAppcastURL:(NSURL *)appcastURL hostBundle:(NSBundle *)hostBundle
{
	NSMutableArray *profileInfo = [NSMutableArray array];
	NSEnumerator *profileInfoEnumerator = [[self systemProfileInformationArrayWithHostBundle:hostBundle] objectEnumerator];
	NSDictionary *currentProfileInfo;
	while ((currentProfileInfo = [profileInfoEnumerator nextObject])) {
		[profileInfo addObject:[NSString stringWithFormat:@"%@=%@", [currentProfileInfo objectForKey:@"key"], [currentProfileInfo objectForKey:@"value"]]];
	}
	
	NSString *appcastStringWithProfile = [NSString stringWithFormat:@"%@?%@", [appcastURL absoluteString], [profileInfo componentsJoinedByString:@"&"]];
	
	// Clean it up so it's a valid URL
	return [NSURL URLWithString:[appcastStringWithProfile stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
}
@end