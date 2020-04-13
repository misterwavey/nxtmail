;
; NXTMAIL - mailer for ZX Spectrum Next
;   uses Next Mailbox Protocol 0.1

                        zeusemulate "48K"               ;
                        ;  zeusemulate "Next", "RAW"       ; RAW prevents Zeus from adding some BASIC emulator-friendly;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
zoLogicOperatorsHighPri = false                         ; data like the stack and system variables. Not needed because
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

org                     $8000                           ; This should keep our code clear of NextBASIC sysvars
                        ;                                 (Necessary for making NextZXOS API calls);
Main                    proc                            ;
                        di                              ;
;                        nextreg NXREG_TURBO_CTL, CPU_28 ; Next Turbo Control Register $07: 11b is 28MHz
                        Border(7)                       ; 7=white
                        OpenOutputChannel(2)            ; ROM: Open channel to upper screen (channel 2)

; SetLayer1_1             ld a, 1                         ; set layer via IDE_MODE using M_P3DOS (needs bank 7)
;                        ld b, 1                         ; if A=1, change mode to:
;                        ld c, 1                         ;   B=layer (0,1,2)
;                        M_P3DOS(IDE_MODE,7)             ;   C=sub-mode (if B=1): 0=lo-res, 1=ula, 2=hi-res, 3=hi-col                                                        ;

ClearScreen             ld a,14                         ; 'clear window control code' (for layers 1+) (see IDE_MODE docs)
                        rst $10                         ;  ROM print a char

                        ei                              ; reenable for ROM keyscan?
SetFontWidth            PrintChar(30)                   ; set char width in pixels
                        PrintChar(5)                    ; to 5 (51 chars wide)

                        PrintLine(0,0,MENU_LINE_1,20)   ;
                        PrintLine(0,1,MENU_LINE_2,20)   ;
                        PrintLine(0,2,MENU_LINE_3,20)   ;

CheckMenuChoice         call ROM_KEY_SCAN               ;
                        inc d                           ;
                        jp nz,CheckMenuChoice           ; ignore 2 keypresses
                        ld a,e                          ; a: = key code of key pressed (ff if none).
                        cp $24                          ; check for 1 key
                        jp z,HandleRegister             ;
                        cp $1c                          ; check for 2 key
                        jp z,HandleSend                 ;
                        cp $14                          ; check for 3 key
                        jp z, HandleList                ;

EndLoop                 jp CheckMenuChoice              ;
                        pend                            ;

HandleRegister          PrintLine(0,4,REG_PROMPT, 26)   ;
                        PrintLine(0,5,PROMPT, 2)        ;
                        call HandleUuidInput            ;
                        PrintLine(0,8,OK, 2)            ;
                        jp Main.CheckMenuChoice         ;

; TODO allow exit with BREAK
HandleUuidInput         ld b, 36                        ; collect 36 chars for uuid
                        ld c,0                          ; used to debounce
                        ld hl, INBUF                    ; which buffer to store chars
InputLoop               PrintLine(3,5,INBUF, 36)        ; show current buffer contents   TODO restore to 51
                        push hl                         ;
                        push bc                         ;
                        call ROM_KEY_SCAN               ; d=modifier e=keycode or $ff
                        pop bc                          ;
                        pop hl                          ;
                        ld a,d                          ; do we have a key modifier? (ss CS etc)
                        cp $ff                          ;
                        jp nz, ShiftCheck               ; yes
                        jp NoShiftPressed               ; no

ShiftCheck              cp $27                          ; $27=CS - check if caps shift is pressed (CS + 0 = delete)
                        jp nz, NoShiftPressed           ; no
                        ld a,e                          ; yes. check 2nd char
                        cp $23                          ; $23=0 - is 2nd char 0 key? (CS + 0 = delete)
                        jp nz, InputLoop                ; no. collect another char
Delete                  ld a,b                          ; yes. let's see if we've got any chars to delete
                        cp 0                            ;
                        jp z, InputLoop                 ; no. collect another char
                        ld (hl), ' '                    ; yes . blank current char
                        dec hl                          ; and reposition buffer pointer
                        inc b                           ; and collected char count
                        jp InputLoop                    ; collect another char

NoShiftPressed          ld a,e                          ; do we have a key pressed?
                        cp $ff                          ;
                        jp z, NoKeyPressed              ; no
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
                        jp c,InputLoop                  ; no, ignore
                        cp $7f                          ; check if <= 126 (ascii ~)
                        jp nc,InputLoop                 ; no, ignore
                        cp c                            ; does key = last keypress?
                        jp z, InputLoop                 ; yes - debounce
                        ld c, a                         ; no - store char in c for next check
                        ld (hl),a                       ; no - store char in buffer
                        inc hl                          ;
                        dec b                           ; one less char to collect
                        ld a,b                          ;
                        cp 0                            ; collected all chars?
                        ld a, c                         ; restore after the count check
                        ret z                           ; yes
                        jp InputLoop                    ;

NoKeyPressed            cp c                            ; is current keycode same as last?
                        jp z, InputLoop                 ; yes - just loop again
                        ld c, a                         ; no, update c to show change
                        jp InputLoop                    ;


HandleSend              PrintAt(0,4)                    ;
                        PrintChar(50)                   ;
                        jp Main.CheckMenuChoice         ;

HandleList              PrintAt(0,4)                    ;
                        PrintChar(51)                   ;
                        jp Main.CheckMenuChoice         ;


MENU_LINE_1             defb "1. Register uuid    "     ;
MENU_LINE_2             defb "2. Send message     "     ;
MENU_LINE_3             defb "3. List messages    "     ;
REG_PROMPT              defb "Enter your Next Mailbox Id";
PROMPT                  defb "> "                       ;
OK                      defb "OK"                       ;

INBUF                   defs 128, ' '                   ; our input buffer
BUFLEN                  defs 1                          ;

PrintLine               macro(X, Y, string, len)        ;
                          push de                       ;
                          push bc                       ;
                          PrintAt(X,Y)                  ;
                          ld de, string                 ; address of string
                          ld bc, len                    ; length of string to print
                          call ROM_PR_STRING            ;
                          pop bc                        ;
                          pop de                        ;
                          mend                          ;

OpenOutputChannel       macro(Channel)                  ; Semantic macro to call a 48K ROM routine
                          ld a, Channel                 ; 2 = upper screen
                          call ROM_CHAN_OPEN            ;
                          mend                          ;

PrintChar               macro(Char)                     ; Semantic macro to call a 48K ROM routine
                          ld a, Char                    ;
                          rst $10                       ; ROM 0010: THE 'PRINT A CHARACTER' RESTART
                          mend                          ;

PrintAt                 macro(X, Y)                     ; Semantic macro to call a 48K ROM routine
                          PrintChar(22)                 ;
                          PrintChar(Y)                  ; X and Y are reversed order, i.e.
                          PrintChar(X)                  ; PRINT AT Y, X
                          mend                          ;

Border                  macro(Colour)                   ; Semantic macro to call a 48K ROM routine
        if Colour=0                                     ;
                          xor a                         ;
        else                                            ;
                          ld a, Colour                  ;
        endif                                           ;
                          out ($FE), a                  ; Change border colour immediately
        if Colour<>0                                    ;
                          ld a, Colour*8                ;
        endif                                           ;
                          ld (23624), a                 ; Makes the ROM respect the new border colour
                          mend                          ;

esxDOS                  macro(Command)                  ; Semantic macro to call an esxDOS routine
                          rst $08                       ; rst $08 is the instruction to call an esxDOS API function.
                          noflow                        ; Zeus normally warns when data might be executed, suppress.
                          db Command                    ; For esxDOS API calls, the data byte is the command number.
                          mend                          ;

M_P3DOS                 macro(Command, Bank)            ; Semantic macro to call an NextZXOS routine via the esxDOS API
                          exx                           ; M_P3DOS: See NextZXOS_API.pdf page 37
                          ld de, Command                ; DE=+3DOS/IDEDOS/NextZXOS call ID
                          ld c, Bank                    ; C=RAM bank that needs to be paged (usually 7, but 0 for some calls)
                          esxDOS($94)                   ; esxDOS API: M_P3DOS ($94)
                          mend                          ;

F_READ                  macro(Address)                  ; Semantic macro to call an esxDOS routine
                          ; In: BC=bytes to read
                          ld a, (FileHandle)            ; A=file handle
                          ld ix, Address                ; IX=address
                          esxDOS($9D)                   ;
                          mend                          ;


; Raise an assembly-time error if the expression evaluates false
zeusassert              zeusver<=76, "Upgrade to Zeus v4.00 (TEST ONLY) or above, available at http://www.desdes.com/products/oldfiles/zeustest.exe";

; Generate a NEX file                                   ; Instruct the .NEX loader to write the file handle to this
                        output_z80 "NxtMail.z80",$FF40, Main ; ;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                        output_nex "NxtMail.nex", $FF40, Main ; Generate the file, with SP argument followed PC;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                        ; Zeus "just knows" which 16K banks to include in the .NEX file,
                        ; making generation a one-liner if you don't want loading screens
                        ; or external palette files. See History/Documentation in Zeus
                        ; for complete instructions and syntax.
;
                        zeussyntaxhighlight 0, $00,$FF,$11, true ; Set the token colour
                        zeussyntaxhighlight 1, $FF,$00,$FF, false ; Set the identifier colour
                        zeussyntaxhighlight 2, $00,$C0,$00, false ; Set the comment colour
                        zeussyntaxhighlight 3, $0,$FF,$AA, false ; Set the constant colour
                        zeussyntaxhighlight 4, $00,$FF,$00, true ; Set the line number colour
                        zeussyntaxhighlight 5, $FF,$FF,$FF, true ; Set the marker colour
                        zeussyntaxhighlight 6, $FF,$00,$FF ; Set the error colour
                        zeussyntaxhighlight 7, $ff,$FF,$FF ; Set the margin data colour

                        zeussyntaxhighlight 249, $00,$00,$A0 ; Set the "marked line" colour. [not used in this version]
                        zeussyntaxhighlight 250, $ff,$ff,$00 ; Set the margin separator line colour
                        zeussyntaxhighlight 251, $00,$00,$C8 ; Set the margin separator line2 colour
                        zeussyntaxhighlight 252, $22,$22,$00 ; Set the current executing line background colour
                        zeussyntaxhighlight 253, $22,$22,$aa ; Set the current editing line background colour
                        zeussyntaxhighlight 254, $00,$00,$00 ; Set the margin background colour
                        zeussyntaxhighlight 255, $00,$00,$00 ; Set the editor background colour


; $028e.  5  KEY_SCAN   {001} the keyboard scanning subroutine
; On returning from $028e KEY_SCAN the DE register and the Zero flag indicate
; which keys are being pressed.
;
; . The Zero flag is reset if pressing more than two keys, or pressing two
;  keys and neither is a shift key; DE identifies two of the keys.
; . The Zero flag is set otherwise, and DE identifies the keys.
; . If pressing just the two shift keys then DE = $2718.
; . If pressing one shift key and one other key, then D identifies the shift
;   key and E identifies the other key.
; . If pressing any one key, then D=$ff and E identifies the key.
; . If pressing no key, then DE=$ffff.
;
; The key codes returned by KEY_SCAN are shown below.
;
; KEY_SCAN key codes: hex, decimal, binary
; ? hh dd bbbbbbbb   ? hh dd bbbbbbbb   ? hh dd bbbbbbbb   ? hh dd bbbbbbbb
; 1 24 36 00100011   Q 25 37 00100101   A 26 38 00100110  CS 27 39 00100111
; 2 1c 28 00011100   W 1d 29 00011101   S 1e 30 00011110   Z 1f 31 00011111
; 3 14 20 00010100   E 15 21 00010101   D 16 22 00010110   X 17 23 00010111
; 4 0c 12 00001100   R 0d 13 00001101   F 0e 14 00001110   C 0f 15 00001111
; 5 04  4 00000100   T 05  5 00000101   G 06  6 00000110   V 07  7 00000111
; 6 03  3 00000011   Y 02  2 00000010   H 01  1 00000001   B 00  0 00000000
; 7 0b 11 00001011   U 0a 10 00001010   J 09  9 00001001   N 08  8 00001000
; 8 13 19 00010011   I 12 18 00010010   K 11 17 00010001   M 10 16 00010000
; 9 1b 27 00011011   O 1a 26 00011010   L 19 25 00011001  SS 18 24 00011000
; 0 23 35 00100011   P 22 34 00100010  EN 21 33 00100001  SP 20 32 00100000
; SS + 0 = delete
