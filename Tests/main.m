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
#import "TerminalParser_VT100.h"

@interface TerminalViewKeyboardPrefs : NSObject

+(BOOL) commandAsMeta;
+(BOOL) altIsNotMeta;
+(BOOL) doubleEscape;

@end
#include <string.h>

/* Keyboard preferences are fixed here so tests do not change user defaults. */
@implementation TerminalViewKeyboardPrefs

+(BOOL) commandAsMeta { return NO; }

+(BOOL) altIsNotMeta { return NO; }

+(BOOL) doubleEscape { return NO; }

@end

@interface TestScreen : NSObject <TerminalScreen>
{
@public
  screen_char_t cells[40][100];
  NSMutableData *output;
  NSMutableArray *history;
  NSString *title;
  int x,y;
  BOOL visible;
}

@end

@implementation TestScreen

-(id) init
{
  if ((self=[super init]))
    {
      output=[[NSMutableData alloc] init];
      history=[[NSMutableArray alloc] init];
    }
  return self;
}

-(void) dealloc
{
  DESTROY(output); DESTROY(history); DESTROY(title);
  DEALLOC;
}

-(void) ts_sendCString: (const char *)s
{
  [self ts_sendCString:s length:strlen(s)];
}

-(void) ts_sendCString: (const char *)s length: (int)n
{
  [output appendBytes:s length:n];
}

-(void) ts_goto: (int)xx : (int)yy
{
  x=xx; y=yy;
}

-(void) ts_putChar: (screen_char_t)c count: (int)n at: (int)xx : (int)yy
{
  while (n--) cells[yy][xx++]=c;
}

-(void) ts_putChar: (screen_char_t)c count: (int)n offset: (int)o
{
  [self doesNotRecognizeSelector:_cmd];
}

-(void) ts_scrollUp: (int)t : (int)b rows: (int)n save: (BOOL)s
{
  [self doesNotRecognizeSelector:_cmd];
}

-(void) ts_scrollDown: (int)t : (int)b rows: (int)n
{
  [self doesNotRecognizeSelector:_cmd];
}

-(void) ts_shiftRow: (int)y at: (int)x delta: (int)d
{
  [self doesNotRecognizeSelector:_cmd];
}

-(screen_char_t) ts_getCharAt: (int)xx : (int)yy
{
  return cells[yy][xx];
}

-(void) ts_setTitle: (NSString *)text type: (int)type
{
  ASSIGN(title,text);
}

-(void) ts_setCursorVisible: (BOOL)v
{
  visible=v;
}

-(void) ts_clearScrollback
{
  [history removeAllObjects];
}

-(void) ts_appendScrollback: (const screen_char_t *)line count: (int)n
{
  [history addObject:[NSData dataWithBytes:line length:n*sizeof(*line)]];
}

-(BOOL) ts_popScrollback: (screen_char_t *)line count: (int)n
{
  NSData *data=[history lastObject];
  if (!data) return NO;
  memset(line,0,n*sizeof(*line));
  memcpy(line,[data bytes],MIN([data length],n*sizeof(*line)));
  [history removeLastObject];
  return YES;
}

-(BOOL) useMultiCellGlyphs { return YES; }

-(int) relativeWidthOfCharacter: (unichar)c { return 1; }

@end

static int failures;
static void check(BOOL ok, const char *name)
{
  printf("%s: %s\n",ok ? "PASS" : "FAIL",name);
  if (!ok) failures++;
}

static void feed(TerminalParser_VT100 *p, const char *s)
{
  [p processBytes:s length:strlen(s)];
}

static BOOL sent(TestScreen *s, const char *text)
{
  return [s->output length]==strlen(text) &&
    !memcmp([s->output bytes],text,strlen(text));
}

static void key(TerminalParser_VT100 *p, unichar c, NSUInteger flags)
{
  NSString *s=[NSString stringWithCharacters:&c length:1];
  NSEvent *event=[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint
    modifierFlags:flags timestamp:0 windowNumber:0 context:nil
    characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:0];
  [p handleKeyEvent:event];
}

int main(void)
{
  CREATE_AUTORELEASE_POOL(pool);
  TestScreen *s=[[TestScreen alloc] init];
  TerminalParser_VT100 *p=[[TerminalParser_VT100 alloc]
    initWithTerminalScreen:s width:10 height:3];
  feed(p,"abc\033[2;3HZ");
  check(s->cells[0][0].ch=='a' && s->cells[1][2].ch=='Z',"text and cursor addressing");
  feed(p,"\033[31;1mR\033[0m");
  check((s->cells[1][3].color&15)==4 && (s->cells[1][3].attr&3)==2,"SGR color and bold");
  feed(p,"\033[?1049hALT\033[?1049l");
  check(s->cells[0][0].ch=='a' && s->cells[1][2].ch=='Z',"alternate screen restores primary");
  feed(p,"\033[?25l"); check(!s->visible,"hide cursor");
  feed(p,"\033[?25h"); check(s->visible,"show cursor");
  feed(p,"\033]2;split "); feed(p,"title\033\\");
  check([s->title isEqualToString:@"split title"],"fragmented OSC title");
  feed(p,"\033[H\xc3"); feed(p,"\xa9");
  check(s->cells[0][0].ch==0xe9,"fragmented UTF-8");
  feed(p,"\033[H\xe7\x95\x8c");
  check(s->cells[0][0].ch==0x754c && s->cells[0][1].ch==MULTI_CELL_GLYPH,"wide character continuation");
  [s->output setLength:0]; feed(p,"\033[2;3H\033[6n");
  check(sent(s,"\033[2;3R"),"cursor position reply");
  [s->output setLength:0]; key(p,NSUpArrowFunctionKey,0);
  check(sent(s,"\033[A"),"normal cursor key");
  [s->output setLength:0]; feed(p,"\033[?1h"); key(p,NSUpArrowFunctionKey,0);
  check(sent(s,"\033OA"),"application cursor key");
  [s->output setLength:0]; key(p,'c',NSControlKeyMask);
  check(sent(s,"\003"),"control key");
  [s->output setLength:0]; key(p,'x',NSAlternateKeyMask);
  check(sent(s,"\033x"),"meta key");
  [s->output setLength:0]; feed(p,"\033[?2004h"); [p sendString:@"a\nb"];
  check(sent(s,"\033[200~a\rb\033[201~"),"bracketed paste");
  feed(p,"\033c1\r\n2\r\n3\r\n4");
  check([s->history count]==1 && s->cells[0][0].ch=='2',"scrolling saves history");
  feed(p,"\033[?1049hA\r\nB\r\nC\r\nD\033[?1049l");
  check([s->history count]==1,"alternate scrolling does not pollute history");
  [p setTerminalScreenWidth:10 height:4];
  check([s->history count]==0 && s->cells[0][0].ch=='1' && s->cells[3][0].ch=='4',"growing restores history");
  [p setTerminalScreenWidth:10 height:2];
  check([s->history count]==2 && s->cells[0][0].ch=='3',"shrinking saves displaced lines once");
  feed(p,"\033[3J"); check([s->history count]==0,"erase scrollback");
  feed(p,"\033c\033[38;2;12;34;56me\xcc\x81\r\n2\r\n3");
  [p setTerminalScreenWidth:10 height:3];
  check(s->cells[0][0].originalCell.chars[1]==0x301 &&
        s->cells[0][0].originalCell.fg.rgb.red==12,
        "history retains combining characters and true color");

  feed(p,"\033c\033[2;4H\033[s\033[H\033[uX");
  check(s->cells[1][3].ch=='X',"CSI s/u restores bpytop cursor position");
  feed(p,"\033[2;5H\033[s");
  feed(p,"\033[H\033["); feed(p,"uY");
  check(s->cells[1][4].ch=='Y',"fragmented cursor restore");
  feed(p,"\033c\033[?69h\033[3;8s\033[?6hZ");
  check(s->cells[0][2].ch=='Z',"CSI s still sets enabled left/right margins");
  feed(p,"\033c\033[38;2;12;34;56mT\033[48;5;196m ");
  check(s->cells[0][0].foreground.rgb.red==12 &&
        s->cells[0][0].foreground.rgb.green==34 &&
        s->cells[0][0].foreground.rgb.blue==56 &&
        s->cells[0][1].background.rgb.red==255 &&
        s->cells[0][1].background.rgb.green==0,
        "display retains exact truecolor and resolves indexed colors");

  feed(p,"\033c\033[3J\033[H0123456789X");
  check(s->cells[0][9].ch=='9' && s->cells[1][0].ch=='X',"deferred autowrap");
  feed(p,"\033c\033[?7l0123456789XY");
  check(s->cells[0][9].ch=='Y' && s->cells[1][0].ch==' ',"disabled autowrap overwrites edge");
  feed(p,"\033c\033[Habcde\033[1;3H\033[2@XY");
  check(s->cells[0][2].ch=='X' && s->cells[0][4].ch=='c',"insert characters");
  feed(p,"\033[1;3H\033[2P");
  check(s->cells[0][2].ch=='c' && s->cells[0][4].ch=='e',"delete characters");
  feed(p,"\033[1;2H\033[2X");
  check(s->cells[0][0].ch=='a' && s->cells[0][1].ch==' ' && s->cells[0][3].ch=='d',"erase characters");
  feed(p,"\033cabc\033[1;2H\033[4hX\033[4l");
  check(s->cells[0][1].ch=='X' && s->cells[0][2].ch=='b',"insert mode");
  [p setTerminalScreenWidth:10 height:4];
  feed(p,"\033c\033[3J1\033[2;1H2\033[3;1H3\033[4;1H4\033[2;3r\033[3;1H\n");
  check(s->cells[0][0].ch=='1' && s->cells[1][0].ch=='3'
        && s->cells[2][0].ch==' ' && s->cells[3][0].ch=='4'
        && [s->history count]==0,"scroll region leaves outer lines and history alone");
  feed(p,"\033[2;1H\033M");
  check(s->cells[1][0].ch==' ' && s->cells[2][0].ch=='3',"reverse index within margins");
  feed(p,"\033[?6h\033[1;2HZ");
  check(s->cells[1][1].ch=='Z',"origin-relative cursor addressing");
  [s->output setLength:0]; feed(p,"\033[6n");
  check(sent(s,"\033[1;3R"),"origin-relative cursor report");
  feed(p,"\033c\033[3g\033[1;4H\033H\r\tT");
  check(s->cells[0][3].ch=='T',"programmable tab stops");
  feed(p,"\033c\033(0lqk\033(B");
  check(s->cells[0][0].ch==0x250c && s->cells[0][1].ch==0x2500
        && s->cells[0][2].ch==0x2510,"DEC graphics character set");
  feed(p,"\033c\033)0\016x\017x");
  check(s->cells[0][0].ch==0x2502 && s->cells[0][1].ch=='x',"G1 shift out and shift in");
  feed(p,"\033c\033[38:2::12:34:56mC\033[48:5:236m ");
  check(s->cells[0][0].foreground.rgb.red==12 && s->cells[0][0].foreground.rgb.blue==56
        && s->cells[0][1].background.rgb.red==48,"colon RGB and standard indexed grayscale");
  feed(p,"\033[0m\033[38;5;67mI");
  check(s->cells[0][2].foreground.rgb.red==95 && s->cells[0][2].foreground.rgb.green==135
        && s->cells[0][2].foreground.rgb.blue==175,"xterm 256-color cube levels");
  feed(p,"\033c\033[31;44;1mA\0337\033[0m\033[4;4H\0338B");
  check(s->cells[0][1].ch=='B' && (s->cells[0][1].attr&3)==2
        && s->cells[0][1].originalCell.fg.index==1,"DEC cursor restore includes pen");
  feed(p,"\033c\033[1;2;3;4;5;7;8;9mX\033[22;23;24;25;27;28;29mY");
  check(s->cells[0][0].ch==' ' && s->cells[0][1].ch=='Y'
        && s->cells[0][1].originalCell.attributes==0,"SGR attribute clearing and conceal");
  feed(p,"\033c\033[1\"qP\033[0\"qN\033[?2J");
  check(s->cells[0][0].ch=='P' && s->cells[0][1].ch==' ',"selective erase protects marked text");
  feed(p,"\033c\033[31mR\033]4;1;rgb:12/34/56\033\\");
  check(s->cells[0][0].foreground.rgb.red==0x12
        && s->cells[0][0].foreground.rgb.blue==0x56,"OSC palette changes repaint existing cells");
  [s->output setLength:0]; feed(p,"\033]4;1;?\a");
  check(sent(s,"\033]4;1;rgb:1212/3434/5656\033\\"),"palette query reply");
  [s->output setLength:0]; feed(p,"\033[?2004h\033[?2004$p");
  check(sent(s,"\033[?2004;1$y"),"private mode query");
  [s->output setLength:0]; feed(p,"\033[?9999$p");
  check(sent(s,"\033[?9999;0$y"),"unknown mode is reported unsupported");
  [s->output setLength:0]; feed(p,"\033c\033[c");
  check(sent(s,"\033[?1;2c"),"primary device attributes");
  [s->output setLength:0]; feed(p,"\033[18t");
  check(sent(s,"\033[8;4;10t"),"character size query");
  feed(p,"\033cA\033Pignored text\033\\B\033_ignored\033\\C");
  check(s->cells[0][0].ch=='A' && s->cells[0][1].ch=='B' && s->cells[0][2].ch=='C',
        "unsupported control strings do not leak into the screen");
  feed(p,"\033c\033[99999999999999999999;2HOK");
  check(s->cells[0][0].ch=='O' && s->cells[0][1].ch=='K',"overflowing CSI is discarded");
  feed(p,"\033c\033[1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;22;23;24;25;26;27;28;29;30;31;32;33HOK");
  check(s->cells[0][0].ch=='O',"excess CSI parameters are bounded and discarded");
  feed(p,"\033c\033[12\030Q");
  check(s->cells[0][0].ch=='Q',"CAN cancels a fragmented sequence");
  feed(p,"\033c\xe2X");
  check(s->cells[0][0].ch==0xfffd && s->cells[0][1].ch=='X',"invalid UTF-8 recovers at next character");
  feed(p,"\033c\xed\xa0\x80");
  check(s->cells[0][0].ch==0xfffd,"UTF-8 surrogate is replaced");
  feed(p,"\033c\xf0\x9f"); feed(p,"\x98\x80");
  check(s->cells[0][0].originalCell.chars[0]==0x1f600
        && s->cells[0][1].ch==MULTI_CELL_GLYPH,"supplementary UTF-8 retains full code point");
  feed(p,"\033c\xe7\x95\x8c\033[1;2HX");
  check(s->cells[0][0].ch==' ' && s->cells[0][1].ch=='X',"overwriting half a wide glyph removes the other half");
  feed(p,"\033c\033[1;10H\xe7\x95\x8c");
  check(s->cells[1][0].ch==0x754c && s->cells[1][1].ch==MULTI_CELL_GLYPH,"wide character wraps before the edge");
  feed(p,"\033c\033[3J\033[2;4HP\033[?1049hALT");
  [p setTerminalScreenWidth:12 height:5];
  feed(p,"\033[?1049l");
  check(s->cells[1][3].ch=='P' && [s->history count]==0,"alternate-screen resize preserves primary content");
  feed(p,"\033c\033[?47hA\033[?47lP\033[?47h");
  check(s->cells[0][0].ch=='A',"mode 47 retains alternate screen");
  feed(p,"\033[?47l");
  [s->output setLength:0]; key(p,NSF5FunctionKey,0);
  check(sent(s,"\033[15~"),"F5 key encoding");
  [s->output setLength:0]; key(p,NSUpArrowFunctionKey,NSControlKeyMask|NSShiftKeyMask);
  check(sent(s,"\033[1;6A"),"modified arrow key encoding");
  [s->output setLength:0]; key(p,'\t',NSShiftKeyMask);
  check(sent(s,"\033[Z"),"backtab encoding");
  [s->output setLength:0]; key(p,' ',NSControlKeyMask);
  check([s->output length]==1 && ((const char *)[s->output bytes])[0]==0,"control space sends NUL");
  [s->output setLength:0]; feed(p,"\033="); key(p,'1',NSNumericPadKeyMask);
  check(sent(s,"\033Oq"),"application numeric keypad");
  [s->output setLength:0]; feed(p,"\033>\033[?2004l"); [p sendString:@"plain\ntext"];
  check(sent(s,"plain\rtext"),"unbracketed paste and newline normalization");
  feed(p,"\033c\2332;3HZ");
  check(s->cells[1][2].ch=='Z',"eight-bit CSI control");
  feed(p,"\2352;title \xc3\x9c\234");
  check([s->title isEqualToString:@"title Ü"],"UTF-8 OSC content is distinct from eight-bit ST");
  feed(p,"\033]2;split title\a");
  [s->output setLength:0]; feed(p,"\033[1;38;2;12;34;56m\033P$qm\033\\");
  check(sent(s,"\033P1$r0;1;38;2;12;34;56m\033\\"),"DCS status query reports actual pen");
  {
    NSMutableData *oversized=[NSMutableData dataWithLength:70000];
    memset([oversized mutableBytes],'z',[oversized length]);
    feed(p,"\033c\033]2;");
    [p processBytes:[oversized bytes] length:[oversized length]];
    feed(p,"\aOK");
    check([s->title isEqualToString:@"split title"] && s->cells[0][0].ch=='O',
          "oversized OSC is discarded without changing the title");
  }

  {
    /* Deterministic streaming stress: odd chunks, mode switches and tiny grids.
       Run the same test under ASan/UBSan to catch parser and resize overruns. */
    unsigned int random=0x4e415449;
    const char *sequences[]={"\033[2J","\033[?1049h","\033[?1049l",
      "\033[2;5r","\033[?6h","\033[?6l","\033[?69h\033[2;6s",
      "\033[?69l","\033[100P","\033[100@","\033[100L","\033[100M",
      "\033[31;48;2;1;2;3m","\033[0m","\033[s","\033[u",
      "\033[H","\033[999;999H","\033[3J","\033[?7l","\033[?7h",
      "\xe7\x95\x8c","e\xcc\x81","\033Pbad\033\\","\033]2;stress\a"};
    int iteration, w=12, h=5;
    BOOL valid=YES;
    feed(p,"\033c");
    for (iteration=0; iteration<10000; iteration++)
      {
        random=random*1664525U+1013904223U;
        if (iteration%37==0)
          {
            w=1+(random%80); h=1+((random>>8)%30);
            [p setTerminalScreenWidth:w height:h];
          }
        const char *sequence=sequences[random%(sizeof(sequences)/sizeof(sequences[0]))];
        NSUInteger n;
        for (n=0; n<strlen(sequence); n++) [p processByte:sequence[n]];
        unsigned char byte=32+((random>>16)%224);
        [p processByte:byte];
        if (s->x<0 || s->x>=w || s->y<0 || s->y>=h) valid=NO;
        int row, col;
        for (row=0; row<h; row++)
          for (col=0; col<w; col++)
            {
              int size=s->cells[row][col].originalCell.width;
              if (size==2 && (col+1>=w || s->cells[row][col+1].originalCell.width!=0)) valid=NO;
              if (size==0 && (col==0 || s->cells[row][col-1].originalCell.width!=2)) valid=NO;
            }
        if (!valid)
          {
            fprintf(stderr,"stress failure at %d: grid %dx%d, cursor %d,%d, sequence %s\n",
                    iteration,w,h,s->x,s->y,sequence);
            break;
          }
      }
    check(valid,"streaming stress preserves cursor bounds and wide-cell invariants");
  }

  RELEASE(p); RELEASE(s); RELEASE(pool);
  return failures ? 1 : 0;
}

