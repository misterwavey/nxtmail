;
; NXTMAIL - mailer for ZX Spectrum Next
;   uses Next Mailbox Protocol 0.1

                        ;   zeusemulate "48K"
                        zeusemulate "Next", "RAW"       ; RAW prevents Zeus from adding some BASIC emulator-friendly

zoLogicOperatorsHighPri = false                         ; data like the stack and system variables. Not needed because
zoSupportStringEscapes  = true                          ;
zxAllowFloatingLabels   = false                         ; this only runs on the Next, and everything is already present.

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


DisplayMenu             PrintLine(0,0,MENU_LINE_1,20)   ;
                        PrintLine(0,1,MENU_LINE_2,20)   ;
                        PrintLine(0,2,MENU_LINE_3,15)   ;
                        PrintLine(0,3,MENU_LINE_4,24)   ;
                        PrintLine(0,18,MboxHost,23)     ;
                        ld a, (CONNECTED)               ;
                        cp 1                            ;
                        jp z, PrintConnected            ;
                        PrintLine(MboxHostLen+1,18,OFFLINE,7);
                        ret                             ;
PrintConnected          ld hl,(MSG_COUNT)               ;
                        inc hl                          ;
                        dec hl                          ; trick for zero check
                        jp z, PrintZeroMessages         ; don't convert message count to ascii if zero (ldir uses len in BC)
                        call ConvertWordToAsc           ; otherwise do
                        ld bc, (WordLen)                ;
                        ld de, MSG_COUNT_BUF            ;
                        ld hl, (WordStart)              ;
                        ldir                            ;
                        PrintLine(0,19,MSG_COUNT_BUF,(WordLen)) ;
                        jp PrintNick                    ;
PrintZeroMessages       PrintLine(1,19,MSG_COUNT_ZERO,1)
PrintNick               PrintLine(3,19,MBOX_BLANK_NICK,20) ;
                        PrintLine(3,19,MBOX_NICK,20)    ;
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
;                        jp HandleMenuChoice             ;
                        ret                             ;

;
; register
;

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
; cmds
;
; 1. register user for app
;
; response:
;
; pos:       |  0      | 1              |
; size:      |  1      | 20             |
; field:     | status  | nickname       |
; condition: |         | status=101/201 |

RegisterUserId:         
                        ld a, MBOX_CMD_REGISTER         ; send:     0   1  1   1  98  97 104 111 106 115 105 98 111 102 108 111 98 117 116 115 117 106 97 114
                        ld h, 0                         ; result: 201 115 116 117 97 114 116   0   0   0   0   0  0   0   0   0
                        ld l, 2+1+1+20                  ; proto+cmd+app+userid
                        ld de, INBUF                    ;
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
PrintBadUser            PrintLine(6,19,MBOX_BLANK_NICK, 20);
                        PrintLine(6,19,BAD_USER_MSG, 20) ; otherwise
                        ret                             ;
PrintNickname           ld a, 1                         ;
                        ld (CONNECTED), a               ;
                        ld de, MBOX_NICK                ;
                        ld hl, (ResponseStart)          ;
                        inc hl                          ; move past status
                        ld bc, 20                       ; userids are 20
                        ldir                            ;
                        ; PrintLine(30,0,MBOX_NICK,20)    ;
                        call SaveFile                   ;
                        ret                             ;


;
; handle send message
;

HandleSend              PrintAt(0,4)                    ;
                        PrintChar(50)                   ;
                        ;                       jp HandleMenuChoice             ;
                        ret                             ;

;
; handle iew message
;

HandleViewMessage       PrintAt(0,4)                    ;
                        PrintChar(50)                   ;
                        ;                       jp HandleMenuChoice             ;
                        ret                             ;
; 3. get message count
;
; response:
;
; pos:      | 0      | 1            |
; size:     | 1      | 1            |
; field:    | status | messageCount |
; condition |        | status=202   |

HandleCount             ld a, MBOX_CMD_MESSAGE_COUNT    ; send:     0 1 4 1 98 97 104 111 106 115 105 98 111 102 108 111 98 117 116 115 117 106 97 114
                        ld h, 0                         ; result: 202 3
                        ld l, 2+1+1+20                  ; proto+cmd+app+userid
                        ld de, INBUF                    ;
                        call MakeCIPSend                ;
                        call ProcessMsgCountResponse    ;
                        ret                             ;

ProcessMsgCountResponse ld hl, (ResponseStart)          ;
                        ld a, (hl)                      ;
                        cp MBOX_STATUS_COUNT_OK         ;
                        jp nz, PrintProblem             ;
                        PrintLine(0,16, OK, 2)          ;
                        inc hl                          ; move past status
                        ld a, (hl)                      ; get count
                        ld (MSG_COUNT), a               ; store
                        inc hl                          ; get 2nd byte
                        ld a, (hl)                      ;
                        ld (MSG_COUNT+1), a             ; store 2nd
                        ld a, (MSG_COUNT)               ; pull 1st back
                        call PrintAHexNoSpace           ; display
                        ret                             ;
PrintProblem            PrintLine(6,19,BAD_USER_MSG, 20) ;
                        ret                             ;


MENU_LINE_1             defb "1. Register userId  "     ;
MENU_LINE_2             defb "2. Send message     "     ;
MENU_LINE_3             defb "3. view message"          ;
MENU_LINE_4             defb "4. refresh message count" ;
REG_PROMPT              defb "Enter your Next Mailbox Id";
PROMPT                  defb "> "                       ;
OK                      defb "OK"                       ;
BAD_USER_MSG            defb "<no user registered>"     ;

INBUF                   defs 128, ' '                   ; our input buffer
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
MBOX_BLANK_NICK         defs 20,' '                     ;
CONNECTED               defb 00                         ;
MSG_COUNT               defb $0,$0                      ;
MSG_COUNT_BUF           defs 6                          ;
MSG_COUNT_ZERO          defb '0'
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


include                 "esp.asm"                       ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
include                 "constants.asm"                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
include                 "msg.asm"                       ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
include                 "parse.asm"                     ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
include                 "macros.asm"                    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
include                 "esxDOS.asm"                    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
include                 "cip.asm"                       ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
include                 "file.asm"                      ;;;;;;;;;;;;;
include                 "keys.asm"                      ;;;;;;;;;
include                 "zeus.asm"                      ; syntax highlighting;;;;;;


; Raise an assembly-time error if the expression evaluates false
zeusassert              zeusver<=78, "Upgrade to Zeus v4.00 (TEST ONLY) or above, available at http://www.desdes.com/products/oldfiles/zeustest.exe";
; zeusprint               zeusver                         ;
; Generate a NEX file                                   ; Instruct the .NEX loader to write the file handle to this
                        ;        output_z80 "NxtMail.z80",$FF40, Main ; ;;;;;;;;;;;;;;;;;;;;;;;;;;;
                        output_nex "NxtMail.nex", $FF40, Main ; Generate the file, with SP argument followed PC;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                        ; Zeus "just knows" which 16K banks to include in the .NEX file,
                        ; making generation a one-liner if you don't want loading screens
                        ; or external palette files. See History/Documentation in Zeus
                        ; for complete instructions and syntax.
