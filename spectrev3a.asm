BITS 64
DEFAULT REL

GLOBAL main

EXTERN printf
EXTERN signal
EXTERN exit

;Space between lines in the buffer
%define GAP (0)

%macro WARMUP 0

 push rbx
 push rax
 mov eax, 1000000

 %%loop:
  vaddps ymm0, ymm0, ymm1
  vsqrtps ymm3, ymm3
  imul rbx, rbx
  vaddps ymm2, ymm2, ymm4
  vsqrtps ymm5, ymm5
  imul rbx, rbx
 
  dec eax
 jnz %%loop

 pop rax
 pop rbx

%endmacro

SECTION .bss ALIGN=4096

 

 buffer: 	resb 256 * (1 + GAP) * 64	


SECTION .data

 timings_data:	TIMES 256 dd 0


 strNewLine	db `\n0x%02x: `, 0
 strHalfLine	db "  ", 0
 strTiming	db `\e[48;5;16`,
  .importance	db "0",
		db `m\e[38;5;15m%03u\e[0m `, 0  

 strEnd		db `\n\n`, 0

SECTION .text

;'._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .' 
;   '     '     '     '     '     '     '     '     '     '     '   
; _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \ 
;/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \
;
;
;FLUSH ALL THE LINES OF A BUFFER FROM THE CACHES
;
;

flush_all:
 lea rdi, [buffer]	;Start pointer
 mov esi, 256		;How many lines to flush
 
.flush_loop:
  lfence		;Prevent the previous clflush to be reordered after the load
  mov eax, [rdi]	;Touch the page
  lfence		;Prevent the current clflush to be reordered before the load
  
  clflush  [rdi]	;Flush a line
  add rdi, (1 + GAP)*64	;Move to the next line

  dec esi
 jnz .flush_loop	;Repeat
  
 lfence			;clflush are ordered with respect of fences ..
			;.. and lfence is ordered (locally) with respect of all instructions
 ret


;'._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .' 
;   '     '     '     '     '     '     '     '     '     '     '   
; _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \ 
;/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \
;
;
;PROFILE THE ACCESS TO EVERY LINE OF THE BUFFER
;
;


profile:
 lea rdi, [buffer]		;Pointer to the buffer
 mov esi, 256			;How many lines to test
 lea r8, [timings_data]		;Pointer to timings results

 ;mov DWORD [buffer + (1+GAP)*64 * 0], 1

 mfence				;I'm pretty sure this is useless, but I included it to rule out ..
				;.. silly, hard to debug, scenarios

.profile: 
  mfence
  rdtscp
  lfence			;Read the TSC in-order (ignoring stores global visibility)

  mov ebp, eax			;Read the low DWORD only (this is a short delay)

  ;PERFORM THE LOADING
  mov eax, DWORD [rdi]

  rdtscp
  lfence			;Again, read the TSC in-order
  
  sub eax, ebp			;Compute the delta
  
  mov DWORD [r8], eax		;Save it

  ;Advance the loop

  add r8, 4			;Move the results pointer
  add rdi, (1 + GAP)*64		;Move to the next line

  dec esi			;Advance the loop
 jnz .profile

 ret

;'._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .' 
;   '     '     '     '     '     '     '     '     '     '     '   
; _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \ 
;/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \
;
;
;SHOW THE RESULTS
;
;

show_results:
 lea rbx, [timings_data]	;Pointer to the timings
 xor r12, r12			;Counter (up to 256)
 mov r10d, 78			;Used to compute the color 

.print_line:

 ;Format the output

 xor eax, eax
 mov esi, r12d
 lea rdi, [strNewLine]		;Setup for a call to printf

 test r12d, 0fh
 jz .print			;Test if counter is a multiple of 16

 lea rdi, [strHalfLine]		;Setup for a call to printf

 test r12d, 07h			;Test if counter is a multiple of 8
 jz .print

.print_timing:

  ;Print
  mov esi, DWORD [rbx]		;Timing value

  ;Compute the color
  mov eax, esi
  xor edx, edx
  div r10d			;eax = Timing value / 78

  ;Update the color 

  mov edx, '6'
  add al, '0'
  cmp eax, edx
  cmova eax, edx
  mov BYTE [strTiming.importance], al

  xor eax, eax
  lea rdi, [strTiming]
  call printf WRT ..plt		;Print a 3-digits number

  ;Advance the loop	

  inc r12d			;Increment the counter
  add rbx, 4			;Move to the next timing
  cmp r12d, 256
 jb .print_line			;Advance the loop

  xor eax, eax
  lea rdi, [strEnd]
  call printf WRT ..plt		;Print a new line

  ret

.print:
  
  call printf WRT ..plt		;Print a string

jmp .print_timing

;'._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .' 
;   '     '     '     '     '     '     '     '     '     '     '   
; _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \ 
;/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \
;
;
;E N T R Y   P O I N T
;
;
;'._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .''._ .' 
;   '     '     '     '     '     '     '     '     '     '     '   
; _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \  _' \ 
;/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \/    \

main:

 ;Flush all the lines of the buffer
 call flush_all
 
 ;Test the access times
 call profile

 ;Show the results
 call show_results

 ;Exit
 xor edi, edi
 call exit WRT ..plt
