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
ROM_CHAN_OPEN           equ $1601                       ; THE 'CHAN-OPEN' SUBROUTINE
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
                        nextreg NXREG_TURBO_CTL, CPU_28 ; Next Turbo Control Register $07: 11b is 28MHz
                        call MakeCIPStart               ; setup comms to server

MainLoop                call SetupScreen                ;
                        call LoadFile                   ; obtain any previously saved userid and register userid with server
                        call DisplayMenu                ;
                        call HandleMenuChoice           ;

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

ClearCentre             PrintAt(0,9)                    ;
                        ld bc, 51*10                    ;
ClearLoop               PrintChar(' ')                  ;
                        dec bc                          ;
                        ld a,c                          ;
                        or b                            ;
                        jp nz ClearLoop                 ;
                        ret                             ;

;
; display main menu
;

DisplayMenu             call ClearCentre                ;
                        PrintLine(0,0,MENU_LINE_1,20)   ;
                        PrintLine(0,1,MENU_LINE_2,20)   ;
                        PrintLine(0,2,MENU_LINE_3,15)   ;
                        PrintLine(0,3,MENU_LINE_4,24)   ;
                        PrintLine(0,20,MboxHost,23)     ;
                        ld a, (CONNECTED)               ;
                        cp 1                            ;
                        jp z, PrintConnected            ;
                        PrintLine(MboxHostLen+1,18,OFFLINE,7);
                        ret                             ;
PrintConnected          ld hl,(MSG_COUNT)               ;
                        inc (hl)                        ;
                        dec (hl)                        ; trick for zero check
                        cp 0                            ; is message count 0?
                        jp z, PrintZeroMessages         ; don't convert message count to ascii if zero (ldir uses len in BC)
                        ld hl, (MSG_COUNT)              ;
                        call ConvertWordToAsc           ; otherwise do
                        ld bc, (WordLen)                ;
                        ld de, MSG_COUNT_BUF            ;
                        ld hl, (WordStart)              ;
                        ldir                            ;
                        PrintLineLenVar(0,21,MSG_COUNT_BUF,WordLen) ;
                        jp PrintNick                    ;
PrintZeroMessages       PrintLine(1,21,MSG_COUNT_ZERO,1);
PrintNick               PrintLine(3,21,MBOX_BLANK_NICK,20) ;
                        PrintLineLenVar(3,21,MBOX_NICK, MBOX_NICK_LEN) ;
                        ret                             ;

;
; HandleMenuChoice
;

HandleMenuChoice        ei                              ;
                        call ROM_KEY_SCAN               ;
                        di                              ;
                        inc d                           ; no shiftkey = ff
                        jp nz,HandleMenuChoice          ; ignore shifted key combos
                        ld a,e                          ; a: = key code of key pressed (ff if none).
                        cp $24                          ; check for 1 key
                        jp z,HandleRegister             ;
                        cp $1c                          ; check for 2 key
                        jp z,HandleSend                 ;
                        cp $14                          ; check for 3 key
                        jp z, HandleViewMessage         ;
                        cp $0c                          ; check for 4 key
                        jp z, HandleCount               ;
EndLoop                 jp HandleMenuChoice             ;

HandleRegister          PrintLine(0,5,REG_PROMPT, 26)   ;
                        PrintLine(0,6,PROMPT, 2)        ;
                        call HandleUserIdInput          ;
                        cp $20                          ; was last key pressed a space?
                        ret z                           ; yes. back to menu - input was cancelled by break
                        PrintLine(0,8,OK, 2)            ;
                        call RegisterUserId             ;
                        PrintLine(0,8,OK, 2)            ;
                        call PressKeyToContinue         ;
                        call ClearCentre                ;
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
; process registration response
;


ProcessRegResponse      ld hl, (ResponseStart)          ;
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_USR_ALR_REG      ; already? no problem
                        jp z, PrintNickname             ;
                        cp MBOX_STATUS_REGISTER_OK      ; ok? cool
                        jp z, PrintNickname             ;
PrintBadUser            PrintLine(6,21,MBOX_BLANK_NICK, 20);
                        PrintLine(6,21,BAD_USER_MSG, 20) ; otherwise
                        ret                             ;
PrintNickname           ld a, 1                         ;
                        ld (CONNECTED), a               ;
                        ld de, MBOX_NICK                ;
                        ld hl, (ResponseStart)          ;
                        inc hl                          ; move past status
                        ld bc, 20                       ; nicks/userids are 20
                        ldir                            ;
                        call CalcUserNickLength         ;
                        call SaveFile                   ;
                        ret                             ;

;
; calc the len of the user's nick
;
CalcUserNickLength      ld a, $00                       ;
                        ld hl, MBOX_NICK                ;
                        ld bc, 20                       ; nick max len
                        cpir                            ; find first $00 or bc == 0
                        ld a, c                         ;
                        or b                            ; bc == 0?
                        jp z, LenIsMax                  ; yes: set size to 20
                        ld a, 20                        ; no: calc len of 20 - bc
                        sub c                           ; if bc max is 20, b is 0
                        ld (MBOX_NICK_LEN), a           ;
                        ret                             ;

LenIsMax                ld a, 20                        ;
                        ld (MBOX_NICK_LEN), a           ;
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


HandleSend              call ClearCentre                ;
                        call WipeTargetNick             ;
                        call HandleGetTargetNick        ;
                        ret c                           ; if we exited via BREAK
                        call TerminateTargetNick        ;
                        ld hl,TARGET_NICK_BUF           ; check we've got at least 1 char in the nickname
                        ld a,(hl)                       ;
                        cp 0                            ;
                        jp z, HandleSend                ; nope
                        call HandleCheckNick            ; is the nick registered?
                        jp z, HandleSend                ; nope

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
                        ret                             ;
;
;
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

TerminateTargetNick     ld hl, TARGET_NICK_BUF          ;  set trailing $0s after text for remainder of nick
                        ld a, ' '                       ;
                        ld bc, 20                       ;
                        cpir                            ;
                        jp nz,NoSpaces                  ;
                        dec hl                          ; found a space so back up
                        inc c                           ; including counter
                        ld d,h                          ; copy remaining counter's worth of $0s over the rest of the nick
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), 0                      ;
                        ldir                            ;
NoSpaces                ret                             ;

WipeOutMsg              ld hl, OUT_MESSAGE              ;   fill nick with spaces (0s cause problems when printing to screen)
                        ld d,h                          ;
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), $09                    ;
                        ld bc, 200                      ;
                        ldir                            ;
                        ret                             ;

WipeTargetNick          ld hl, TARGET_NICK_BUF          ;   fill nick with spaces (0s cause problems when printing to screen)
                        ld d,h                          ;
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), ' '                    ;
                        ld bc, 20                       ;
                        ldir                            ;
                        ret                             ;

BuildSendMsgRequest     ld (MBOX_CMD), a                ;
                        ld de, REQUESTBUF               ; entire server request string
                        WriteString(MBOX_PROTOCOL_BYTES, 2);
                        WriteString(MBOX_CMD, 1)        ;
                        WriteString(MBOX_APP_ID, 1)     ; 1=nextmail
                        WriteString(USERIDBUF,20)       ; userid
                        WriteString(TARGET_NICK_BUF,20) ;
                        WriteString(OUT_MESSAGE,200)    ;
                        ret                             ;

HandleGetTargetNick     ld b, 20                        ; collect 20 chars for userId
                        ld c, $24                       ; used to debounce
                        ld hl, TARGET_NICK_BUF          ; which buffer to store chars
                        PrintLine(0,5,NICK_PROMPT, NICK_PROMPT_LEN) ;
GetNickInputLoop        PrintLine(3,6,TARGET_NICK_BUF, 20) ; show current buffer contents
                        push hl                         ;
                        push bc                         ;
                        ei                              ;
                        call ROM_KEY_SCAN               ; d=modifier e=keycode or $ff
                        di                              ;
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
                        scf                             ; yes: set carry for return status
                        ret z                           ; back to menu
                        jp nz, GetNickInputLoop         ; no. collect another char

GetNickDelete           push af                         ; yes
                        ld a,b                          ; let's see if we've got any chars to delete
                        cp 0                            ;
                        jp z, GetNickInputLoop          ; no. collect another char
                        pop af                          ; yes
                        cp c                            ; is this key same as last keypress?
                        jp z, GetNickInputLoop          ; yes. = debounce
                        ld c, a                         ; no. store key for next debounce check
                        ld (hl), ' '                    ; blank current char
                        dec hl                          ; and reposition buffer pointer
                        inc b                           ; and collected char count
                        jp GetNickInputLoop             ; collect another char

GetNickNoShiftPressed   ld a,e                          ; do we have a key pressed?
                        cp $ff                          ;
                        jp z, GetNickNoKeyPressed       ; no
                        cp $21                          ; enter?
                        ret z                           ;
                        push bc                         ; we have a keypress without shift
                        push hl                         ;
                        ld b, 0                         ;
                        ld c, a                         ;  bc = keycode value
                        ld hl, ROM_KEYTABLE             ;  hl = code to ascii lookup table
                        add hl, bc                      ;  find ascii given keycode
                        ld a, (hl)                      ;
                        pop hl                          ;
                        pop bc                          ;
                        cp $20                          ; check if >= 32 (ascii space)
                        jp c,GetNickInputLoop           ; no, ignore
                        cp $7f                          ; check if <= 126 (ascii ~)
                        jp nc,GetNickInputLoop          ; no, ignore
                        cp c                            ; does key = last keypress?
                        jp z, GetNickInputLoop          ; yes - debounce
                        ld c, a                         ; no - store char in c for next check
                        ld (hl),a                       ; no - store char in buffer
                        inc hl                          ;
                        dec b                           ; one less char to collect
                        ld a,b                          ;
                        cp 0                            ; collected all chars?
                        ld a, c                         ;    (restore after the count check)
                        ccf                             ; clear c for return status
                        ret z                           ; yes
                        jp GetNickInputLoop             ; no

GetNickNoKeyPressed     cp c                            ; is current keycode same as last?
                        jp z, GetNickInputLoop          ; yes - just loop again
                        ld c, a                         ; no, update c to show change
                        jp GetNickInputLoop             ;

HandleGetOutMsg         ld b, 200                       ; collect 20 chars for userId
                        ld c, $24                       ; used to debounce
                        ld hl, OUT_MESSAGE              ; which buffer to store chars
                        PrintLine(0,5,MSG_GET_MSG_PROMPT, MSG_GET_MSG_PROMPT_LEN) ;
GetMsgInputLoop         PrintLine(3,6,OUT_MESSAGE, 200) ; show current buffer contents
                        push hl                         ;
                        push bc                         ;
                        ei                              ;
                        call ROM_KEY_SCAN               ; d=modifier e=keycode or $ff
                        di                              ;
                        pop bc                          ;
                        pop hl                          ;
                        ld a,d                          ; do we have a key modifier? (ss CS etc)
                        cp $ff                          ;
                        jp nz, GetMsgShiftCheck         ; yes
                        jp GetMsgNoShiftPressed         ; no

GetMsgShiftCheck        cp $27                          ; $27=CS - check if caps shift is pressed (CS + 0 = delete)
                        jp nz, GetMsgNoShiftPressed     ; no
                        ld a,e                          ; yes. check 2nd char
                        cp $23                          ; $23=0 - is 2nd char 0 key? (CS + 0 = delete)
                        jp z, GetMsgDelete              ; yes
                        cp $20                          ; no. is 2nd char SPACE? (CS+SP=break)
                        scf                             ; yes: set carry for return status
                        ret z                           ; back to menu
                        jp nz, GetMsgInputLoop          ; no. collect another char

GetMsgDelete            push af                         ; yes
                        ld a,b                          ; let's see if we've got any chars to delete
                        cp 0                            ;
                        jp z, GetMsgInputLoop           ; no. collect another char
                        pop af                          ; yes
                        cp c                            ; is this key same as last keypress?
                        jp z, GetMsgInputLoop           ; yes. = debounce
                        ld c, a                         ; no. store key for next debounce check
                        ld (hl), ' '                    ; blank current char
                        dec hl                          ; and reposition buffer pointer
                        inc b                           ; and collected char count
                        jp GetMsgInputLoop              ; collect another char

GetMsgNoShiftPressed    ld a,e                          ; do we have a key pressed?
                        cp $ff                          ;
                        jp z, GetMsgNoKeyPressed        ; no
                        cp $21                          ; enter?
                        ret z                           ;
                        push bc                         ; we have a keypress without shift
                        push hl                         ;
                        ld b, 0                         ;
                        ld c, a                         ;  bc = keycode value
                        ld hl, ROM_KEYTABLE             ;  hl = code to ascii lookup table
                        add hl, bc                      ;  find ascii given keycode
                        ld a, (hl)                      ;
                        pop hl                          ;
                        pop bc                          ;
                        cp $20                          ; check if >= 32 (ascii space)
                        jp c,GetMsgInputLoop            ; no, ignore
                        cp $7f                          ; check if <= 126 (ascii ~)
                        jp nc,GetMsgInputLoop           ; no, ignore
                        cp c                            ; does key = last keypress?
                        jp z, GetMsgInputLoop           ; yes - debounce
                        ld c, a                         ; no - store char in c for next check
                        ld (hl),a                       ; no - store char in buffer
                        inc hl                          ;
                        dec b                           ; one less char to collect
                        ld a,b                          ;
                        cp 0                            ; collected all chars?
                        ld a, c                         ;    (restore after the count check)
                        ccf                             ; clear c for return status
                        ret z                           ; yes
                        jp GetMsgInputLoop              ; no

GetMsgNoKeyPressed      cp c                            ; is current keycode same as last?
                        jp z, GetMsgInputLoop           ; yes - just loop again
                        ld c, a                         ; no, update c to show change
                        jp GetMsgInputLoop              ;

; HandleGetMessageToSend  ld de, OUT_MESSAGE              ;
;                        ld hl, DUMMY_MESSAGE            ;
;                        ld bc, 50                       ;
;                        ldir                            ;
;                        ret                             ;

ProcessSendResponse     ld hl, (ResponseStart)          ;
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_OK               ;
                        jp nz, PrintProblemSend         ;
                        PrintLine(15, 15, OK, 2)        ;
                        call PressKeyToContinue         ;
                        ret                             ;
PrintProblemSend        PrintLine(15,15, MSG_ERR_SENDING,MSG_ERR_SENDING_LEN);
                        call PressKeyToContinue         ;
                        call ClearCentre                ;
                        ret                             ;

;
; handle check registered nickname
; ENTRY
;    USERIDBUF is set to valid userid
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
                        WriteString(USERIDBUF,20)       ; userid
                        WriteString(TARGET_NICK_BUF,20) ;
                        ret                             ;

ProcessNickResponse     ld hl, (ResponseStart)          ;
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_UNREG_NICK       ;
                        jp z, UnregisteredNick          ;
                        ret                             ; Z unset
UnregisteredNick        PrintLine(0,16,MSG_UNREG_NICK, MSG_UNREG_NICK_LEN);
                        call PressKeyToContinue         ;
                        ld a, 0                         ;
                        or a                            ; Z set
                        ret                             ;

; handle view message
;

; 4. getMessage
;
; response:
;
; pos:      | 0      | 1          | 2          |
; size:     | 1      | 1          | n          |
; field:    | status | messagelen | message    |
; condition |        | status=203 | status=203 |

HandleViewMessage       call WipeMsgId                  ;  replace with ' 's
                        call HandleGetMsgId             ;  input 1-5 digits
                        call TerminateMsgId             ;  place 0 at end of input if < 5
                        call CountMsgIdLen              ;  populate MSG_ID_BUF_LEN with the num digits in the id
                        DecodeDecimal(MSG_ID_BUF, MSG_ID_BUF_LEN) ; populate hl with the numerical value of the input id
                        ld (MBOX_MSG_ID), hl            ;
                        ld a, MBOX_CMD_GET_MESSAGE      ; send:
                        call BuildGetMsgRequest         ;
                        ld h, 0                         ; result: 0
                        ld l, 2+1+1+20+2                ; proto+cmd+app+userid+2_id_bytes
                        ld de, REQUESTBUF               ;
                        call MakeCIPSend                ;
                        call ProcessGetResponse         ;
                        ret                             ;

CountMsgIdLen           ld hl, MSG_ID_BUF               ;
                        ld a, ' '                       ;
                        ld bc, 5                        ; nick max len
                        cpir                            ; find first $00 or bc == 0
                        ld a, c                         ;
                        or b                            ; bc == 0?
                        jp z, MsgIdLenIsMax             ; yes: set size to 5
                        ld a, 5                         ; no: calc len of 5 - bc
                        sub c                           ; if bc max is 5, b is 0
                        ld (MSG_ID_BUF_LEN), a          ;
                        ret                             ;

MsgIdLenIsMax           ld a, 5                         ;
                        ld (MSG_ID_BUF_LEN), a          ;
                        ret                             ;

TerminateMsgId          ld hl, MSG_ID_BUF               ;  set trailing $0s after text for remainder of number
                        ld a, ' '                       ;
                        ld bc, 5                        ;
                        cpir                            ;
                        jp nz,MsgIdNoSpaces             ;
                        dec hl                          ; found a space so back up
                        inc c                           ; including counter
                        ld d,h                          ; copy remaining counter's worth of $0s over the rest of the nick
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), 0                      ;
                        ldir                            ;
MsgIdNoSpaces           ret                             ;

WipeMsgId               ld hl, OUT_MESSAGE              ;   fill nick with spaces (0s cause problems when printing to screen)
                        ld d,h                          ;
                        ld e,l                          ;
                        inc de                          ;
                        ld (hl), ' '                    ;
                        ld bc, 5                        ;
                        ldir                            ;
                        ret                             ;

BuildGetMsgRequest      ld (MBOX_CMD), a                ;
                        ld de, REQUESTBUF               ; entire server request string
                        WriteString(MBOX_PROTOCOL_BYTES, 2);
                        WriteString(MBOX_CMD, 1)        ; cmd is get message by id
                        WriteString(MBOX_APP_ID, 1)     ; 1=nextmail
                        WriteString(USERIDBUF,20)       ; userid
                        WriteString(MBOX_MSG_ID,2)      ; param 1 is msg id
                        ret                             ;

HandleGetMsgId          ld b, 5                         ; collect 1-5 chars for msg id (0-65535)
                        ld c, $24                       ; used to debounce
                        ld hl, MSG_ID_BUF               ; which buffer to store chars
                        PrintLine(0,5,MSG_ID_PROMPT, MSG_ID_PROMPT_LEN) ;
GetMsgIdInputLoop       PrintLine(3,6,MSG_ID_BUF, 5)    ; show current buffer contents
                        push hl                         ;
                        push bc                         ;
                        ei                              ;
                        call ROM_KEY_SCAN               ; d=modifier e=keycode or $ff
                        di                              ;
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

GetMsgIdDelete          push af                         ; yes
                        ld a,b                          ; let's see if we've got any chars to delete
                        cp 0                            ;
                        jp z, GetMsgIdInputLoop         ; no. collect another char
                        pop af                          ; yes
                        cp c                            ; is this key same as last keypress?
                        jp z, GetMsgIdInputLoop         ; yes. = debounce
                        ld c, a                         ; no. store key for next debounce check
                        ld (hl), ' '                    ; blank current char
                        dec hl                          ; and reposition buffer pointer
                        inc b                           ; and collected char count
                        jp GetMsgIdInputLoop            ; collect another char

GetMsgIdNoShiftPressed  ld a,e                          ; do we have a key pressed?
                        cp $ff                          ;
                        jp z, GetMsgIdNoKeyPressed      ; no
                        cp $21                          ; enter?
                        ret z                           ; yes, we're done
                        push bc                         ; we have a keypress without shift
                        push hl                         ;
                        ld b, 0                         ;
                        ld c, a                         ;  bc = keycode value
                        ld hl, ROM_KEYTABLE             ;  hl = code to ascii lookup table
                        add hl, bc                      ;  find ascii given keycode
                        ld a, (hl)                      ;
                        pop hl                          ;
                        pop bc                          ;
                        cp $30                          ; check if >= 48 (ascii '0')
                        jp c,GetMsgIdInputLoop          ; no, ignore
                        cp $3a                          ; check if < 58 (ascii '9'+1)
                        jp nc,GetMsgIdInputLoop         ; no, ignore
                        cp c                            ; does key = last keypress?
                        jp z, GetMsgIdInputLoop         ; yes - debounce
                        ld c, a                         ; no - store char in c for next check
                        ld (hl),a                       ; no - store char in buffer
                        inc hl                          ;
                        dec b                           ; one less char to collect
                        ld a,b                          ;
                        cp 0                            ; collected all chars?
                        ld a, c                         ;    (restore after the count check)
                        ccf                             ; clear c for return status
                        ret z                           ; yes
                        jp GetMsgIdInputLoop            ; no

GetMsgIdNoKeyPressed    cp c                            ; is current keycode same as last?
                        jp z, GetMsgIdInputLoop         ; yes - just loop again
                        ld c, a                         ; no, update c to show change
                        jp GetMsgIdInputLoop            ;

;HandleGetMsgId          ld a, 1                         ;  TODO get user input
;                        ld (MBOX_MSG_ID), a             ;
;                        ret                             ;

ProcessGetResponse      ld hl, (ResponseStart)          ;  status byte
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_GET_MSG_OK       ; is it ok?
                        jp nz, PrintBadMsgId            ; no - show error
                        inc hl                          ; yes - move past status byte
                        ld a, (hl)                      ; this is len
                        ld (IN_MSG_LEN), a              ;
                        ld de, IN_MESSAGE               ; populate in_messge with contents of response
                        inc hl                          ; move past len byte into start of msg
                        ld bc, (IN_MSG_LEN)             ;
                        ldir                            ;
                        PrintLineLenVar(0,10,IN_MESSAGE,IN_MSG_LEN);
                        call PressKeyToContinue         ;
                        ret                             ;

PrintBadMsgId           PrintLine(0,15,BAD_MSG_ID,BAD_MSG_ID_LEN) ;
                        call PressKeyToContinue         ;
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
                        ret                             ;

ProcessMsgCountResponse ld hl, (ResponseStart)          ;
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_COUNT_OK         ;
                        jp nz, PrintProblem             ;
                        inc hl                          ; move past status
                        ld a, (hl)                      ; get count
                        ld (MSG_COUNT), a               ; store
                        ; inc hl                          ; get 2nd byte
                        ; ld a, (hl)                      ;
                        ; ld (MSG_COUNT+1), a             ; store 2nd

                        PrintAt(15,15)                  ;
                        ld a, (MSG_COUNT)               ; pull 1st back
                        call PrintAHexNoSpace           ; display
                        ret                             ;
PrintProblem            PrintLine(6,21,BAD_USER_MSG, BAD_USER_MSG_LEN) ;
                        ret                             ;

;
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
                        WriteString(USERIDBUF,20)       ; userid
                        ret                             ;

PressKeyToContinue      PrintLine(0,17, MSG_PRESS_KEY, MSG_PRESS_KEY_LEN);
KeyLoop                 ei                              ;
                        call ROM_KEY_SCAN               ; d=modifier e=keycode or $ff
                        di                              ;
                        ld a,d                          ; do we have a key modifier? (ss CS etc)
                        cp $ff                          ; ff=no
                        ret nz                          ; yes, return
                        ld a,e                          ;
                        cp $ff                          ; ff=no
                        ret nz                          ; yes, return
                        jp KeyLoop                      ; otherwise continue to check for input

MENU_LINE_1             defb "1. Register userId  "     ;
MENU_LINE_2             defb "2. Send message     "     ;
MENU_LINE_3             defb "3. view message"          ;
MENU_LINE_4             defb "4. refresh message count" ;
REG_PROMPT              defb "Enter your Next Mailbox Id";
REG_PROMPT_LEN          equ $-REG_PROMPT                ;
PROMPT                  defb "> "                       ;
OK                      defb "OK"                       ;
BAD_USER_MSG            defb "<no user registered>"     ;
BAD_USER_MSG_LEN        equ $-BAD_USER_MSG              ;

USERIDBUF               defs 128, ' '                   ; our input buffer
BUFLEN                  defs 1                          ;
FILEBUF                 defs 128                        ;

FILE_NAME               defb "/nxtMail2/nxtMail.dat",0  ;
DIR_NAME                defb "/nxtMail2",0              ;
MboxHost:               defb "nextmailbox.spectrum.cl"  ;
MboxHostLen             equ $-MboxHost                  ;
OFFLINE                 defb "offline"                  ;
ONLINE_AS               defb "as "                      ;
MESSAGES                defb "000 messages"             ;
MboxPort:               defb "8361"                     ;
MboxPortLen:            equ $-MboxPort                  ;

MBOX_PROTOCOL_BYTES     defb $00, $01                   ;
MBOX_APP_ID             defb $01                        ; nxtmail is app 1 in db
MBOX_CMD                defb $01                        ;
MBOX_NICK               defs 20                         ;
MBOX_NICK_LEN           defb 00,00                      ;
MBOX_BLANK_NICK         defs 20,' '                     ;
CONNECTED               defb 00                         ;
MSG_COUNT               defb $0,$0                      ;
MSG_COUNT_BUF           defs 6                          ;
MSG_COUNT_ZERO          defb '0'                        ;
SENDBUF                 defb 255                        ;
TARGET_NICK             defs 20, 0                      ;
OUT_MESSAGE             ds 200,$09                      ; gets printed so fill with tab
REQUESTBUF              ds 256                          ;
RequestLenAddr:         dw $0000                        ;
RequestBufAddr:         dw $0000                        ;
RequestLen              defb 0,0                        ;
WordStart:              ds 5                            ;
WordLen:                dw $0000                        ;
ResponseStart:          dw $0000                        ;
ResponseLen:            dw $0000                        ;
Prescaler:              ds 3                            ;
Buffer:                 ds 256                          ;
BufferLen               equ $-Buffer                    ;
MsgBuffer:              ds 256                          ;
MsgBufferLen            equ $-MsgBuffer                 ;
TARGET_NICK_BUF         defs 20,' '                     ;
TARGET_NICK_LEN         defb 0,0                        ; 2 because we'll point BC at it for ldir
MSG_ID_PROMPT           defb "Message number (0-65535. Enter to end)" ;
MSG_ID_PROMPT_LEN       equ $-MSG_ID_PROMPT             ;
MSG_ID_BUF              defs 5,' '                      ; '0'-'65535'
MSG_ID_BUF_LEN          defb 0                          ; length of the digits entered 1-5
MBOX_MSG_ID             defb 0,0                        ; 2 bytes for 0-65535
IN_MSG_LEN              defb 0,0                        ; 2 because we'll point BC at it for ldir
IN_MESSAGE              defs 200                        ;
BAD_MSG_ID              defb "bad message number"       ;
BAD_MSG_ID_LEN          equ $-BAD_MSG_ID                ;
MSG_ERR_SENDING         defb "Error sending message"    ;
MSG_ERR_SENDING_LEN     equ $-MSG_ERR_SENDING           ;
MSG_PRESS_KEY           defb "Press any key to continue";
MSG_PRESS_KEY_LEN       equ $-MSG_PRESS_KEY             ;
MSG_UNREG_NICK          defb "Nick is unregistered with NxtMail";
MSG_UNREG_NICK_LEN      equ $-MSG_UNREG_NICK            ;
NICK_PROMPT             defb "To nickname: (20 chars. Enter to end)" ;
NICK_PROMPT_LEN         equ $-NICK_PROMPT               ;
MSG_GET_MSG_PROMPT      defb "Message body: (200 max. Enter to end)";
MSG_GET_MSG_PROMPT_LEN  equ $-MSG_GET_MSG_PROMPT        ;

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
