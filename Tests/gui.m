/*
 * This file is part of Terminal.app.
 * Copyright (C) 2026 Terminal contributors.
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License, version 3 or later.
 * This program is distributed WITHOUT ANY WARRANTY; without even the implied
 * warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See <https://www.gnu.org/licenses/> for a copy of the license.
 */

#import <AppKit/AppKit.h>
#import "TerminalView.h"
#include <string.h>
#include <math.h>
#include <unistd.h>

@interface TestView : TerminalView

-(void) exercise;

@end

@implementation TestView

- (BOOL)containsText:(NSString *)needle
{
  NSMutableString *text=[NSMutableString string];
  int i;
  for (i=0; i<sx*sy; i++)
    {
      unichar ch=screen[i].ch ? screen[i].ch : ' ';
      [text appendString:[NSString stringWithCharacters:&ch length:1]];
    }
  return [text rangeOfString:needle].location!=NSNotFound;
}

- (BOOL)waitForText:(NSString *)needle
{
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:8];
  while (![self containsText:needle] && [deadline timeIntervalSinceNow]>0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
  return [self containsText:needle];
}

- (void)waitForExit
{
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
  while (master_fd!=-1 && [deadline timeIntervalSinceNow]>0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
  NSCAssert(master_fd==-1,@"interactive child exits");
}

- (void)exerciseApplications
{
  NSString *file=[NSString stringWithFormat:@"/tmp/terminal-native-vim-%d.txt",getpid()];
  NSString *command=[NSString stringWithFormat:
    @"printf '\\033cVIM_PRIMARY'; /usr/bin/vim -Nu NONE -i NONE -n %@; printf '\\r\\nVIM_DONE'",file];
  [[self window] setContentSize:NSMakeSize(fx*100+border_x,fy*35+border_y)];
  [self runProgram:@"/bin/sh" withArguments:[NSArray arrayWithObjects:@"-c",command,nil] initialInput:nil];
  NSCAssert([self waitForText:[file lastPathComponent]],@"Vim draws its filename");
  [self ts_sendCString:"inative terminal edit\033:wq\r"];
  NSCAssert([self waitForText:@"VIM_DONE"],@"Vim returns to primary screen");
  [self waitForExit];
  NSString *saved=[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL];
  NSCAssert([saved isEqualToString:@"native terminal edit\n"] && [self containsText:@"VIM_PRIMARY"],
            @"Vim edit, save, and primary screen restoration");
  [self runProgram:@"/bin/sh" withArguments:[NSArray arrayWithObjects:@"-c",
    @"printf '\\033cLESS_PRIMARY'; seq 1 200 | /usr/bin/less; printf '\\r\\nLESS_DONE'",nil] initialInput:nil];
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
  while ((screen[0].ch!='1' || screen[sx].ch!='2') && [deadline timeIntervalSinceNow]>0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
  NSCAssert(screen[0].ch=='1' && screen[sx].ch=='2',@"less displays its input");
  [self ts_sendCString:"G"];
  NSCAssert([self waitForText:@"200"],@"less scrolls to the end");
  [self ts_sendCString:"q"];
  NSCAssert([self waitForText:@"LESS_DONE"],@"less exits");
  [self waitForExit];
  NSCAssert([self containsText:@"LESS_PRIMARY"],@"less restores the primary screen");
  [self runProgram:@"/bin/sh" withArguments:[NSArray arrayWithObjects:@"-c",
    @"printf '\\033cTOP_PRIMARY'; /usr/bin/top -d 0.2; printf '\\r\\nTOP_DONE'",nil] initialInput:nil];
  NSCAssert([self waitForText:@"PID"] && [self waitForText:@"load average"],@"top displays its process list");
  [[self window] setContentSize:NSMakeSize(fx*90+border_x,fy*30+border_y)];
  NSCAssert([self waitForText:@"PID"],@"top survives terminal resize");
  [self ts_sendCString:"q"];
  NSCAssert([self waitForText:@"TOP_DONE"],@"top exits");
  [self waitForExit];
  printf("PASS: real Vim editing, less paging, and top with resize\n");
}


-(void) exercise
{
  int i;
  const char *text="\033c1\r\n2\r\n3\r\n4";
  [self setFrameSize:NSMakeSize(fx*10+border_x,fy*3+border_y)];
  [tp processBytes:text length:strlen(text)];
  NSCAssert(sb_length==1 && screen[0].ch=='2',@"view scrollback push");
  [self setFrameSize:NSMakeSize(fx*10+border_x,fy*4+border_y)];
  NSCAssert(sb_length==0 && screen[0].ch=='1',@"view restores history");
  [self setFrameSize:NSMakeSize(fx*10+border_x,fy*2+border_y)];
  NSCAssert(sb_length==2 && screen[0].ch=='3',@"view saves resized rows once");
  text="\033[?1049hALT\033[?1049l";
  [tp processBytes:text length:strlen(text)];
  NSCAssert(sb_length==2 && screen[0].ch=='3',@"view alternate screen");
  for (i=0;i<100;i++)
    {
      [self setFrameSize:NSMakeSize(fx*(10+i%5)+border_x,fy*(2+i%4)+border_y)];
      [tp processBytes:"\r\nline" length:6];
    }
  [self setNeedsDisplay:YES];
  [[self window] display];
  printf("PASS: actual TerminalView scrollback, alternate screen, 100 resizes and drawing\n");
  [self setFrameSize:NSMakeSize(fx*40+border_x,fy*10+border_y)];
  {
    NSBitmapImageRep *bitmap;
    NSRect bounds=[self bounds];
    const char *colors="\033c\033[?25l\033[48;2;12;34;56m  \033[48;5;196m  ";
    int dot, row, column;
    [tp processBytes:colors length:strlen(colors)];
    for (dot=0; dot<8; dot++)
      {
        unichar ch=0x2800+(1<<dot);
        NSString *pattern=[NSString stringWithFormat:@"\033[2;%dH\033[0;38;2;255;255;255;48;2;0;0;0m%@",
          dot+1,[NSString stringWithCharacters:&ch length:1]];
        NSData *data=[pattern dataUsingEncoding:NSUTF8StringEncoding];
        [tp processBytes:[data bytes] length:[data length]];
      }
    draw_all=YES;
    [self setNeedsDisplay:YES];
    [[self window] display];
    bitmap=[self bitmapImageRepForCachingDisplayInRect:bounds];
    [self cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
    {
      NSColor *rgb=[[bitmap colorAtX:border_x+fx/2 y:bounds.size.height-(border_y+(sy-.5)*fy)]
        colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
      NSCAssert(fabs([rgb redComponent]*255-12)<2 &&
                fabs([rgb greenComponent]*255-34)<2 &&
                fabs([rgb blueComponent]*255-56)<2,@"truecolor background pixels");
      rgb=[[bitmap colorAtX:border_x+2.5*fx y:bounds.size.height-(border_y+(sy-.5)*fy)]
        colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
      NSCAssert([rgb redComponent]>.99 && [rgb greenComponent]<.01,
                @"256-color background pixels");
    }
    for (dot=0; dot<8; dot++)
      for (row=0; row<4; row++)
        for (column=0; column<2; column++)
          {
            static const int bits[4][2]={{0,3},{1,4},{2,5},{6,7}};
            int x,y,lit=0;
            for (y=0; y<[bitmap pixelsHigh]; y++)
              for (x=border_x+dot*fx+column*fx/2;
                   x<border_x+dot*fx+(column+1)*fx/2; x++)
                {
                  CGFloat viewY=bounds.size.height-y-.5;
                  CGFloat low=border_y+(sy-2)*fy+(3-row)*fy/4;
                  if (viewY<low || viewY>=low+fy/4) continue;
                  NSColor *rgb=[[bitmap colorAtX:x y:y]
                    colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                  if ([rgb redComponent]>.15) lit++;
                }
            NSCAssert((lit>0)==(bits[row][column]==dot),@"braille dot orientation");
          }
    [[bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
      writeToFile:@"/tmp/terminal-bpytop-render.png" atomically:YES];
    printf("PASS: truecolor, indexed colors and all eight braille dot positions rendered\n");
  }
  [self runProgram:@"/bin/sh" withArguments:
    [NSArray arrayWithObjects:@"-c",@"printf '\\033c'; printf '%s PTY_OK' \"$TERM\"",nil]
    initialInput:nil];
  {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while (master_fd!=-1 && [deadline timeIntervalSinceNow]>0)
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    NSCAssert(master_fd==-1,@"PTY child exits");
    NSCAssert(screen[0].ch=='x' && screen[4].ch=='m' && screen[6].ch=='P',
              @"PTY output reaches the native parser and TERM is xterm");
  }
  printf("PASS: real PTY output, TERM and child exit\n");
  [self exerciseApplications];

  /* Optional live application smoke test, with an isolated bpytop config. */
  NSString *smoke=[[[NSProcessInfo processInfo] environment] objectForKey:@"TERMINAL_BPYTOP_SMOKE"];
  if (smoke)
    {
      NSDate *deadline;
      int dots=0;
      [[self window] setContentSize:NSMakeSize(fx*100+border_x,fy*35+border_y)];
      [self runProgram:smoke withArguments:[NSArray array] initialInput:nil];
      deadline=[NSDate dateWithTimeIntervalSinceNow:5];
      while ([deadline timeIntervalSinceNow]>0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
      for (i=0;i<sx*sy;i++)
        if (screen[i].ch>0x2800 && screen[i].ch<=0x28ff) dots++;
      draw_all=YES;
      [self setNeedsDisplay:YES];
      [[self window] display];
      NSBitmapImageRep *bitmap=[self bitmapImageRepForCachingDisplayInRect:[self bounds]];
      [self cacheDisplayInRect:[self bounds] toBitmapImageRep:bitmap];
      [[bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
        writeToFile:@"/tmp/terminal-bpytop-live.png" atomically:YES];
      [self ts_sendCString:"q" length:1];
      deadline=[NSDate dateWithTimeIntervalSinceNow:5];
      while (master_fd!=-1 && [deadline timeIntervalSinceNow]>0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
      NSCAssert(dots>0 && master_fd==-1,@"live bpytop draws graphs and exits on q");
      printf("PASS: live bpytop graph rendering and clean exit\n");
    }


}

@end

int main(void)
{
  CREATE_AUTORELEASE_POOL(pool);
  [NSApplication sharedApplication];
  NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,400)
    styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
  TestView *view=[[TestView alloc] initWithFrame:NSMakeRect(0,0,600,400)];
  [window setContentView:view];
  [window orderFront:nil];
  [view exercise];
  [window orderOut:nil];
  RELEASE(view); RELEASE(window); RELEASE(pool);
  return 0;
}

