; parse.asm

;  Copyright 2019-2020 Robin Verhagen-Guest
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;
;     http://www.apache.org/licenses/LICENSE-2.0
;
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.



GetBufferLength         proc
                        push hl
                        ld bc, BufferLen
                        xor a
                        cpir
                        dec hl
                        pop de
                        push de
                        sbc hl, de
                        ld e, l
                        pop hl
                        ret
pend

NextRegReadProc         proc
                        out (c), a
                        inc b
                        in a, (c)
                        ret
pend

ReadAndCheckDigit       proc
                        ld a, (hl)
                        cp '0'
                        ret c                           ; Return with carry set if < 0
                        cp '9'+1
                        jr nc, Err                      ; Return with carry set if > 9
                        or a
                        ret                             ; Return with carry clear if 0..9
Err:                    scf
                        ret
pend

WaitFramesProc          proc
                        ei
Loop:                   halt
                        djnz Loop
                        di
                        ret
pend

