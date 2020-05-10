;
; NXTMAIL - mailer for ZX Spectrum Next
;   uses Next Mailbox Protocol 0.1

; request:
; protocol maj=0 min=1
; 26 chars is min len of valid request
;
; pos:   |  0        | 2    |  3   |  4     | 25           | 46      |
; size:  |  2        | 1    |  1   |  20    | 20           | 255     |
; field: |  protocol | cmd  |  app | userid | param1:      | message |
;        |           |      |      |        | nickname / * |         |
;        |           |      |      |        | or msgid     |         |
;

                        ;   zeusemulate "48K"
                        zeusemulate "Next", "RAW"       ; RAW prevents Zeus from adding some BASIC emulator-friendly
                        zoLogicOperatorsHighPri = false ; data like the stack and system variables. Not needed because
                        zoSupportStringEscapes = true   ; this only runs on the Next, and everything is already present.
                        zxAllowFloatingLabels = false   ;

; NextZXOS APIs
IDE_MODE                equ $01d5                       ; used to set the characters per line

; Spectrum ROM routines
ROM_KEYTABLE            equ $0205                       ; convert from keycode to ascii
ROM_KEY_SCAN            equ $028e                       ;
ROM_CHAN_OPEN           equ $1601                       ; to allow us to print to the upper screen
ROM_PR_STRING           equ $203c                       ;

; Next registers
NXREG_TURBO_CTL         equ $07                         ; set CPU speed
CPU_28                  equ 11b                         ; 11b = 28MHz

; Next Mailbox Protocol
MBOX_STATUS_OK          equ 0                           ;
MBOX_STATUS_INV_PROTO   equ 1                           ;
MBOX_STATUS_INV_CMD     equ 2                           ;
MBOX_STATUS_INV_APP     equ 3                           ;
MBOX_STATUS_INV_USERID  equ 4                           ;
MBOX_STATUS_INV_LENGTH  equ 5                           ;
MBOX_STATUS_INT_ERR     equ 6                           ;
MBOX_STATUS_MISS_NICK   equ 7                           ;
MBOX_STATUS_MISS_MSG    equ 8                           ;
MBOX_STATUS_UNIMPL      equ 9                           ;
MBOX_STATUS_MISS_MSG_ID equ 10                          ;

MBOX_STATUS_USR_ALR_REG equ 101                         ;
MBOX_STATUS_UNREG_NICK  equ 102                         ;
MBOX_STATUS_UNK_USERID  equ 103                         ;
MBOX_STATUS_UNREG_USER  equ 104                         ;

MBOX_STATUS_REGISTER_OK equ 201                         ;
MBOX_STATUS_COUNT_OK    equ 202                         ;
MBOX_STATUS_GET_MSG_OK  equ 203                         ;
MBOX_STATUS_INV_MSG_ID  equ 204                         ;

MBOX_CMD_REGISTER       equ 1                           ;
MBOX_CMD_CHECK_REG_NICK equ 2                           ;
MBOX_CMD_SEND_MESSAGE   equ 3                           ;
MBOX_CMD_MESSAGE_COUNT  equ 4                           ;
MBOX_CMD_GET_MESSAGE    equ 5                           ;
MBOX_CMD_GET_RAND_USERS equ 6                           ; # ?
MBOX_CMD_AWAIT_USERS    equ 7                           ; # session / group?



org                     $8000                           ; This should keep our code clear of NextBASIC sysvars
                        ;                                 (Necessary for making NextZXOS API calls);
;
; main loop
;
Main                    proc                            ;
                        di                              ;
                        nextreg NXREG_TURBO_CTL, CPU_28 ; Next Turbo Control Register to set cpu speed
                        call MakeCIPStart               ; setup comms to server

                        call SetupScreen                ;
                        call LoadFile                   ; obtain any previously saved userid and register userid with server
                        call DisplayMenu                ;
                        call DisplayStatus              ;
MainLoop                call HandleMenuChoice           ;

                        jp MainLoop                     ;
pend

;
; end of main
;



;
; setup screen
;
SetupScreen             Border(7)                       ; 7=white
                        OpenOutputChannel(2)            ; ROM: Open channel to upper screen (channel 2)
SetLayer1_1             ld a, 1                         ; set layer via IDE_MODE using M_P3DOS (needs bank 7)
                        ld b, 1                         ; if A=1, change mode to:
                        ld c, 1                         ;   B=layer (0,1,2)
                        M_P3DOS(IDE_MODE,7)             ;   C=sub-mode (if B=1): 0=lo-res, 1=ula, 2=hi-res, 3=hi-col                                                        ;
ClearScreen             ld a,14                         ; 'clear window control code' (for layers 1+) (see IDE_MODE docs)
                        rst $10                         ;  ROM print a char
SetFontWidth            PrintChar(30)                   ; set char width in pixels
                        PrintChar(5)                    ; to 5 (51 chars wide)
                        ret                             ;

;
; clear centre panel of any text
;
ClearCentre             PrintAt(0,7)                    ;
                        ld bc, 51*13                    ; 52 cols * 13 rows.
ClearLoop               PrintChar(' ')                  ;
                        dec bc                          ;
                        ld a,c                          ;
                        or b                            ;
                        jp nz ClearLoop                 ;
                        ret                             ;

;
; display main menu
;
DisplayMenu             call DrawMenuBox                ;
                        PrintLine(1,1,MENU_LINE_1,MENU_LINE_1_LEN) ;
                        PrintLine(1,2,MENU_LINE_2,MENU_LINE_2_LEN) ;
                        PrintLine(1,3,MENU_LINE_3,MENU_LINE_3_LEN) ;
                        PrintLine(1,4,MENU_LINE_4,MENU_LINE_4_LEN) ;
                        ret                             ;
;
; show connected, nick, message counts
;
DisplayStatus           PrintLine(0,21,BLANK_ROW,51)    ;
                        PrintLine(0,22,BLANK_ROW,51)    ;
                        PrintLine(0,23,BLANK_ROW,51)    ;
                        PrintLine(0,21,CONNECTED_TO, CONNECTED_TO_LEN);
                        PrintLine(0+CONNECTED_TO_LEN,21,MboxHost,MboxHostLen) ;
                        ld a, (CONNECTED)               ;
                        cp 1                            ;
                        jp z, PrintConnected            ;
                        PrintLine(MboxHostLen+1,18,OFFLINE,OFFLINE_LEN);
                        ret                             ;   bail because we're offline
PrintConnected          PrintLine(0,22,MSG_NICK,MSG_NICK_LEN) ;
                        PrintLineLenVar(0+MSG_NICK_LEN,22,MBOX_NICK, MBOX_NICK_LEN) ;
                        PrintLine(0,23,MESSAGES,MESSAGES_LEN);
                        PrintLine(49-VERSION_LEN,23,VERSION,VERSION_LEN);
                        ld hl,MSG_COUNT                 ;
                        inc (hl)                        ;
                        dec (hl)                        ; trick for zero check
                        jp z, PrintZeroMessages         ; don't convert message count to ascii if zero (ldir uses len in BC)
                        ld hl, (MSG_COUNT)              ;
                        call ConvertWordToAsc           ; otherwise convert number to ascii: text in WordStart, length in WordLen
                        ld bc, (WordLen)                ; fill MSG_COUNT_BUF with the ascii number
                        ld de, MSG_COUNT_BUF            ;
                        ld hl, (WordStart)              ;
                        ldir                            ;
                        PrintLineLenVar(0+MESSAGES_LEN,23,MSG_COUNT_BUF,WordLen) ;
                        ret                             ;
PrintZeroMessages       PrintLine(0+MESSAGES_LEN,23,MSG_COUNT_ZERO,1);
                        ret                             ;

;
; surround menu with a box
;
DrawMenuBox             PrintLine(0,0,TOP_ROW,51)       ;
                        PrintAt(0,1)                    ;
                        PrintChar(138)                  ;
                        PrintAt(50,1)                   ;
                        PrintChar(133)                  ;

                        PrintAt(0,2)                    ;
                        PrintChar(138)                  ;
                        PrintAt(50,2)                   ;
                        PrintChar(133)                  ;

                        PrintAt(0,3)                    ;
                        PrintChar(138)                  ;
                        PrintAt(50,3)                   ;
                        PrintChar(133)                  ;

                        PrintAt(0,4)                    ;
                        PrintChar(138)                  ;
                        PrintAt(50,4)                   ;
                        PrintChar(133)                  ;

                        PrintLine(0,5,BOT_ROW,51)       ;
                        ret                             ;

; HandleMenuChoice
;
HandleMenuChoice        call ROM_KEY_SCAN               ;
                        inc d                           ; no shiftkey = ff
                        ret nz                          ; ignore shifted key combos
                        ld a,e                          ; a: = key code of key pressed (ff if none).
                        cp $24                          ; check for 1 key
                        jp z, HandleRegister            ;
                        cp $1c                          ; check for 2 key
                        jp z, HandleSend                ;
                        cp $14                          ; check for 3 key
                        jp z, HandleViewMessage         ;
                        cp $0c                          ; check for 4 key
                        jp z, HandleCount               ;
                        ret                             ;
HandleRegister          PrintLine(0,7,REG_PROMPT, REG_PROMPT_LEN) ;
                        PrintLine(0,8,PROMPT, PROMPT_LEN) ;
                        call WipeUserId                 ;
                        call HandleUserIdInput          ;
                        jp c, RegBreak                  ; back to menu - input was cancelled by break
                        call PopulateMboxUserId         ;
                        call RegisterUserId             ;
                        call PressKeyToContinue         ;
RegBreak                call ClearCentre                ;
                        call HandleCount                ; also displays status
                        ret                             ;
;
; copy buffer into fixed location
;
PopulateMboxUserId      ld hl, USER_ID_BUF              ; source
                        ld de, MBOX_USER_ID             ;
                        ld bc, 20                       ;
                        ldir                            ;
                        ret                             ;
;
; register
;

; 1. register user for app
;
; response:
;
; pos:       |  0      | 1              |
; size:      |  1      | 20             |
; field:     | status  | nickname       |
; condition: |         | status=101/201 |

RegisterUserId:         ld a, MBOX_CMD_REGISTER         ;
                        call BuildStandardRequest       ; send:     0   1  1   1  98  97 104 111 106 115 105 98 111 102 108 111 98 117 116 115 117 106 97 114
                        ld de, REQUESTBUF               ; result: 201 115 116 117 97 114 116   0   0   0   0   0  0   0   0   0
                        ld h, 0                         ;
                        ld l, 2+1+1+20                  ; proto+cmd+app+userid
                        call MakeCIPSend                ;
                        call ProcessRegResponse         ;
                        ret                             ;
;
; set all 20 chars of user id to spaces
;
WipeUserId              ld hl, USER_ID_BUF              ;   fill nick with spaces (0s cause problems when printing to screen)
                        ld d,h                          ;
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), ' '                    ;
                        ld bc, 19                       ;
                        ldir                            ;
                        ret                             ;
;
; process registration response
;
ProcessRegResponse      ld hl, (ResponseStart)          ;
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_USR_ALR_REG      ; already? no problem
                        jp z, PrintNickname             ;
                        cp MBOX_STATUS_REGISTER_OK      ; ok? cool
                        jp z, PrintNickname             ;
                        ld a, 0                         ;
BadUser                 ld (CONNECTED), a               ;
                        ret                             ;
PrintNickname           ld a, 1                         ;
                        ld (CONNECTED), a               ;
                        ld de, MBOX_NICK                ;
                        ld hl, (ResponseStart)          ;
                        inc hl                          ; move past status
                        ld bc, 20                       ; nicks/userids are 20
                        ldir                            ;
                        ld hl, MBOX_NICK                ;
                        ld de, MBOX_NICK_LEN            ;
                        call CalcNickLength             ;
                        call SaveFile                   ;
                        ret                             ;


;
; handle send message
;

; 5. sendMessage
;
; response:
;
; pos:   | 0      |
; size:  | 1      |
; field: | status |
HandleSend              call WipeTargetNick             ;
                        call HandleGetTargetNick        ;
                        jp c, SendExit                  ; if we exited via BREAK
                        call TerminateTargetNick        ;
                        ld hl,TARGET_NICK_BUF           ; check we've got at least 1 char in the nickname
                        ld a,(hl)                       ;
                        cp 0                            ;
                        jp z, HandleSend                ; nope
                        call HandleCheckNick            ; is the nick registered?
                        jp z, HandleSend                ; nope. go back around
                        call ClearCentre                ;
                        call WipeOutMsg                 ;
                        call HandleGetOutMsg            ;
                        call TerminateOutMsg            ;
                        ld a, MBOX_CMD_SEND_MESSAGE     ; send:   0 1 3 1 98 97 104 111 106 115 105 98 111 102 108 111 98 117 116 115 117 106 97 114 115 116 117 97 114 116 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 116 104 101 32 113 117 105 99 107 32 98 114 111 119 110 32 102 111 120 0
                        call BuildSendMsgRequest        ;
                        ld h, 0                         ; result: 0
                        ld l, 2+1+1+20+20+200           ; proto+cmd+app+userid+targetnick+message
                        ld de, REQUESTBUF               ;
                        call MakeCIPSend                ;
                        call ProcessSendResponse        ;
                        call PressKeyToContinue         ;
SendExit                call ClearCentre                ;
                        call HandleCount                ;
                        call DisplayStatus              ;
                        ret                             ;
;
; zero pad the remainder of the msg
;
TerminateOutMsg         ld hl, OUT_MESSAGE              ;  set trailing $0s after text for remainder of nick
                        ld a, $09                       ;
                        ld bc, 200                      ;
                        cpir                            ;
                        jp nz,MsgNoSpaces               ;
                        dec hl                          ; found a space so back up
                        inc c                           ; including counter
                        ld d,h                          ; copy remaining counter's worth of $0s over the rest of the nick
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), 0                      ;
                        ldir                            ;
MsgNoSpaces             ret                             ;

;
; zero pad the entered nick
;
TerminateTargetNick     ld hl, TARGET_NICK_BUF          ;  set trailing $0s after text for remainder of nick if nick isn't already full
                        ld a, ' '                       ;
                        ld bc, 20                       ;
                        cpir                            ;
                        ret nz                          ; z set if found a match, so we're done
                        dec hl                          ; found a space so back up
                        inc c                           ; including counter
                        ld d,h                          ; copy remaining counter's worth of $0s over the rest of the nick
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), 0                      ;
                        ldir                            ;
                        ret                             ;

;
; set outgoing message to be tab char (printable and detectable as end of entry)
;
WipeOutMsg              ld hl, OUT_MESSAGE              ;   fill nick with spaces (0s cause problems when printing to screen)
                        ld d,h                          ;
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), $09                    ;
                        ld bc, 199                      ;
                        ldir                            ;
                        ret                             ;
;
; set nick to all spaces so it can be displayed
;
WipeTargetNick          ld hl, TARGET_NICK_BUF          ;   fill nick with spaces (0s cause problems when printing to screen)
                        ld d,h                          ;
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), ' '                    ;
                        ld bc, 19                       ;
                        ldir                            ;
                        ret                             ;

BuildSendMsgRequest     ld (MBOX_CMD), a                ;
                        ld de, REQUESTBUF               ; entire server request string
                        WriteString(MBOX_PROTOCOL_BYTES, 2);
                        WriteString(MBOX_CMD, 1)        ;
                        WriteString(MBOX_APP_ID, 1)     ; 1=nextmail
                        WriteString(MBOX_USER_ID,20)    ; userid
                        WriteString(TARGET_NICK_BUF,20) ;
                        WriteString(OUT_MESSAGE,200)    ;
                        ret                             ;

HandleGetTargetNick     ld b, 20                        ; collect 20 chars for userId
                        ld c, $32                       ; used to debounce ($32 is '2' from menu)
                        ld hl, TARGET_NICK_BUF          ; which buffer to store chars
                        PrintLine(0,7,NICK_PROMPT, NICK_PROMPT_LEN) ;

GetNickInputLoop        PrintLine(3,8,TARGET_NICK_BUF, 20) ; show current buffer contents
                        push hl                         ;
                        push bc                         ;
                        call ROM_KEY_SCAN               ; d=modifier e=keycode or $ff
                        pop bc                          ;
                        pop hl                          ;
                        ld a,d                          ; do we have a key modifier? (ss CS etc)
                        cp $ff                          ;
                        jp nz, GetNickShiftCheck        ; yes
                        jp GetNickNoShiftPressed        ; no

GetNickShiftCheck       cp $27                          ; $27=CS - check if caps shift is pressed (CS + 0 = delete)
                        jp nz, GetNickNoShiftPressed    ; no
                        ld a,e                          ; yes. check 2nd char
                        cp $23                          ; $23=0 - is 2nd char 0 key? (CS + 0 = delete)
                        jp z, GetNickDelete             ; yes
                        cp $20                          ; no. is 2nd char SPACE? (CS+SP=break)
                        scf                             ; set carry for return status
                        ret z                           ; back to menu if yes we pressed break
                        jp GetNickInputLoop             ; no. collect another char

GetNickDelete           ld a,b                          ; let's see if we've got any chars to delete
                        cp 20                           ;
                        jp z, GetNickInputLoop          ; no. ignore this delete
                        ld a,e                          ; yes. get keypress again
                        cp c                            ; is this key same as last keypress?
                        jp z, GetNickInputLoop          ; yes. = debounce
                        ld c, a                         ; no. store key for next debounce check
                        dec hl                          ; and reposition buffer pointer
                        ld (hl), ' '                    ; blank current char
                        inc b                           ; and increase the needed-chars count
                        jp GetNickInputLoop             ; collect another char

GetNickNoShiftPressed   ld a,e                          ; do we have a key pressed?
                        cp $ff                          ;
                        jp z, GetNickNoKeyPressed       ; no
                        cp $21                          ; enter?
                        ret z                           ; yes. we're done here
                        ld a, b                         ; can we allow more chars?
                        cp 0                            ; got all our chars?
                        ld a,e                          ;   place key into a again
                        jp z, GetNickNoKeyPressed       ; not allowed any more chars until delete is pressed
                        push bc                         ; we have a keypress without shift
                        push hl                         ;
                        ld b, 0                         ;
                        ld c, a                         ;  bc = keycode value
                        ld hl, ROM_KEYTABLE             ;  hl = code to ascii lookup table
                        add hl, bc                      ;  find ascii, given keycode
                        ld a, (hl)                      ;
                        pop hl                          ;
                        pop bc                          ;
                        cp $20                          ; check if >= 32 (ascii space)
                        jp c,GetNickInputLoop           ; no, ignore
                        cp $7f                          ; check if <= 126 (ascii ~)
                        jp nc,GetNickInputLoop          ; no, ignore
                        cp c                            ; does key = last keypress?
                        jp z, GetNickInputLoop          ; yes - debounce
                        ld c, a                         ; no - store char in c for next debounce check
                        ld (hl),a                       ; no - store char in buffer
                        inc hl                          ;
                        dec b                           ; one less char to collect
                        jp GetNickInputLoop             ; no

GetNickNoKeyPressed     cp c                            ; is current keycode same as last?
                        jp z, GetNickInputLoop          ; yes - just loop again
                        ld c, a                         ; no, update c to show change
                        jp GetNickInputLoop             ;

HandleGetOutMsg         ld b, 200                       ; collect 20 chars for userId
                        ld c, $24                       ; used to debounce
                        ld hl, OUT_MESSAGE              ; which buffer to store chars
                        PrintLine(0,7,MSG_GET_MSG_PROMPT, MSG_GET_MSG_PROMPT_LEN) ;
GetMsgInputLoop         PrintLine(3,8,OUT_MESSAGE, 200) ; show current buffer contents
                        push hl                         ;
                        push bc                         ;
                        call ROM_KEY_SCAN               ; d=modifier e=keycode or $ff
                        pop bc                          ;
                        pop hl                          ;
                        ld a,d                          ; do we have a key modifier? (ss CS etc)
                        cp $ff                          ; ff = no mod keypress?
                        jp z, GetMsgNotBreakOrDelete    ; if no mod key pressed
                        cp $27                          ; yes: $27=CS - check if caps shift is pressed (CS + 0 = delete)
                        jp nz, GetMsgNotBreakOrDelete   ; no
                        ld a,e                          ; yes. check 2nd char
                        cp $23                          ; $23=0 - is 2nd char 0 key? (CS + 0 = delete)
                        jp z, GetMsgDelete              ; yes
                        cp $20                          ; no. is 2nd char SPACE? (CS+SP=break)
                        scf                             ; yes: set carry for return status
Break                   ret z                           ; BREAK back to menu
                        jp GetMsgNotBreakOrDelete       ; no. collect another char

GetMsgDelete            ld a,b                          ; let's see if we've got any chars to delete
                        cp 200                          ;
                        jp z, GetMsgInputLoop           ; no. collect another char
                        ld a,e                          ; yes. get keypress again
                        cp c                            ; is this key same as last keypress?
                        jp z, GetMsgInputLoop           ; yes. = debounce
                        ld c, a                         ; no. store key for next debounce check
                        dec hl                          ; and reposition buffer pointer
                        ld (hl), ' '                    ; blank current char
                        inc b                           ; and collected char count
                        jp GetMsgInputLoop              ; collect another char

GetMsgNotBreakOrDelete  ld a,e                          ; do we have a (non mod) key pressed?
                        cp $ff                          ;  ff means no
                        jp z, GetMsgNoKeyPressed        ; no
                        cp $21                          ; yes - was it enter?
                        jp nz,NoCharsYet                ; not enter
                        ld a,b                          ; yes enter - check we've got at least 1 char
                        cp 200                          ;
                        jp z,NoCharsYet                 ; no: skip enter
                        ret                             ; yes: we're done
NoCharsYet              ld a,b                          ; any spare room in the buffer?
                        cp 0                            ;
                        jp z, GetMsgInputLoop           ; we can't take any more until delete/enter
                        ld a,e                          ; not break, not delete, not enter
                        push bc                         ;
                        push hl                         ;
                        ld b, 0                         ;
                        ld c, a                         ;  bc = keycode value
                        ld hl, ROM_KEYTABLE             ;  hl = code to ascii lookup table
                        add hl, bc                      ;  find ascii given keycode
                        ld a, (hl)                      ;   A is ascii
                        cp 'A'-1                          ; >= 'A'?  ($41 is 'A')
                        jp c,NotAZ                      ; < 'A'
                        cp 'Z'+1                         ; <= 'Z'?
                        jp nc, NotAZ                    ; > 'Z'
                        add a,$20                       ; convert A-Z uppercase to lowercase
NotAZ                   pop hl                          ;
                        pop bc                          ;
                        ld e,a                          ; preserve A as ascii key
                        ld a,d                          ; recheck modifier key
                        cp $18                          ; SS?
                        jp z, HandleSymShift            ;
                        cp $27                          ; CS?
                        jp z, HandleCapsShift           ;
                        ld a,e                          ; restore A as ascii key
                        jp DoneModifying                ;

HandleCapsShift         ld a,e                          ; restore A as ascii key
                        cp 'a'                          ; >= 'a'?
                        jp c,NotLowercaseAZ             ;
                        cp 'z'+1                        ; <= 'z'?
                        jp nc, NotLowercaseAZ           ;
                        ; otherwise get uppercase
                        sub $20                         ; take off 32d to make a-z uppercase
NotLowercaseAZ          jp DoneModifying                ;

HandleSymShift          ld a,e                          ;   (restore A as ascii keypress)
                        push hl                         ;
                        push bc                         ;
                        cp '0'                          ; between 0-1?
                        jp c,NotNum                     ;
                        cp '9'+1                        ;
                        jp nc,NotNum                    ;
                        ld hl, SSHIFT_TABLE_NUM         ; yes, use num lookup table
                        sub '0'                         ; find offset from ascii
                        ld b,0                          ;
                        ld c,a                          ; add offset into SSHIFT table
                        add hl, bc                      ;
                        ld a, (hl)                      ;
                        cp 0                            ; is there a modifier for this key?
                        jp nz,DoneSymMod                ; if so: keep current val
                        ld a,e                          ; if not: restore original ascii key
                        jp DoneSymMod                   ;

NotNum                  cp 'a'                          ; between a-z?
                        jp c,DoneSymMod                 ;
                        cp 'z'+1                        ;
                        jp nc,DoneSymMod                ;
                        ld hl, SSHIFT_TABLE_AZ          ; yes, use az lookup table
                        sub 'a'                         ; find offset from ascii
                        ld b,0                          ;
                        ld c,a                          ; add offset into SSHIFT table
                        add hl, bc                      ;
                        ld a, (hl)                      ;
                        cp 0                            ; is there a modifier for this key?
                        jp nz,DoneSymMod                ; if so: keep current val
                        ld a,e                          ; if not: restore original ascii key
DoneSymMod              pop bc                          ;
                        pop hl                          ;
DoneModifying           cp ' '                          ; >= ' '?
                        jp c,GetMsgNoKeyPressed         ;
                        cp 'z' + 1                      ; <= 'z'?
                        jp nc, GetMsgNoKeyPressed       ;
                        cp c                            ; does key = last keypress?
                        jp z, GetMsgInputLoop           ; yes - debounce
                        ld c, a                         ; no - store char in c for next check
                        ld (hl),a                       ; no - store char in buffer
                        inc hl                          ;
                        dec b                           ; one less char to collect
                        jp GetMsgInputLoop              ; no

GetMsgNoKeyPressed      cp c                            ; is current keycode same as last?
                        jp z, GetMsgInputLoop           ; yes - just loop again
                        ld c, a                         ; no, update c to show change
                        jp GetMsgInputLoop              ;

ProcessSendResponse     ld hl, (ResponseStart)          ;
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_OK               ;
                        jp nz, PrintProblemSend         ;
                        PrintLine(15, 15, OK, OK_LEN)   ;
                        ret                             ;
PrintProblemSend        PrintLine(15,15, MSG_ERR_SENDING,MSG_ERR_SENDING_LEN);
                        ret                             ;

;
; handle check registered nickname
; ENTRY
;    MBOX_USER_ID is set to valid userid
;    TARGET_NICK_BUF is set to $0 terminated nick max 20 len
; EXIT
;    Z set if nick is unregistered with nextmail otherwise Z is unset
;
; 2. check nickname registered for app
;
; response:
;
; pos:   | 0      |
; size:  | 1      |
; field: | status |
;

HandleCheckNick         ld a, MBOX_CMD_CHECK_REG_NICK   ; send:
                        call BuildNickRequest           ;
                        ld h, 0                         ; result: 0
                        ld l, 2+1+1+20+20               ; proto+cmd+app+userid+nick
                        ld de, REQUESTBUF               ;
                        call MakeCIPSend                ;
                        call ProcessNickResponse        ;
                        ret                             ;

BuildNickRequest        ld (MBOX_CMD), a                ;
                        ld de, REQUESTBUF               ; entire server request string
                        WriteString(MBOX_PROTOCOL_BYTES, 2);
                        WriteString(MBOX_CMD, 1)        ;
                        WriteString(MBOX_APP_ID, 1)     ; 1=nextmail
                        WriteString(MBOX_USER_ID,20)    ; userid
                        WriteString(TARGET_NICK_BUF,20) ;
                        ret                             ;

ProcessNickResponse     ld hl, (ResponseStart)          ;
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_UNREG_NICK       ;
                        jp z, UnregisteredNick          ;
                        ret                             ; Z unset
UnregisteredNick        PrintLine(0,16,MSG_UNREG_NICK, MSG_UNREG_NICK_LEN);
                        ld a, 0                         ;
                        or a                            ; Z set
                        ret                             ;

;
; handle view message
;

; 4. getMessage
;
; response:
;
; pos:      | 0      | 1          | 21         | 23         |
; size:     | 1      | 20         | 2          | n          |
; field:    | status | senderNick | messagelen | message    |
; condition |        |              status=203              |
;
HandleViewMessage       call WipeMsgId                  ;  fill entire string with ' ' ready for display
                        call HandleGetMsgId             ;  input 1-5 digits
                        call TerminateMsgId             ;  place 0 at end of input if < 5
                        call CountMsgIdLen              ;  populate MSG_ID_BUF_LEN with the num digits in the id

                        DecodeDecimal(MSG_ID_BUF, MSG_ID_BUF_LEN) ; populate hl with the numerical value of the input id
                        ld (MBOX_MSG_ID), hl            ;
                        ld a, MBOX_CMD_GET_MESSAGE      ;
                        call BuildGetMsgRequest         ;
                        ld h, 0                         ;
                        ld l, 2+1+1+20+2                ; 2x_proto+cmd+app+userid+2x_msg_id
                        ld de, REQUESTBUF               ;
                        call MakeCIPSend                ;
                        call ProcessGetResponse         ;
                        call PressKeyToContinue         ;
                        call ClearCentre                ;
                        call DisplayStatus              ;

                        ret                             ;

CountMsgIdLen           ld hl, MSG_ID_BUF               ;
                        ld a, 0                         ;
                        ld bc, 5                        ; nick max len
                        cpir                            ; find first ' ' or bc == 0
                        jp nz, MsgIdLenIsMax            ; z if match
                        ld a, 5                         ; no: calc len of 5 - bc
                        inc c                           ;
                        sub c                           ; if bc max is 5, b is 0, so just use c
                        ld (MSG_ID_BUF_LEN), a          ;
                        ret                             ;
MsgIdLenIsMax           ld a, 5                         ;
                        ld (MSG_ID_BUF_LEN), a          ;
                        ret                             ;

TerminateMsgId          ld hl, MSG_ID_BUF               ;  set trailing $0s after text for remainder of number
                        ld a, ' '                       ;
                        ld bc, 5                        ;
                        cpir                            ;
                        ret nz                          ; z only set if match found, so return if we've nothing to terminate
                        dec hl                          ; found a space so back up
                        inc c                           ; including counter
                        ld d,h                          ; copy remaining counter's worth of $0s over the rest of the msgid
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), 0                      ;
                        ldir                            ;
                        ret                             ;

WipeMsgId               ld hl, MSG_ID_BUF               ; fill id with spaces (0s cause problems when printing to screen)
                        ld d,h                          ;
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), ' '                    ;
                        ld bc, 4                        ;
                        ldir                            ;
                        ret                             ;

BuildGetMsgRequest      ld (MBOX_CMD), a                ;
                        ld de, REQUESTBUF               ; entire server request string
                        WriteString(MBOX_PROTOCOL_BYTES, 2);
                        WriteString(MBOX_CMD, 1)        ; cmd is get message by id
                        WriteString(MBOX_APP_ID, 1)     ; 1=nextmail
                        WriteString(MBOX_USER_ID,20)    ; userid
                        WriteString(MBOX_MSG_ID,2)      ; param 1 is msg id
                        ret                             ;

HandleGetMsgId          ld b, 5                         ; collect 1-5 chars for msg id (1-65535)
                        ld c, $14                       ; used to debounce (initially '3' from menu choice)
                        ld hl, MSG_ID_BUF               ; which buffer to store chars
                        PrintLine(0,7,MSG_ID_PROMPT, MSG_ID_PROMPT_LEN) ;
                        PrintLine(1,8,PROMPT,PROMPT_LEN);
GetMsgIdInputLoop       PrintLine(3,8,MSG_ID_BUF, 5)    ; show current buffer contents
                        push hl                         ;
                        push bc                         ;
                        call ROM_KEY_SCAN               ; d=modifier e=keycode or $ff
                        pop bc                          ;
                        pop hl                          ;
                        ld a,d                          ; do we have a key modifier? (ss CS etc)
                        cp $ff                          ;
                        jp nz, GetMsgIdShiftCheck       ; yes
                        jp GetMsgIdNoShiftPressed       ; no

GetMsgIdShiftCheck      cp $27                          ; $27=CS - check if caps shift is pressed (CS + 0 = delete)
                        jp nz, GetMsgIdNoShiftPressed   ; no
                        ld a,e                          ; yes. check 2nd char
                        cp $23                          ; $23=0 - is 2nd char 0 key? (CS + 0 = delete)
                        jp z, GetMsgIdDelete            ; yes
                        cp $20                          ; no. is 2nd char SPACE? (CS+SP=break)
                        scf                             ; yes: set carry for return status
                        ret z                           ; back to menu
                        jp nz, GetMsgIdInputLoop        ; no. collect another char

GetMsgIdDelete          ld a,b                          ; let's see if we've got any chars to delete
                        cp 5                            ;
                        jp z, GetMsgIdInputLoop         ; no. collect another char
                        ld a,e                          ; yes. getkeypress again
                        cp c                            ; is this key same as last keypress?
                        jp z, GetMsgIdInputLoop         ; yes. = debounce
                        ld c, a                         ; no. store key for next debounce check
                        dec hl                          ; and reposition buffer pointer
                        ld (hl), ' '                    ; blank current char
                        inc b                           ; and collected char count
                        jp GetMsgIdInputLoop            ; collect another char

GetMsgIdNoShiftPressed  ld a,e                          ; do we have a key pressed?
                        cp $ff                          ;
                        jp z, GetMsgIdNoKeyPressed      ; no
                        cp $21                          ; yes: is it enter?
                        ret z                           ; yes, we're done
                        push bc                         ; no: so we have a keypress without shift
                        push hl                         ;
                        ld b, 0                         ;
                        ld c, a                         ;  bc = keycode value
                        ld hl, ROM_KEYTABLE             ;  hl = code-to-ascii lookup table
                        add hl, bc                      ;  find ascii given keycode
                        ld a, (hl)                      ; a = ascii code for keypress
                        pop hl                          ; hl = input buffer
                        pop bc                          ; b=char count c=last keypress
                        cp $30                          ; check if >= 48 (ascii '0')
                        jp c,GetMsgIdInputLoop          ; no, ignore
                        cp $3a                          ; check if < 58 (ascii '9'+1)
                        jp nc,GetMsgIdInputLoop         ; no, ignore
                        ld d,a                          ; d = copy of ascii val
                        ld a,e                          ; a = original keypress
                        cp c                            ; does key = last keypress?
                        jp z, GetMsgIdInputLoop         ; yes - debounce
                        ld c,a                          ; no - store keypress in c for next debounce check
                        ld a,d                          ; a = ascii version again
                        ld (hl),a                       ; no - store ascii char in buffer
                        inc hl                          ;
                        dec b                           ; one less char to collect
                        ld a, c                         ;    (restore after the count check)
                        ret z                           ; is b now 0? return if so
                        jp GetMsgIdInputLoop            ; no

GetMsgIdNoKeyPressed    cp c                            ; is current keycode same as last? ($ff if no key pressed)
                        jp z, GetMsgIdInputLoop         ; yes - just loop again
                        ld c, a                         ; no, update c to show change
                        jp GetMsgIdInputLoop            ;

ProcessGetResponse      ld hl, (ResponseStart)          ;  status byte
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_GET_MSG_OK       ; is it ok?
                        jp nz, PrintBadMsgId            ; no - show error
                        inc hl                          ; yes - move past status byte into sender's nick
                        ld de, IN_NICK                  ; will hold our copy of the msg sender's nick
                        ld bc, 20                       ;
                        ldir                            ;
                        push hl                         ; hl pointing after nick
                        ld de, IN_NICK_LEN              ;
                        ld hl, IN_NICK                  ;
                        call CalcNickLength             ;
                        pop hl                          ; pointing at msg len
                        ld a, (hl)                      ; this is msg len
                        ld (IN_MSG_LEN), a              ;
                        ld de, IN_MESSAGE               ; populate in_messge with contents of response
                        inc hl                          ; move past len byte into start of msg
                        ld bc, (IN_MSG_LEN)             ;
                        ldir                            ;
                        PrintLine(0,10,MSG_FROM,MSG_FROM_LEN);
                        PrintLineLenVar(0+MSG_FROM_LEN,10,IN_NICK,IN_NICK_LEN);
                        PrintLineLenVar(0,12,IN_MESSAGE,IN_MSG_LEN);
                        ret                             ;

PrintBadMsgId           PrintLine(0,15,BAD_MSG_ID,BAD_MSG_ID_LEN) ;
                        ret                             ;

;
; fetch number of messages for user
;

; 3. get message count
;
; response:
;
; pos:      | 0      | 1            |
; size:     | 1      | 1            |
; field:    | status | messageCount |
; condition |        | status=202   |

HandleCount             ld a, MBOX_CMD_MESSAGE_COUNT    ;
                        call BuildStandardRequest       ; send:     0   1  1   1  98  97 104 111 106 115 105 98 111 102 108 111 98 117 116 115 117 106 97 114
                        ld de, REQUESTBUF               ; result: 201 115 116 117 97 114 116   0   0   0   0   0  0   0   0   0
                        ld h, 0                         ;
                        ld l, 2+1+1+20                  ; proto+cmd+app+userid
                        call MakeCIPSend                ;
                        call ProcessMsgCountResponse    ;
                        call DisplayStatus              ;

                        ret                             ;

ProcessMsgCountResponse ld hl, (ResponseStart)          ;
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_COUNT_OK         ;
                        jp nz, PrintProblem             ;
                        inc hl                          ; move past status
                        ld a, (hl)                      ; get count
                        ld (MSG_COUNT), a               ; store
                        inc hl                          ; get 2nd byte
                        ld a, (hl)                      ;
                        ld (MSG_COUNT+1), a             ; store 2nd
                        ret                             ;
PrintProblem            PrintLine(6,21,BAD_USER_MSG, BAD_USER_MSG_LEN) ;
                        ret                             ;

;                                                              ;
; calc the len of the user's nick (20 bytes)
; nicks are 1+ characters with trailing $00s
;
; ENTRY: HL address of nick
;        DE address of nick_len (2 bytes)
; EXIT: (DE) contains nick len
;
CalcNickLength          ld a, $00                       ;
                        ld bc, 20                       ; nick max len
                        cpir                            ; find first $00 or bc == 0
                        jp nz, LenIsMax                 ; z only set if match found
                        inc c                           ; back up the counter
                        ld a, 20                        ; no: calc len of 20 - bc
                        sub c                           ; if bc max is 20, b is 0
                        ld (de), a                      ;
                        ret                             ;

LenIsMax                ld a, 20                        ;
                        ld (de), a                      ;
                        ret                             ;


; BuildStandardRequest
;
; ENTRY
;  A = MBOX CMD
; EXIT
;  REQUESTBUF is populated ready for CIPSEND
;
BuildStandardRequest    ld (MBOX_CMD), a                ;
                        ld de, REQUESTBUF               ; entire server request string
                        WriteString(MBOX_PROTOCOL_BYTES, 2);
                        WriteString(MBOX_CMD, 1)        ;
                        WriteString(MBOX_APP_ID, 1)     ; 1=nextmail
                        WriteString(MBOX_USER_ID,20)    ; userid
                        ret                             ;

PressKeyToContinue      PrintLine(10,17, MSG_PRESS_KEY, MSG_PRESS_KEY_LEN);
KeyLoop                 call ROM_KEY_SCAN               ; d=modifier e=keycode or $ff
                        ld a,d                          ; do we have a key modifier? (ss CS etc)
                        cp $ff                          ; ff=no
                        ret nz                          ; yes, return
                        ld a,e                          ;
                        cp $ff                          ; ff=no
                        ret nz                          ; yes, return
                        jp KeyLoop                      ; otherwise continue to check for input

BAD_MSG_ID              defb "bad message number"       ;
BAD_MSG_ID_LEN          equ $-BAD_MSG_ID                ;
BAD_USER_MSG            defb "<no user registered>"     ;
BAD_USER_MSG_LEN        equ $-BAD_USER_MSG              ;
Buffer:                 ds 256                          ;
BufferLen               equ $-Buffer                    ;
BUFLEN                  defs 1                          ;
CONNECTED               defb 00                         ;
CONNECTED_TO            defb "Connected to "            ;
CONNECTED_TO_LEN        equ $-CONNECTED_TO              ;
DIR_NAME                defb "/nxtMail2",0              ;
FILEBUF                 defs 128                        ;
FILE_NAME               defb "/nxtMail2/nxtMail.dat",0  ;
HYPHEN                  defb '-'                        ;
IN_MESSAGE              defs 200                        ;
IN_MSG_LEN              defb 0,0                        ; 2 because we'll point BC at it for ldir
IN_NICK                 defs 20                         ;
IN_NICK_LEN             defb 0,0                        ;
MboxHost                defb "nextmailbox.spectrum.cl"  ;
MboxHostLen             equ $-MboxHost                  ;
MboxPort:               defb "8361"                     ;
MboxPortLen:            equ $-MboxPort                  ;
MBOX_APP_ID             defb $01                        ; nxtmail is app 1 in db
MBOX_BLANK_NICK         defs 20,' '                     ;
MBOX_CMD                defb $01                        ;
MBOX_MSG_ID             defb 0,0                        ; 2 bytes for 0-65535
MBOX_NICK               defs 20                         ;
MBOX_NICK_LEN           defb 00,00                      ;
MBOX_PROTOCOL_BYTES     defb $00, $01                   ;
MBOX_USER_ID            defs 20                         ; the one used for transmission to allow the working buffer to be reset
MENU_LINE_1             defb "1. Connect/Register userId" ;
MENU_LINE_1_LEN         equ $-MENU_LINE_1               ;
MENU_LINE_2             defb "2. Send message"          ;
MENU_LINE_2_LEN         equ $-MENU_LINE_2               ;
MENU_LINE_3             defb "3. View message"          ;
MENU_LINE_3_LEN         equ $-MENU_LINE_3               ;
MENU_LINE_4             defb "4. Refresh message count" ;
MENU_LINE_4_LEN         equ $-MENU_LINE_4               ;
MESSAGES                defb "Messages: "               ;
MESSAGES_LEN            equ $-MESSAGES                  ;
MSG_COUNT               defb $0,$0                      ;
MSG_COUNT_BUF           defs 5                          ;
MSG_COUNT_ZERO          defb '0'                        ;
MSG_ERR_SENDING         defb "Error sending message"    ;
MSG_ERR_SENDING_LEN     equ $-MSG_ERR_SENDING           ;
MSG_GET_MSG_PROMPT      defb "Message body: (200 max. Enter to end)";
MSG_GET_MSG_PROMPT_LEN  equ $-MSG_GET_MSG_PROMPT        ;
MSG_FROM                defb "From: "                   ;
MSG_FROM_LEN            equ $-MSG_FROM                  ;
MSG_ID_BUF              defs 5,' '                      ; '1'-'65535'
MSG_ID_BUF_LEN          defb 0                          ; length of the digits entered 1-5
MSG_ID_PROMPT           defb "Message number (1-65535. Enter to end)" ;
MSG_ID_PROMPT_LEN       equ $-MSG_ID_PROMPT             ;
MSG_PRESS_KEY           defb "Press any key to continue";
MSG_PRESS_KEY_LEN       equ $-MSG_PRESS_KEY             ;
MSG_UNREG_NICK          defb "Nick is unregistered with NxtMail";
MSG_UNREG_NICK_LEN      equ $-MSG_UNREG_NICK            ;
MSG_NICK                defb "Nick: "                   ;
MSG_NICK_LEN            equ $-MSG_NICK                  ;
NICK_PROMPT             defb "To nickname: (20 chars. Enter to end)" ;
NICK_PROMPT_LEN         equ $-NICK_PROMPT               ;
OFFLINE                 defb "offline"                  ;
OFFLINE_LEN             equ $-OFFLINE                   ;
OK                      defb "OK"                       ;
OK_LEN                  equ $-OK                        ;
OUT_MESSAGE             ds 200,$09                      ; gets printed so fill with tab (not 0s and not space because users use space)
PROMPT                  defb "> "                       ;
PROMPT_LEN              equ $-PROMPT                    ;
REG_PROMPT              defb "Enter your Next Mailbox Id (then enter)";
REG_PROMPT_LEN          equ $-REG_PROMPT                ;
REQUESTBUF              ds 256                          ;
SENDBUF                 defb 255                        ;
TARGET_NICK_BUF         defs 20,' '                     ;
TARGET_NICK_LEN         defb 0,0                        ; 2 because we'll point BC at it for ldir
USER_ID_BUF             defs 20, ' '                    ; our input buffer
VERSION                 defb "nxtMail v0.4 2020 Tadaguff";
VERSION_LEN             equ $-VERSION                   ;

TOP_ROW                 defb 139,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131;
                        defb 131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131;
                        defb 131,131,131,131,131,131,131,131,131,131,135;
BOT_ROW                 defb 142,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140;
                        defb 140,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140,140;
                        defb 140,140,140,140,140,140,140,140,140,140,141;
BLANK_ROW               defs 51,' '                     ;

                        ; asc 0  1   2   3   4   5   6   7    8   9
SSHIFT_TABLE_NUM        defb 00,'!','@','#','$','%','&','\'','(',')';;;;;;

                        ; asc A  B   C  D E F G  H  I  J   K   L   M   N   O    P  Q  R  S  T  U  V  W  X  Y  Z
SSHIFT_TABLE_AZ         defb 00,'*','?',0,0,0,0,'^',0,'-','+','=','.',',',";",'\"',0,'<',0,'>',0,'/',0,'`',0,':'; note: ` is £ in speccy

                        include "esp.asm"               ;
                        include "constants.asm"         ;
                        include "msg.asm"               ;
                        include "parse.asm"             ;
                        include "macros.asm"            ;
                        include "esxDOS.asm"            ;
                        include "cip.asm"               ;
                        include "file.asm"              ;
                        include "keys.asm"              ;
                        include "zeus.asm"              ; syntax highlighting


; Raise an assembly-time error if the expression evaluates false
                        zeusassert zeusver<=78, "Upgrade to Zeus v4.00 (TEST ONLY) or above, available at http://www.desdes.com/products/oldfiles/zeustest.exe";
; zeusprint               zeusver                         ;
; Generate a NEX file                                   ; Instruct the .NEX loader to write the file handle to this
                        ;        output_z80 "NxtMail.z80",$FF40, Main ;
                        output_nex "NxtMail.nex", $FF40, Main ; Generate the file, with SP argument followed PC
                        ; Zeus "just knows" which 16K banks to include in the .NEX file,
                        ; making generation a one-liner if you don't want loading screens
                        ; or external palette files. See History/Documentation in Zeus
                        ; for complete instructions and syntax.
